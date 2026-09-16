# Privacy notes for this project

This repository contains PromptFoundry's source code, build and verification scripts, product documentation, and selected privacy-safe screenshots. The compiled DMG is distributed through GitHub Releases rather than committed to Git history.

It does not contain:

- user prompt-history databases or exports
- API keys, tokens, cookies, or credentials
- macOS Keychain data
- personal documents or attachments
- private Codex task identifiers
- local usernames or unredacted personal filesystem paths
- Apple Developer certificates, provisioning profiles, or signing identities
- compiled app bundles, DMGs, Swift build caches, logs, or local databases

The Codex screenshot is cropped to exclude the chat sidebar. The handoff-review screenshot excludes the working-directory value so no personal local path is shown.

The five setup screenshots show generic application locations and tilde-abbreviated home-folder paths. They do not expose the producing Mac's account name or unrelated desktop content.

The application stores prompt history locally and uses macOS Keychain for optional API credentials. The default refinement path uses the user's signed-in local Codex installation through `codex app-server`; PromptFoundry checks connection state but does not read or copy Codex authentication files. See the main README for the architecture and first-launch flow.
