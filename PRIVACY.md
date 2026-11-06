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

The historical V1 Codex screenshot is cropped to exclude the task sidebar. Its handoff-review screenshot excludes the personal working-directory value. V2 screenshots use a neutral reading-list app example, filter out unrelated library entries, and show a generic `/tmp/PromptFoundry-Example` folder in the handoff review. No screenshot includes personal account information or the surrounding desktop.

The five setup screenshots show generic application locations and tilde-abbreviated home-folder paths. They do not expose the producing Mac's account name or unrelated desktop content.

The application stores prompt history locally and uses macOS Keychain for optional API credentials. The default refinement path uses the user's signed-in local Codex installation through `codex app-server`; PromptFoundry checks connection state but does not read or copy Codex authentication files. See the main README for the architecture and first-launch flow.

Local storage does not mean offline inference: prompt refinement sends the brief and selected context through the chosen Codex or API provider. File references contribute filenames by default. V2's explicit Use contents selection sends supported file text with the next request. Clarification answers are stored in Additional Context and included in subsequent refinement. Content selections reset on changing prompts. The final handoff review shows referenced file paths before sending to Codex.

V2 uses a separate prompt database and preferences. Its one-time library import opens the original store without saving and copies the library into V2. The original store is retained; subsequent changes do not synchronize between the two applications. Credentials and Keychain data are not part of the import.
