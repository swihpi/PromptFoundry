import Foundation

public enum PromptComparison {
    public enum Kind { case unchanged, added, removed }
    public struct Line {
        public let kind: Kind
        public let text: String
    }
    public static func lines(before: String, after: String) -> [Line] {
        let old = before.components(separatedBy: "\n")
        let new = after.components(separatedBy: "\n")
        let difference = new.difference(from: old)
        var removed = Set<Int>(), added = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }
        var output: [Line] = [], i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count && removed.contains(i) { output.append(Line(kind: .removed, text: "− " + old[i])); i += 1 }
            else if j < new.count && added.contains(j) { output.append(Line(kind: .added, text: "+ " + new[j])); j += 1 }
            else if j < new.count { output.append(Line(kind: .unchanged, text: "  " + new[j])); i += 1; j += 1 }
            else { break }
        }
        return output
    }
}
