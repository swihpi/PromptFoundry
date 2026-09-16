import Foundation

public final class CodexAppServerService: CodexServicing, PromptRefining {
    private let locator: CodexExecutableLocating
    private var client: AppServerProcess?
    private let lock = NSLock()

    public init(locator: CodexExecutableLocating = DefaultCodexExecutableLocator()) {
        self.locator = locator
    }

    public func connectionStatus() async -> CodexConnectionStatus {
        guard let executable = locator.locate() else { return .unavailable(message: PromptFoundryError.codexNotInstalled.localizedDescription) }
        do {
            let version = try Self.run(executable: executable, arguments: ["--version"])
            let login = try Self.run(executable: executable, arguments: ["login", "status"])
            guard login.localizedCaseInsensitiveContains("logged in") else {
                return .unavailable(message: PromptFoundryError.codexNotAuthenticated.localizedDescription)
            }
            return .connected(version: version.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .unavailable(message: error.localizedDescription)
        }
    }

    public func availableModels() async throws -> [ModelDescriptor] {
        let response = try await appServer().request(method: "model/list", params: ["limit": 100, "includeHidden": false])
        let data = response["data"] as? [[String: Any]] ?? []
        return data.compactMap { model in
            guard let id = (model["model"] as? String) ?? (model["id"] as? String) else { return nil }
            let efforts = (model["supportedReasoningEfforts"] as? [[String: Any]] ?? []).compactMap {
                ($0["reasoningEffort"] as? String).flatMap(ReasoningEffort.init(rawValue:))
                    ?? ($0["effort"] as? String).flatMap(ReasoningEffort.init(rawValue:))
            }
            return ModelDescriptor(
                id: id,
                displayName: model["displayName"] as? String ?? id,
                description: model["description"] as? String ?? "Available in Codex",
                tier: ModelCatalog.tier(for: id),
                supportedEfforts: efforts.isEmpty ? ModelCatalog.defaultEfforts(for: id) : efforts,
                available: !(model["hidden"] as? Bool ?? false)
            )
        }
    }

    public func createTask(_ request: CodexTaskRequest) async throws -> CodexTaskResult {
        try validate(request)
        let response = try await appServer().request(method: "thread/start", params: CodexRequestBuilder.threadStart(request))
        guard let thread = response["thread"] as? [String: Any], let threadID = thread["id"] as? String else {
            throw PromptFoundryError.codexUnavailable("The app-server did not return a task identifier.")
        }
        _ = try? await appServer().request(method: "thread/settings/update", params: CodexRequestBuilder.threadSettings(request, threadID: threadID))
        return CodexTaskResult(threadID: threadID)
    }

    public func runTask(_ request: CodexTaskRequest) async throws -> CodexTaskResult {
        let created = try await createTask(request)
        let server = try appServer()
        let response = try await server.request(method: "turn/start", params: CodexRequestBuilder.turnStart(request, threadID: created.threadID))
        let turnID = (response["turn"] as? [String: Any])?["id"] as? String
        guard let turnID else { throw PromptFoundryError.codexUnavailable("The app-server did not confirm task execution.") }
        _ = try await server.request(
            method: "thread/unsubscribe",
            params: CodexRequestBuilder.threadUnsubscribe(threadID: created.threadID)
        )
        return CodexTaskResult(threadID: created.threadID, turnID: turnID)
    }

    public func refine(_ request: PromptRefinementRequest) -> AsyncThrowingStream<PromptRefinementEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var threadID: String?
                var turnID: String?
                do {
                    continuation.yield(.started)
                    let server = try appServer()
                    let threadResponse = try await server.request(
                        method: "thread/start",
                        params: CodexRefinementRequestBuilder.threadStart(request)
                    )
                    guard let thread = threadResponse["thread"] as? [String: Any],
                          let createdThreadID = thread["id"] as? String else {
                        throw PromptFoundryError.codexRefinementUnavailable("The app-server did not return a private refinement task identifier.")
                    }
                    threadID = createdThreadID
                    let turnResponse = try await server.request(
                        method: "turn/start",
                        params: CodexRefinementRequestBuilder.turnStart(request, threadID: createdThreadID)
                    )
                    guard let turn = turnResponse["turn"] as? [String: Any],
                          let createdTurnID = turn["id"] as? String else {
                        throw PromptFoundryError.codexRefinementUnavailable("The app-server did not start prompt refinement.")
                    }
                    turnID = createdTurnID

                    var raw = ""
                    var lastPartial = ""
                    for try await event in server.events(threadID: createdThreadID, turnID: createdTurnID) {
                        try Task.checkCancellation()
                        switch event {
                        case .delta(_, _, let text):
                            raw += text
                            if let partial = PromptResponseParser.partialProfessionalPrompt(from: raw), partial != lastPartial {
                                let addition = String(partial.dropFirst(lastPartial.count))
                                lastPartial = partial
                                if !addition.isEmpty { continuation.yield(.delta(addition)) }
                            }
                        case .messageCompleted(_, _, let text):
                            if !text.isEmpty { raw = text }
                        case .turnCompleted(_, _, let status, let detail):
                            if status == "interrupted" || status == "cancelled" { throw PromptFoundryError.cancelled }
                            guard status == "completed" else {
                                throw PromptFoundryError.codexRefinementUnavailable(detail ?? "The refinement turn ended with status \(status).")
                            }
                            let parsed = try PromptResponseParser.parse(raw)
                            continuation.yield(.completed(parsed, rawResponse: raw))
                            continuation.finish()
                            return
                        }
                    }
                    throw PromptFoundryError.codexRefinementUnavailable("The refinement stream closed before completion.")
                } catch is CancellationError {
                    if let threadID, let turnID {
                        _ = try? await self.appServer().request(method: "turn/interrupt", params: ["threadId": threadID, "turnId": turnID])
                    }
                    continuation.finish(throwing: PromptFoundryError.cancelled)
                } catch let error as PromptFoundryError {
                    if case .codexUnavailable(let detail) = error {
                        continuation.finish(throwing: PromptFoundryError.codexRefinementUnavailable(detail))
                    } else {
                        continuation.finish(throwing: error)
                    }
                } catch {
                    continuation.finish(throwing: PromptFoundryError.codexRefinementUnavailable(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func validate(_ request: CodexTaskRequest) throws {
        var isDirectory: ObjCBool = false
        guard request.workingDirectory.hasPrefix("/"),
              FileManager.default.fileExists(atPath: request.workingDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PromptFoundryError.invalidWorkingDirectory
        }
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PromptFoundryError.codexUnavailable("The professional prompt is empty.")
        }
    }

    private func appServer() throws -> AppServerProcess {
        lock.lock(); defer { lock.unlock() }
        if let client { return client }
        guard let executable = locator.locate() else { throw PromptFoundryError.codexNotInstalled }
        let created = AppServerProcess(executableURL: executable)
        client = created
        return created
    }

    private static func run(executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let detail = errorText.isEmpty ? text : errorText
            throw PromptFoundryError.codexUnavailable(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? errorText : text
    }
}

public enum CodexRefinementRequestBuilder {
    public static func threadStart(_ request: PromptRefinementRequest) -> [String: Any] {
        [
            "cwd": FileManager.default.temporaryDirectory.path,
            "model": request.model,
            "sandbox": CodexSandbox.readOnly.rawValue,
            "approvalPolicy": "never",
            "ephemeral": true,
            "personality": "none",
            "threadSource": "PromptFoundry",
            "developerInstructions": PromptContract.instructions(for: request) + "\nDo not inspect files, run commands, call tools, or modify anything. Return only the JSON object required by the supplied output schema."
        ]
    }

    public static func turnStart(_ request: PromptRefinementRequest, threadID: String) -> [String: Any] {
        [
            "threadId": threadID,
            "input": [["type": "text", "text": PromptContract.inputText(for: request)]],
            "cwd": FileManager.default.temporaryDirectory.path,
            "model": request.model,
            "effort": request.reasoning.rawValue,
            "approvalPolicy": "never",
            "outputSchema": PromptContract.jsonSchema,
            "turnTrigger": "PromptFoundry/refine"
        ]
    }
}

public enum CodexRequestBuilder {
    public static func threadStart(_ request: CodexTaskRequest) -> [String: Any] {
        [
            "cwd": request.workingDirectory,
            "model": request.model,
            "sandbox": request.sandbox.rawValue,
            "approvalPolicy": request.approvalPolicy,
            "ephemeral": false,
            "threadSource": "PromptFoundry"
        ]
    }

    public static func threadSettings(_ request: CodexTaskRequest, threadID: String) -> [String: Any] {
        [
            "threadId": threadID,
            "effort": request.reasoning.rawValue,
            "model": request.model,
            "cwd": request.workingDirectory,
            "approvalPolicy": request.approvalPolicy
        ]
    }

    public static func turnStart(_ request: CodexTaskRequest, threadID: String) -> [String: Any] {
        [
            "threadId": threadID,
            "input": [["type": "text", "text": request.prompt]],
            "cwd": request.workingDirectory,
            "model": request.model,
            "effort": request.reasoning.rawValue,
            "approvalPolicy": request.approvalPolicy
        ]
    }

    public static func threadUnsubscribe(threadID: String) -> [String: Any] {
        ["threadId": threadID]
    }
}

public protocol CodexExecutableLocating {
    func locate() -> URL?
}

public struct DefaultCodexExecutableLocator: CodexExecutableLocating {
    public init() {}
    public func locate() -> URL? {
        var candidates: [String] = []
        if let configured = UserDefaults.standard.string(forKey: "codexExecutablePath"), !configured.isEmpty {
            candidates.append(configured)
        }
        candidates += [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { String($0) + "/codex" }
        }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }
}

final class AppServerProcess: @unchecked Sendable {
    private let executableURL: URL
    private let stateQueue = DispatchQueue(label: "app.promptfoundry.PromptFoundry.appserver")
    private var process: Process?
    private var inputHandle: FileHandle?
    private var buffer = Data()
    private var errorBuffer = Data()
    private var nextID = 1
    private var initialized = false
    private var continuations: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var turnContinuations: [String: AsyncThrowingStream<AppServerTurnEvent, Error>.Continuation] = [:]
    private var eventBacklog: [AppServerTurnEvent] = []

    init(executableURL: URL) { self.executableURL = executableURL }

    deinit { process?.terminate() }

    func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        try await ensureInitialized()
        return try await sendRequest(method: method, params: params)
    }

    func events(threadID: String, turnID: String) -> AsyncThrowingStream<AppServerTurnEvent, Error> {
        AsyncThrowingStream { continuation in
            stateQueue.async {
                let queued = self.eventBacklog.filter { $0.threadID == threadID && $0.turnID == turnID }
                self.eventBacklog.removeAll { $0.threadID == threadID && $0.turnID == turnID }
                queued.forEach { continuation.yield($0) }
                if queued.contains(where: \.isTerminal) {
                    continuation.finish()
                } else {
                    self.turnContinuations[turnID] = continuation
                }
            }
            continuation.onTermination = { [weak self] _ in
                self?.stateQueue.async { self?.turnContinuations.removeValue(forKey: turnID) }
            }
        }
    }

    private func ensureInitialized() async throws {
        if stateQueue.sync(execute: { initialized }) { return }
        try launchIfNeeded()
        _ = try await sendRequest(method: "initialize", params: [
            "clientInfo": ["name": "PromptFoundry", "title": "PromptFoundry", "version": "1.0.0"]
        ])
        try sendNotification(method: "initialized", params: [:])
        stateQueue.sync { initialized = true }
    }

    private func launchIfNeeded() throws {
        if stateQueue.sync(execute: { self.process?.isRunning == true }) { return }
        let newProcess = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        newProcess.executableURL = executableURL
        newProcess.arguments = ["app-server", "--stdio"]
        newProcess.standardInput = input
        newProcess.standardOutput = output
        newProcess.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.stateQueue.async { self?.errorBuffer.append(data) }
        }
        newProcess.terminationHandler = { [weak self] _ in self?.failPending() }
        try newProcess.run()
        stateQueue.sync {
            self.process = newProcess
            inputHandle = input.fileHandleForWriting
        }
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        let id = stateQueue.sync { let value = nextID; nextID += 1; return value }
        return try await withCheckedThrowingContinuation { continuation in
            stateQueue.sync { continuations[id] = continuation }
            do { try write(["id": id, "method": method, "params": params]) }
            catch {
                _ = stateQueue.sync { continuations.removeValue(forKey: id) }
                continuation.resume(throwing: error)
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        try write(["method": method, "params": params])
    }

    private func write(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        guard let inputHandle = stateQueue.sync(execute: { inputHandle }) else {
            throw PromptFoundryError.codexUnavailable("The app-server input channel is unavailable.")
        }
        try inputHandle.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        stateQueue.async {
            self.buffer.append(data)
            while let newline = self.buffer.firstIndex(of: 0x0A) {
                let line = self.buffer.prefix(upTo: newline)
                self.buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if let id = object["id"] as? Int, let continuation = self.continuations.removeValue(forKey: id) {
                    if let error = object["error"] as? [String: Any] {
                        continuation.resume(throwing: PromptFoundryError.codexUnavailable(error["message"] as? String ?? "Unknown app-server error"))
                    } else {
                        continuation.resume(returning: object["result"] as? [String: Any] ?? [:])
                    }
                } else if let method = object["method"] as? String, let params = object["params"] as? [String: Any] {
                    self.consumeNotification(method: method, params: params)
                }
            }
        }
    }

    private func consumeNotification(method: String, params: [String: Any]) {
        switch method {
        case "item/agentMessage/delta":
            guard let threadID = params["threadId"] as? String,
                  let turnID = params["turnId"] as? String,
                  let delta = params["delta"] as? String else { return }
            publish(.delta(threadID: threadID, turnID: turnID, text: delta))
        case "item/completed":
            guard let threadID = params["threadId"] as? String,
                  let turnID = params["turnId"] as? String,
                  let item = params["item"] as? [String: Any],
                  item["type"] as? String == "agentMessage",
                  let text = item["text"] as? String else { return }
            publish(.messageCompleted(threadID: threadID, turnID: turnID, text: text))
        case "turn/completed":
            guard let threadID = params["threadId"] as? String,
                  let turn = params["turn"] as? [String: Any],
                  let turnID = turn["id"] as? String,
                  let status = turn["status"] as? String else { return }
            let detail = (turn["error"] as? [String: Any])?["message"] as? String
            publish(.turnCompleted(threadID: threadID, turnID: turnID, status: status, detail: detail))
        default:
            break
        }
    }

    private func publish(_ event: AppServerTurnEvent) {
        if let continuation = turnContinuations[event.turnID] {
            continuation.yield(event)
            if event.isTerminal {
                continuation.finish()
                turnContinuations.removeValue(forKey: event.turnID)
            }
        } else {
            eventBacklog.append(event)
            if eventBacklog.count > 1_000 { eventBacklog.removeFirst(eventBacklog.count - 1_000) }
        }
    }

    private func failPending() {
        stateQueue.async {
            let pending = self.continuations.values
            self.continuations.removeAll()
            let turnStreams = self.turnContinuations.values
            self.turnContinuations.removeAll()
            self.initialized = false
            let detail = String(data: self.errorBuffer, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.errorBuffer.removeAll()
            let message = (detail?.isEmpty == false) ? detail! : "The local app-server stopped unexpectedly."
            pending.forEach { $0.resume(throwing: PromptFoundryError.codexUnavailable(message)) }
            turnStreams.forEach { $0.finish(throwing: PromptFoundryError.codexUnavailable(message)) }
        }
    }
}

enum AppServerTurnEvent: Sendable {
    case delta(threadID: String, turnID: String, text: String)
    case messageCompleted(threadID: String, turnID: String, text: String)
    case turnCompleted(threadID: String, turnID: String, status: String, detail: String?)

    var threadID: String {
        switch self {
        case .delta(let value, _, _), .messageCompleted(let value, _, _), .turnCompleted(let value, _, _, _): return value
        }
    }

    var turnID: String {
        switch self {
        case .delta(_, let value, _), .messageCompleted(_, let value, _), .turnCompleted(_, let value, _, _): return value
        }
    }

    var isTerminal: Bool {
        if case .turnCompleted = self { return true }
        return false
    }
}
