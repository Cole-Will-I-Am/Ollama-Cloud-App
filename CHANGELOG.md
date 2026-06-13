# Changelog

## 2026-06-13 — releases 1.5.1 → 1.6.1

### Added: AI Debate (1.6.0)
- New **Debate** tab — the app is now a `TabView` (Chats | Debate) via `AppTabsView`.
- `DebateRunner` streams two models taking turns on a topic — **Debate** (for vs against) or **Discussion** — via `OllamaAPIClient.streamChat`, with an optional impartial closing **synthesis**.
- `DebateHomeView` (topic + two model pickers + format/rounds/synthesis + saved list) and `DebateRunView` (full-page streaming transcript, color-coded turns, Stop/Save).
- Debates persist to a JSON file (`DebateStore`), deliberately **not** a SwiftData `@Model` — avoids a schema migration/store reset.

### Added: Built-in model tools (1.5.4)
- `AssistantToolkit`: `calculator` + `run_javascript` (on-device, always available) and `fetch_url` (opt-in via **Settings > Chat > Web access**, off by default; blocks loopback/private hosts).
- Wired into `ChatView` tools + the `StreamingChatService` dispatch loop. Tuned the tools system-prompt guidance so models use them naturally without reciting them.

### Changed
- **SEER assistant (1.6.1):** backing model `qwen3.5:397b-cloud` → **`gpt-oss:120b`**; system prompt updated to cover the current feature set (Debate tab, model tools, Web access / Visualizations toggles).
- **Removed Projects / Code Workspace from the UI (1.5.3):** hid the Chats/Projects toggle and all entry points. `Project`/`ProjectFile` stay in the SwiftData schema (dormant) so the feature can return without a store reset. (The 1.5.2 file-upload-into-projects work is therefore currently dormant.)

### Fixed
- **(1.5.5)** Saved conversations were hidden from the list — the `isProjectChat != true` query excluded NULL rows in SwiftData's SQLite store; now matches `nil`/`false` explicitly, so chat history shows again.
- **(1.5.1)** Deleting a conversation mid-stream could crash / corrupt the store — cancel streaming on view teardown + guard persistence against a deleted conversation.
- **(1.5.1)** iOS JavaScript execution had no timeout — added a 10s watchdog so an infinite loop no longer hangs the Run spinner.
- **(1.5.1)** `move_file` could collide a directory's children → silent file loss; now rejected. Plus: tool-call-only replies no longer show a blank "No response", transient-retry no longer duplicates partial thinking, and `create_file` under an existing file no longer hides it.
- **(1.6.1)** Debate labels were over-tracked ("P r o p o n e n t") and the Debate setup keyboard wouldn't dismiss — normal label spacing + Done/scroll-to-dismiss.
- Consent gate: long tracked labels could run off-screen on narrow iPhones — scale-to-fit + padding.

## 2026-03-06

### Added: OpenAI API Provider Support

OpenAI is now available as a second provider alongside Ollama. Both can be active simultaneously.

1. **Settings**
- New "OPENAI" section with SecureField + CONNECT button to validate and store an API key.
- Connected state shows status and a REMOVE OPENAI KEY button.
- Key stored in Keychain as `openai_api_key`.

2. **Model picker**
- Fetches models from both Ollama and OpenAI in parallel.
- Non-favorite models grouped by provider with "OLLAMA" and "OPENAI" section headers.
- Removed capability tags (FAST, REASON, CODE, etc.) from model rows.

3. **Streaming**
- New `OpenAIAPIClient` actor targeting `api.openai.com` with SSE stream parsing.
- `StreamingChatService` routes by provider: Ollama uses existing JSONL path, OpenAI uses SSE with incremental tool call delta accumulation.
- SEER-specific logic (model resolution, thinking, scaffolds, preflight) skipped for OpenAI models.

4. **Data model**
- `APIProvider` enum (`.ollama`, `.openai`).
- `OllamaModel` gains a `provider` field; `id` scoped to `"{provider}:{name}"`.
- `Conversation` gains `apiProviderRaw` (nil defaults to `.ollama` for backward compatibility).
- Provider set on model selection in both `ChatView` and `RootView`.

## 2026-03-06 (WIP)

### Added: Code Workspace — In-App Project IDE

A full project-based coding environment has been added alongside the existing chat mode.

1. **Project management**
- New `Project` and `ProjectFile` SwiftData models for in-memory project storage.
- `ProjectListView` with create, rename, swipe-to-delete, and file count/timestamp display.
- Sidebar mode switcher (Chats | Projects) in `RootView`.

