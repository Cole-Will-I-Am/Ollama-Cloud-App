# Code Workspace — Technical Report

> ⚠️ **Removed from the UI (2026-06-13).** The Projects / Code Workspace feature
> was hidden from the app (the Chats/Projects toggle and entry points were
> removed). The code and SwiftData models remain in the repo (dormant) so it can
> be revived without a store migration; this doc describes that dormant feature.
>
> **Feature:** VS Code-like "Code" mode for SEER
> **Date:** 2026-03-06
> **Status:** Implemented; currently removed from the UI (dormant)
> **Platforms:** iOS 17+ / macOS 14+

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Data Models](#data-models)
4. [CodeToolkit — Built-in Tools](#codetoolkit--built-in-tools)
5. [Streaming Service Integration](#streaming-service-integration)
6. [Navigation — Sidebar Mode Switch](#navigation--sidebar-mode-switch)
7. [Views — Workspace UI](#views--workspace-ui)
8. [Export](#export)
9. [File Inventory](#file-inventory)
10. [Cross-Platform Considerations](#cross-platform-considerations)
11. [Data Flow Diagrams](#data-flow-diagrams)
12. [Known Limitations & Risks](#known-limitations--risks)
13. [QA Test Matrix](#qa-test-matrix)
14. [Future Work](#future-work)

---

## Overview

Code Workspace adds a standalone project system to SEER where users can create coding projects and have AI models build entire applications via Ollama's tool calling interface. Projects are independent of conversations — they have their own file tree, a CodeMirror-powered code editor, and an embedded chat panel. Models discover file operations (create, read, edit, delete, move files) through the same tool calling pattern used by VisualsToolkit.

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Project storage | SwiftData (same as conversations) | No new persistence layer; files stored as model objects, not on disk |
| Project vs conversation | Standalone (not per-conversation) | Projects persist independently; can switch models; cleaner mental model |
| File editing | CodeMirror 6 via WKWebView | Syntax highlighting for 15+ languages; cross-platform; dark theme |
| Tool pattern | Same as VisualsToolkit (static enum) | Consistent architecture; models discover tools via Ollama schema |
| Chat panel | Embedded, uses a hidden Conversation | Reuses the entire message persistence and streaming infrastructure |
| Export format | .zip archive | Universal; macOS uses `/usr/bin/zip`, iOS uses `NSFileCoordinator` |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ RootView (MainAppView)                                          │
│  ├── Segmented Picker: [Chats | Projects]                       │
│  ├── Sidebar:                                                   │
│  │   ├── ConversationListView (when Chats)                      │
│  │   └── ProjectListView (when Projects)                        │
│  └── Detail:                                                    │
│      ├── ChatView (when Chats + selected conversation)          │
│      └── CodeWorkspaceView (when Projects + selected project)   │
│           ├── FileTreeView (left sidebar, 200pt)                │
│           ├── Editor Area (CodeEditorView + tab bar)             │
│           └── ProjectChatPanel (bottom, collapsible)             │
└─────────────────────────────────────────────────────────────────┘
```

### Model-Tool Interaction Flow

```
User types in ProjectChatPanel
    │
    ▼
ProjectChatPanel.sendMessage()
    │  merges: VisualsToolkit.tools + CodeToolkit.tools + MCP tools
    │
    ▼
StreamingChatService.sendMessage(project: project, ...)
    │
    ▼
Ollama API (streaming response with tool_calls)
    │
    ▼
Tool dispatch chain (StreamingChatService lines ~357-377):
    1. VisualsToolkit.handles(name)?  → VisualsToolkit.execute()
    2. CodeToolkit.handles(name)?     → CodeToolkit.execute(project:modelContext:)
    3. MCP fallback (macOS only)      → mcpManager.callTool()
    4. Unknown tool                   → error message
    │
    ▼
Tool result persisted as Message(role: "tool")
    │
    ▼
Re-stream with tool results → model sees file operation output
    │
    ▼
SwiftData updates → FileTreeView/CodeEditorView observe changes live
```

---

## Data Models

### `Project` (`Models/Project.swift`)

```swift
@Model final class Project {
    var id: UUID
    var name: String                  // User-editable project name
    var accountScopeKey: String       // Multi-account isolation (same pattern as Conversation)
    var conversationID: UUID          // Links to a hidden Conversation for the chat panel
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ProjectFile.project)
    var files: [ProjectFile]          // Cascade-deletes all files when project is deleted
}
```

**Important:** `conversationID` is a UUID reference, not a SwiftData relationship. This is intentional — the Conversation is created separately and linked by ID. On project deletion, `ProjectListView.deleteProject()` manually fetches and deletes the linked Conversation.

### `ProjectFile` (`Models/ProjectFile.swift`)

```swift
@Model final class ProjectFile {
    var id: UUID
    var path: String              // Relative path from project root, e.g. "src/main.py"
    var content: String           // Full file content (empty string for directories)
    var isDirectory: Bool         // true = directory node, false = file
    var createdAt: Date
    var updatedAt: Date
    var project: Project?         // Inverse of Project.files
}
```

**Path conventions:**
- Forward slashes only (`src/utils/helpers.py`)
- No leading slash
- No `.` or `..` components (normalized on input by CodeToolkit)
- Directories are explicit records (not inferred from file paths alone)

### `Conversation` — Modified

Added one field:

```swift
var isProjectChat: Bool?    // nil/false = normal chat, true = hidden project chat
```

- Optional Bool (nil by default) — fully backward compatible, no migration needed
- SwiftData treats `nil` as falsy in predicates
- Filtered out of `ConversationListView` and `MainAppView` queries via `conversation.isProjectChat != true`

### Schema Registration

`OllamaCloudApp.swift` schema array now includes:

```swift
let schema = Schema([
    Conversation.self, Message.self, ReasoningScaffold.self,
    Project.self, ProjectFile.self
])
```

**Migration note:** Adding new models to an existing schema with `ModelConfiguration` is a lightweight migration — SwiftData creates the new tables automatically. The `isProjectChat` optional field on Conversation is also a lightweight migration (nullable column addition). No explicit migration plan is needed.

---

## CodeToolkit — Built-in Tools

### Location: `Services/CodeToolkit.swift`

### API Surface

```swift
enum CodeToolkit {
    static let tools: [ChatTool]           // 8 tool definitions for Ollama schema
    static let toolNames: Set<String>      // Fast lookup set
    static func handles(_ name: String) -> Bool
    static func execute(
        toolName: String,
        arguments: [String: JSONValue],
        project: Project,
        modelContext: ModelContext
    ) -> (content: String, isError: Bool)
}
```

### Tool Reference

| # | Tool Name | Required Params | Description | Returns on Success |
|---|-----------|----------------|-------------|-------------------|
| 1 | `create_file` | `path`, `content` | Creates a new file. Fails if file already exists. Auto-creates parent directories. | `"Created src/main.py (42 bytes)"` |
| 2 | `write_file` | `path`, `content` | Replaces file content. Creates if doesn't exist. Fails on directories. | `"Wrote src/main.py (42 bytes)"` |
| 3 | `edit_file` | `path`, `old_text`, `new_text` | Find-and-replace (first occurrence). | `"Edited src/main.py: replaced 10 chars with 15 chars"` |
| 4 | `read_file` | `path` | Returns file content. For directories, lists immediate children. | Raw file content string |
| 5 | `delete_file` | `path` | Deletes a file or empty directory. Non-empty dirs fail. | `"Deleted src/main.py"` |
| 6 | `create_directory` | `path` | Creates directory and parent dirs. | `"Created directory src/utils/"` |
| 7 | `list_files` | *(none)* | Returns ASCII tree of entire project. | Tree string (see below) |
| 8 | `move_file` | `old_path`, `new_path` | Moves/renames file or directory. Recursively updates children paths for directories. | `"Moved old/path → new/path"` |

### `list_files` Output Format

```
├── src/
│   ├── main.py
│   └── utils.py
├── tests/
│   └── test_main.py
└── README.md
```

Directories are sorted first, then alphabetical within each level.

### Path Normalization

All tools run paths through `normalizePath()`:
- Splits on `/`
- Strips `.` and empty components
- Resolves `..` by removing the previous path component (if any)
- Rejoins with `/`

Example: `"./src/../src/main.py"` → `"src/main.py"`

### Parent Directory Auto-Creation

`create_file`, `write_file`, `create_directory`, and `move_file` all call `ensureParentDirectories()` which:
1. Walks path components left to right
2. For each intermediate directory not already present, inserts a `ProjectFile(isDirectory: true)`
3. Does NOT save modelContext — caller is responsible for save

### Error Handling

Every tool returns `(content: String, isError: Bool)`. Error cases:
- Missing required parameters → `("Missing required parameter: path", true)`
- File not found → `("File not found: path", true)`
- File already exists (for `create_file`) → `("File already exists: path. Use write_file to overwrite.", true)`
- Writing to directory → `("Cannot write to a directory: path", true)`
- Non-empty directory delete → `("Directory not empty: path (N items). Delete contents first.", true)`
- `old_text` not found (for `edit_file`) → `("old_text not found in path", true)`
- Destination exists (for `move_file`) → `("Destination already exists: path", true)`
- Invalid source path (for `move_file`) → `("Invalid old_path", true)`
- Invalid destination path (for `move_file`) → `("Invalid new_path", true)`

The `isError` flag is currently consumed but not differentiated in the streaming service — error state is conveyed to the model through the text content itself (`_ = isError` on line ~389 of StreamingChatService).

### Tree String Builder

Uses a `final class TreeNode` (reference type) to build a nested tree from the flat file list, then renders with `├──`, `└──`, `│` connectors. The class-based approach avoids Swift's restriction on `&` inout references to nested value-type dictionaries.

---

## Streaming Service Integration

### Location: `Services/StreamingChatService.swift`

### Changes Made

**1. `sendMessage()` signature — new parameter:**
```swift
project: Project? = nil
```

Added after `mcpManager:`, before `conversation:`. Default `nil` means existing callers (normal ChatView) are unaffected.

**2. `retryLast()` signature — same addition:**
```swift
project: Project? = nil
```

Forwarded to `sendMessage()`.

**3. Built-in handler detection (line ~314):**

Before:
```swift
let hasBuiltinHandler = result.toolCalls.contains { VisualsToolkit.handles($0.function.name) }
```

After:
```swift
let hasBuiltinHandler = result.toolCalls.contains {
    VisualsToolkit.handles($0.function.name)
    || CodeToolkit.handles($0.function.name)
}
```

This ensures the tool round loop activates for CodeToolkit calls even without MCP.

**4. Tool dispatch chain (line ~357):**

New `else if` branch between VisualsToolkit and MCP:
```swift
} else if CodeToolkit.handles(toolName), let project {
    (resultText, isError) = CodeToolkit.execute(
        toolName: toolName,
        arguments: call.function.arguments,
        project: project,
        modelContext: modelContext
    )
} else {
```

**Dispatch order:**
1. VisualsToolkit (visualization tools)
2. CodeToolkit (file operation tools) — only if `project` is non-nil
3. MCP (macOS only, external tool servers)
4. Unknown tool fallback

### Tool Round Loop Behavior

The existing `toolRoundLoop` (max 10 rounds) handles CodeToolkit calls identically to VisualsToolkit:
- Tool call message persisted as `Message(role: "tool_call")`
- Each tool executed, result persisted as `Message(role: "tool")`
- `modelContext.save()` after each round
- Messages rebuilt and re-streamed to model
- Model sees tool results and can issue more tool calls

This means a model can chain operations: `create_directory` → `create_file` → `create_file` → `list_files` across multiple rounds, up to 10 total.

---

## Navigation — Sidebar Mode Switch

### Location: `App/RootView.swift`

### Changes to `MainAppView`

**New state:**
```swift
enum SidebarMode: String, CaseIterable { case chats, projects }
@State private var sidebarMode: SidebarMode = .chats
@State private var selectedProject: Project?
```

**Sidebar content:**

A `VStack` wraps a segmented picker and conditional content:
```swift
Picker("Mode", selection: $sidebarMode) {
    Text("Chats").tag(SidebarMode.chats)
    Text("Projects").tag(SidebarMode.projects)
}
.pickerStyle(.segmented)
```

Below the picker:
- `.chats` → `ConversationListView(selection: $selectedConversation)`
- `.projects` → `ProjectListView(selection: $selectedProject)`

**Detail content:**

Priority order:
1. If `sidebarMode == .projects` and `selectedProject != nil` → `CodeWorkspaceView(project:)`
2. If `selectedConversation != nil` → `ChatView(conversation:)`
3. Else → empty state (SEER emblem + "Let's Party")

**Mode switching:**

`onChange(of: sidebarMode)` clears the other selection to prevent stale state:
```swift
if sidebarMode == .chats { selectedProject = nil }
else { selectedConversation = nil }
```

**Query filter updated:**

`MainAppView`'s own `@Query` now also filters `isProjectChat != true` to match `ConversationListView`.

### `ConversationListView` — Modified

Query predicate updated:
```swift
(conversation.accountScopeKey == accountScopeKey
 || conversation.accountScopeKey == "")
&& conversation.isProjectChat != true
```

### `AppCommands` — Modified

New notification:
```swift
static let newProject = Notification.Name("seer.command.newProject")
```

### `OllamaCloudApp` — Modified

New keyboard shortcut in macOS commands:
```swift
Button("New Project") {
    AppCommand.post(AppCommand.newProject)
}
.keyboardShortcut("n", modifiers: [.command, .shift])
```

The `newProject` notification handler in `MainAppView` switches `sidebarMode = .projects` (the actual project creation happens via ProjectListView's "+" button/model picker flow).

---

## Views — Workspace UI

### `ProjectListView` (`Views/ProjectListView.swift`)

Mirrors `ConversationListView` structure:
- `@Query` for projects filtered by `accountScopeKey`
- List with `NavigationLink(value:)` rows
- Folder icon (instead of CPU icon)
- Shows: project name, file count
- "New Project" button → creates Project + hidden Conversation → shows ModelPickerView
- Swipe-to-delete (cascade deletes files + manually deletes hidden conversation)
- macOS: hover highlight, bottom "NEW PROJECT" capsule button

**Project creation flow:**
1. `newProject()` creates a `Conversation(isProjectChat: true)` and a `Project(conversationID: conversation.id)`
2. Opens `ModelPickerView` sheet
3. On model select: sets `conversation.modelName`, saves, selects project
4. On cancel/dismiss: `deletePendingProjectIfEmpty()` checks if model was selected; if not, deletes both

### `FileTreeView` (`Views/FileTreeView.swift`)

**Input:** `[ProjectFile]`, `selectedPath` binding, callbacks for delete/rename/new file.

**Tree building:** `FileNode.buildTree(from:)` converts flat `[ProjectFile]` paths into a nested tree:
1. Sorts files by path
2. Iterates each file's path components
3. Inserts nodes into a nested dictionary structure
4. Returns sorted array (directories first, then alphabetical)

**Rendering:** Recursive `nodeView()` returns `AnyView` (type erasure required for SwiftUI recursion):
- Directories: `DisclosureGroup` with recursive children
- Files: `Button` that sets `selectedPath`
- Both: context menu with Delete / New File Here

**Icons:** `iconForExtension()` maps file extensions to SF Symbols (swift, terminal, globe, doc.text, etc.)

### `CodeEditorView` (`Views/CodeEditorView.swift`)

**Architecture:** WKWebView wrapper with CodeMirror 6 loaded from ESM CDN (esm.sh).

**Platform split:**
- iOS: `UIViewRepresentable`
- macOS: `NSViewRepresentable`
- Shared: `Coordinator` class, `editorHTML()` static method

**JS Bridge:**
- Swift → JS: `setContent(text)`, `setLanguage(lang)` via `evaluateJavaScript`
- JS → Swift: `contentChanged` message handler via `WKScriptMessageHandler`
- Content changes debounced at 300ms in JS before posting to Swift

**Language support:**

```
python, javascript, typescript, html, css, json, markdown,
rust, cpp, java, sql, swift (mapped to cpp), go (mapped to cpp),
shell (no highlighting), yaml (no highlighting)
```

Languages loaded from CDN:
- `@codemirror/lang-javascript`, `@codemirror/lang-python`, `@codemirror/lang-html`
- `@codemirror/lang-css`, `@codemirror/lang-json`, `@codemirror/lang-markdown`
- `@codemirror/lang-rust`, `@codemirror/lang-cpp`, `@codemirror/lang-java`, `@codemirror/lang-sql`

**Theme:** One Dark base with custom SEER overrides:
- Background: `#080810` (matches `Color.bgPrimary`)
- Gutters: `#0a0a14` with `#1a1a2e` border
- Selection: `#1a1a3e`
- Cursor: `#8888cc`

**Update cycle:**
1. Coordinator tracks `lastSetContent` and `lastSetLanguage`
2. On `updateUIView`/`updateNSView`, only pushes to JS if value actually changed
3. Prevents infinite loops (JS change → Swift callback → SwiftUI update → JS set)

**JS string escaping:** Uses `JSONEncoder` to escape content for JavaScript string literals.

**Readiness:** Coordinator has `isReady` flag, set in `webView(_:didFinish:)`. Content/language set before ready are queued in `pendingContent`/`pendingLanguage`.

### `CodeWorkspaceView` (`Views/CodeWorkspaceView.swift`)

**The main IDE container.**

**State:**
```swift
@Bindable var project: Project
@State private var selectedFilePath: String?        // Currently viewed file
@State private var openFilePaths: [String] = []     // Tab bar (ordered)
@State private var isChatPanelCollapsed = false
@State private var showFileTreeSheet = false         // iOS only
@State private var showChatSheet = false             // iOS only
```

**Layout — Regular (macOS / iPad):**
```
VStack {
    HStack {
        fileTreeSidebar (200pt fixed width)
        Divider
        VStack { tabBar; Divider; editorArea }
    }
    Divider
    ProjectChatPanel (250pt or 30pt collapsed)
}
```

**Layout — Compact (iPhone):**
```
VStack { tabBar; Divider; editorArea }
// File tree: triggered as .sheet via folder toolbar button
// Chat: triggered as .sheet(detent: .medium) via bubble toolbar button
```

**Tab bar:** Horizontal scroll of open file names. Click to switch, X button to close. Selected tab has `Color.bgPrimary` background.

**Editor area:** Shows `CodeEditorView` for selected file, or empty state ("Select a file to edit").

**File content saving:** `CodeEditorView.onContentChange` directly mutates the `ProjectFile.content` and calls `modelContext.save()`. This means user edits are persisted immediately and visible to the model via `read_file`.

**Toolbar items:**
- iOS only: folder button (file tree sheet), bubble button (chat sheet)
- All platforms: export button (square.and.arrow.up)

**Project conversation lookup:** Uses `FetchDescriptor` to find the Conversation by `project.conversationID`. This is done as a computed property (`projectConversation`).

**onAppear:** Auto-opens the first non-directory file if `openFilePaths` is empty.

### `ProjectChatPanel` (`Views/ProjectChatPanel.swift`)

**Embedded chat panel for the code workspace.**

**Simplified vs ChatView:** No image attachments, no file attachments, no scaffold picker, no photo picker, no branching UI. Just text input + tool calling.

**Toggle bar:** Button with drag handle visual + chevron. Toggles `isCollapsed` with animation.

**Chat content:** ScrollViewReader + LazyVStack displaying:
- User messages: right-aligned, `Color.accentSoft` background
- Assistant messages: left-aligned, `Color.surface` background
- Tool results: compact capsule with wrench icon + tool name
- Tool calls and system messages: hidden

**Auto-scroll:** `onChange(of: sortedMessages.count)` and `onChange(of: streaming.streamingContent)` scroll to `"chatBottom"` anchor.

**Input bar:** TextField with 1-5 line limit, send/stop button. Same pattern as ChatView but without attachment options.

**Tool merging:** Always includes both `VisualsToolkit.tools` and `CodeToolkit.tools`, plus MCP tools on macOS.

---

## Export

### Location: `Services/ProjectExporter.swift`

### Flow

```
exportAsZip(project:)
    │
    ├── Write all ProjectFile contents to temp directory
    │   (FileManager.createDirectory + String.write)
    │
    ├── macOS: Process("/usr/bin/zip", ["-r", ...])
    │   └── Waits for exit, checks terminationStatus
    │
    └── iOS: NSFileCoordinator.coordinate(readingItemAt:options:.forUploading)
        └── System creates zip, we copy to our target URL
    │
    ▼
Returns URL to .zip file in temp directory
```

### Platform Integration

**macOS:** `NSSavePanel` with `.zip` UTType. User picks destination, we `FileManager.copyItem` from temp to chosen location.

**iOS:** `UIActivityViewController` (share sheet) via `ShareSheetView: UIViewControllerRepresentable`. Presented as a `.sheet`.

### Error Cases

- `ExportError.noFiles` — project has no non-directory files
- `ExportError.writeFailed` — file system write error
- `ExportError.zipFailed` — zip creation failed (process exit code or coordinator error)

---

## File Inventory

### New Files (9)

| File | Lines | Purpose |
|------|-------|---------|
| `Models/Project.swift` | ~28 | SwiftData project model |
| `Models/ProjectFile.swift` | ~25 | SwiftData project file model |
| `Services/CodeToolkit.swift` | ~410 | 8 tool definitions + implementations + tree builder |
| `Services/ProjectExporter.swift` | ~80 | Zip export for both platforms |
| `Views/ProjectListView.swift` | ~240 | Project list sidebar |
| `Views/FileTreeView.swift` | ~170 | Recursive file tree |
| `Views/CodeEditorView.swift` | ~220 | CodeMirror 6 WKWebView editor |
| `Views/CodeWorkspaceView.swift` | ~340 | Main IDE workspace container |
| `Views/ProjectChatPanel.swift` | ~195 | Collapsible chat panel |

### Modified Files (7)

| File | Change Summary |
|------|---------------|
| `Models/Conversation.swift` | +1 field: `var isProjectChat: Bool?` |
| `App/OllamaCloudApp.swift` | +2 models in schema, +1 keyboard shortcut command |
| `App/RootView.swift` | +sidebar mode enum, +segmented picker, +project selection, +CodeWorkspaceView detail |
| `Services/StreamingChatService.swift` | +`project:` param on sendMessage/retryLast, +CodeToolkit in handler check, +CodeToolkit dispatch branch |
| `Views/ChatView.swift` | +`project: Project?` property, +CodeToolkit.tools merge at 3 send sites |
| `Views/ConversationListView.swift` | +`isProjectChat != true` predicate filter |
| `Utils/AppCommands.swift` | +`newProject` notification name |

---

## Cross-Platform Considerations

| Concern | iOS | macOS |
|---------|-----|-------|
| File tree | Sheet (triggered by toolbar button) | Inline sidebar (200pt) |
| Chat panel | Sheet with `.medium`/`.large` detents | Inline bottom panel (collapsible) |
| Code editor | `UIViewRepresentable` WKWebView | `NSViewRepresentable` WKWebView |
| Export | `UIActivityViewController` share sheet | `NSSavePanel` with `.zip` UTType |
| Zip creation | `NSFileCoordinator` `.forUploading` | `/usr/bin/zip` via `Process` |
| Layout detection | `horizontalSizeClass == .compact` | Always regular |
| MCP tools | Not available | Merged into tool list |
| Keyboard shortcut | N/A | Cmd+Shift+N for New Project |

### Shared Code

All business logic (CodeToolkit, ProjectExporter, data models) compiles for both platforms without `#if os()` guards. Platform guards only appear in:
- View representables (UIViewRepresentable vs NSViewRepresentable)
- Export UI (share sheet vs save panel)
- Layout branches (compact vs regular)
- MCP manager injection

---

## Data Flow Diagrams

### Project Lifecycle

```
User taps "+"
    │
    ▼
ProjectListView.newProject()
    ├── Creates Conversation(isProjectChat: true)
    ├── Creates Project(conversationID: conv.id)
    ├── Saves modelContext
    └── Opens ModelPickerView sheet
         │
         ├── User selects model → conv.modelName set → project selected
         └── User cancels → deletePendingProjectIfEmpty() cleans up both
```

### File Creation via Tool Call

```
Model returns tool_call: create_file(path: "src/app.py", content: "...")
    │
    ▼
StreamingChatService tool dispatch
    → CodeToolkit.handles("create_file") == true
    → CodeToolkit.execute(toolName: "create_file", args, project, modelContext)
        │
        ├── normalizePath("src/app.py") → "src/app.py"
        ├── findFile(path: "src/app.py") → nil (doesn't exist)
        ├── ensureParentDirectories("src/app.py")
        │   └── Creates ProjectFile(path: "src", isDirectory: true)
        ├── Creates ProjectFile(path: "src/app.py", content: "...")
        └── Returns ("Created src/app.py (N bytes)", false)
    │
    ▼
Message(role: "tool", content: "Created src/app.py (N bytes)") persisted
    │
    ▼
modelContext.save() triggers SwiftData observation
    │
    ▼
FileTreeView sees new file in project.files → tree updates
CodeEditorView can open the new file
```

### User Edit → Model Read

```
User types in CodeEditorView
    │ (debounced 300ms)
    ▼
JS → webkit.messageHandlers.contentChanged.postMessage(text)
    │
    ▼
Coordinator.userContentController(_:didReceive:)
    → onContentChange(text)
    │
    ▼
CodeWorkspaceView closure:
    file.content = newContent
    file.updatedAt = Date()
    modelContext.save()
    │
    ▼
Model calls read_file(path: "src/app.py")
    → Returns current file.content (includes user's edits)
```

---

## Known Limitations & Risks

### Functional Limitations

| # | Limitation | Impact | Mitigation |
|---|-----------|--------|------------|
| 1 | **File content stored in SwiftData** | Large projects (hundreds of files, large binaries) may impact memory/performance | Acceptable for code projects; binary files not a target use case |
| 2 | **CodeMirror loaded from CDN** | Requires internet on first load; no offline fallback | WKWebView caches aggressively; could bundle CodeMirror in future |
| 3 | **No syntax highlighting for all languages** | Swift/Go mapped to C++, Shell/YAML have no highlighting | Close enough for readability; can add more `@codemirror/lang-*` imports |
| 4 | **`edit_file` replaces first occurrence only** | Model must be precise with `old_text`; can't do global replace | Matches Claude Code's Edit tool behavior; models adapt |
| 5 | **10-round tool loop limit** | Very large projects may hit this in a single response | Configurable in StreamingChatService; user can send follow-up messages |
| 6 | **No undo/redo in editor** | CodeMirror has built-in undo, but SwiftData writes are immediate | Could add undo support via modelContext.undoManager in future |
| 7 | **Project conversation is UUID-linked, not a relationship** | Slightly more complex deletion logic; requires manual fetch | Avoids circular SwiftData relationship complexity |
| 8 | **No file size limits** | Model could write very large files | Could add a size check in CodeToolkit |

### Risk Areas for QA

| # | Risk | Severity | Details |
|---|------|----------|---------|
| 1 | **SwiftData schema migration** | Medium | New models + new optional field on Conversation. Should be lightweight migration, but test with existing data stores |
| 2 | **Hidden conversation cleanup** | Medium | If app crashes between Project creation and Conversation creation, orphans possible. ProjectListView.deletePendingProjectIfEmpty() handles the normal case |
| 3 | **CodeMirror memory** | Low-Medium | WKWebView with CodeMirror could accumulate memory if many files opened. Tab close should release, but verify |
| 4 | **Concurrent tool execution** | Low | Tool calls are sequential within a round, but user could edit a file while model is also editing it via tool call. SwiftData's main actor isolation should prevent data races |
| 5 | **Export on iOS** | Low | NSFileCoordinator `.forUploading` trick is undocumented but widely used. Test on real device |

---

## QA Test Matrix

### Project CRUD

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 1 | Create project | Tap Projects → "+" → select model | Project appears in list with model name |
| 2 | Cancel creation | Tap "+" → cancel model picker | No orphaned project or conversation |
| 3 | Delete project | Swipe to delete | Project, all files, and hidden conversation deleted |
| 4 | Rename project | (Future: currently requires direct edit) | — |
| 5 | Switch between Chats and Projects | Tap segmented control | Correct list shown; other selection cleared |
| 6 | Project persistence | Create project → kill app → relaunch | Project still in list with all files |

### CodeToolkit Tools

| # | Test | Chat Input | Expected Tool Behavior |
|---|------|-----------|----------------------|
| 7 | create_file | "Create a file called hello.py with print('hello')" | File appears in tree, content correct |
| 8 | write_file (overwrite) | "Replace hello.py content with print('world')" | File content updated |
| 9 | write_file (new) | "Write to new_file.txt with some content" | File created |
| 10 | edit_file | "In hello.py, change 'world' to 'universe'" | Partial content updated |
| 11 | read_file | "What's in hello.py?" | Model reads and reports content |
| 12 | delete_file | "Delete hello.py" | File removed from tree |
| 13 | create_directory | "Create a src directory" | Directory node in tree |
| 14 | list_files | "Show me all files" | ASCII tree output |
| 15 | move_file | "Rename hello.py to greet.py" | Path updated, tab updated if open |
| 16 | Parent auto-creation | "Create src/utils/helpers.py" | src/ and src/utils/ directories auto-created |
| 17 | Non-empty dir delete | "Delete src/ (with files inside)" | Error: "Directory not empty" |
| 18 | Duplicate create | "Create hello.py" (already exists) | Error: "File already exists" |

### Editor

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 19 | Open file | Click file in tree | Content shown in editor, tab added |
| 20 | Switch tabs | Click different tab | Editor shows that file's content |
| 21 | Close tab | Click X on tab | Tab removed; next tab selected |
| 22 | Edit file | Type in editor | Content saved to SwiftData (check via read_file tool) |
| 23 | Syntax highlighting | Open .py file | Python syntax colored |
| 24 | Language switch | Open .js then .py file | Highlighting changes appropriately |
| 25 | Live update from tool | Model writes to open file | Editor shows updated content |

### Chat Panel

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 26 | Send message | Type + send in project chat | Message appears, model responds |
| 27 | Tool execution | Ask model to create files | Tool calls shown as capsules, files created |
| 28 | Collapse/expand | Click toggle bar | Panel collapses to 30pt / expands to 250pt |
| 29 | Auto-scroll | Rapid tool calls | Chat stays scrolled to bottom |
| 30 | Stop streaming | Click stop button during response | Streaming stops cleanly |

### Export

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 31 | Export (macOS) | Click export → save panel | .zip created with correct directory structure |
| 32 | Export (iOS) | Click export → share sheet | .zip available for sharing/saving |
| 33 | Export empty | Export project with no files | Error: "Project has no files to export" |
| 34 | Verify zip contents | Unzip exported file | All files present with correct content and directory structure |

### Cross-Platform

| # | Test | Platform | Steps | Expected |
|---|------|----------|-------|----------|
| 35 | Compact layout | iPhone | Open project | File tree as sheet, editor full-width |
| 36 | Regular layout | iPad/Mac | Open project | Side-by-side tree + editor, bottom chat |
| 37 | MCP coexistence | macOS | Enable MCP + use project | All 3 tool sources work together |

### Regression

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 38 | Normal chats unaffected | Switch to Chats, use normally | All existing chat functionality works |
| 39 | Project chats hidden | Check conversation list | No "Project Chat" entries visible |
| 40 | VisualsToolkit still works | In project chat, ask for a chart | Visualization tool still executes |
| 41 | Existing data preserved | Launch with pre-existing conversations | All conversations present, no data loss |

---

## Future Work

- **Bundled CodeMirror** — Include CodeMirror JS/CSS in the app bundle for offline support
- **File rename in tree** — Context menu rename (currently only via move_file tool)
- **Run button** — Execute main file (extend CodeExecutionService to project context)
- **Search across files** — Cmd+Shift+F style search
- **Git integration** — Initialize git repo in export, track changes
- **Binary file support** — Image previews, drag-and-drop assets
- **Multiple open editors** — Split view / side-by-side editing
- **Undo/redo** — Wire up modelContext.undoManager
- **Project templates** — Quick-start templates (Flask app, React app, etc.)
- **Collaborative editing** — Multiple tool calls and user edits merging gracefully
