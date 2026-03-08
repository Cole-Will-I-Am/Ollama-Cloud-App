import Foundation
import Combine

/// Shared state bridge between ProjectChatPanel and the center editor panel.
/// Holds extracted code blocks from assistant messages.
class CodeBlockOutputState: ObservableObject {
    @Published var extractedBlocks: [ExtractedCodeBlock] = []   // from persisted messages
    @Published var streamingBlocks: [ExtractedCodeBlock] = []   // from current stream

    var allBlocks: [ExtractedCodeBlock] { extractedBlocks + streamingBlocks }

    /// Rebuild extracted blocks from all assistant messages in the conversation.
    func rebuildFromMessages(_ messages: [Message]) {
        var blocks: [ExtractedCodeBlock] = []
        for message in messages where message.role == "assistant" {
            let result = CodeBlockExtractor.extract(from: message.content, messageID: message.id)
            blocks.append(contentsOf: result.codeBlocks)
        }
        extractedBlocks = blocks
    }
}
