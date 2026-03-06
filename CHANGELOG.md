# Changelog

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