2. **CodeToolkit — 8 built-in file tools**
- `create_file`, `write_file`, `edit_file`, `read_file`, `delete_file`, `create_directory`, `list_files`, `move_file`.
- Exposed to models via Ollama tool calling; edits persist immediately to SwiftData.
- Integrated into `StreamingChatService` dispatch chain (VisualsToolkit → CodeToolkit → MCP).

3. **CodeMirror 6 editor**
- `CodeEditorView`: cross-platform WKWebView wrapper with CodeMirror 6 via ESM CDN.
- Syntax highlighting for 15+ languages, dark OLED theme matching the app.
- 300ms debounced content sync — user edits are immediately available to models via `read_file`.

4. **Workspace layout**
- `CodeWorkspaceView`: sidebar file tree, tab bar for multi-file editing, collapsible bottom chat panel.
- Adaptive layout: compact (iPhone sheets) vs. regular (iPad/macOS side-by-side).
- `ProjectChatPanel`: embedded chat with auto-merged CodeToolkit + VisualsToolkit + MCP tools.

5. **File tree with connector lines**
- `FileTreeView` renders a minimal tree diagram with thin 0.5pt connector lines (├── └── │).
- Names only — no file type icons. Subtle chevron for directory expand/collapse.
- Context menu for rename, delete, and new file creation.

6. **Code block extraction**
- `CodeBlockExtractor` parses assistant messages for fenced code blocks (supports streaming).
- `CodeBlockOutputView` displays extracted blocks with "Save to File" for quick project integration.

7. **ZIP export**
- `ProjectExporter`: exports project as `.zip` — macOS uses `NSSavePanel`, iOS uses share sheet.

8. **Conversation isolation**
- Each project has a hidden linked `Conversation` (`isProjectChat` flag) excluded from the chat list.
- Project auto-renames based on the first user message.

## 2026-03-06 10:17:42 EST

### Added: Conversation Branching

The changes add **conversation branching** so edits/regenerations don't delete history.

1. **Data model now supports a message tree**
- Each `Message` can point to a `parentID`.
- `Conversation` tracks `activeLeafID` (the currently selected branch tip).
- `activeBranchMessages` shows only the selected branch path from root to leaf.

2. **Sending is now branch-aware**
- `sendMessage(...)` accepts `parentMessageID`.
- New user/tool/assistant messages are linked into that branch via `parentID`.
- API prompt history is built from the active branch, not full global message list.
- Retry keeps the same parent pointer, so retries stay on the same branch.

3. **Edit/regenerate are non-destructive**
- **Edit Prompt** restores old prompt into input and sets a fork parent instead of deleting later messages.
- **Regenerate** re-asks from the original user message and creates a sibling assistant branch.
- Normal send uses `forkParentID ?? activeLeafID` to continue current branch or forked point.

4. **UI branch switching**
- Message rows can show a sibling switcher (`◂ n of m ▸`) when alternatives exist.
- Clicking arrows switches the active branch to that sibling path.
- Includes wrap-around cycling and haptic feedback.

5. **macOS keyboard shortcuts**
- Added Chat menu commands:
  - `Cmd+Shift+[` = previous branch
  - `Cmd+Shift+]` = next branch
- Shortcuts cycle through siblings at the deepest fork in the active path.

## 2026-03-06 10:59:25 EST

### Added: Visuals Toolkit and HTML Tool Rendering

The changes add built-in **visualization tooling** and in-chat HTML rendering for rich tool outputs.

1. **Tool schema and JSON parsing expanded**
- `ChatToolProperty` now supports `items` for array schemas via `ChatToolPropertyItems`.
- `JSONValue` now includes convenience accessors: `stringValue`, `numberValue`, `intValue`, `boolValue`, `arrayValue`, and `objectValue`.

2. **Built-in visuals toolset added**
- Added `VisualsToolkit.swift` with 18 visualization tool definitions.
- Tools return generated HTML with dark-theme Plotly.js charts aligned to SEER's `#080810` theme.
- Model discovers and calls these via standard Ollama tool calling (no system prompt injection).

3. **Service execution path updated**
- Tool execution loop in `StreamingChatService` is no longer limited to macOS compilation guards.
- Dispatch now checks `VisualsToolkit.handles()` before falling back to MCP handling.
- Built-in tools execute on both iOS and macOS, while MCP tools remain macOS-only.

4. **Tool availability wired into send flows**
- `send()`, `retryLast()`, and `requestRegenerate()` in `ChatView` now merge `VisualsToolkit.tools` with MCP tools.
- Existing MCP tool behavior remains intact for backward compatibility.

5. **HTML tool results now render inline**
- Added `HTMLContentView.swift` as a cross-platform SwiftUI `WKWebView` wrapper (`UIViewRepresentable`/`NSViewRepresentable`).
- `ToolResultBubble` detects HTML content, auto-expands, and renders interactive HTML output with tool-specific heights.
