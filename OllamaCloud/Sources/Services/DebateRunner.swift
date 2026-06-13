import Foundation

/// A single live (streaming) turn the UI observes. Persisted form is `DebateTurn`.
@MainActor
final class LiveTurn: ObservableObject, Identifiable {
    let id = UUID()
    let side: String     // "A", "B", "S"
    let label: String
    let model: String
    @Published var text: String = ""
    @Published var streaming: Bool = true

    init(side: String, label: String, model: String) {
        self.side = side
        self.label = label
        self.model = model
    }

    var snapshot: DebateTurn { DebateTurn(side: side, label: label, model: model, text: text) }
}

/// Runs an AI debate: two Ollama models take turns on a topic, optionally closed
/// by an impartial synthesis. Self-contained — reuses OllamaAPIClient streaming
/// but not the chat conversation/SwiftData state.
@MainActor
final class DebateRunner: ObservableObject {
    @Published var turns: [LiveTurn] = []
    @Published var isRunning = false
    @Published var error: String?
    @Published var topic = ""
    @Published var modelA = ""
    @Published var modelB = ""
    @Published var mode: DebateMode = .debate
    /// Set once a finished/loaded debate is in `turns`, so the UI can offer Save.
    @Published var finished = false

    private var task: Task<Void, Never>?
    private(set) var recordID = UUID()

    func start(topic: String, modelA: String, modelB: String, mode: DebateMode, rounds: Int, synthesis: Bool) {
        guard !isRunning else { return }
        self.topic = topic; self.modelA = modelA; self.modelB = modelB; self.mode = mode
        recordID = UUID()
        turns = []
        error = nil
        finished = false
        isRunning = true
        task = Task { await run(rounds: max(1, min(4, rounds)), synthesis: synthesis) }
    }

    func stop() { task?.cancel() }

    /// Render a saved/shared record read-only (no streaming).
    func load(_ record: DebateRecord) {
        stop()
        recordID = record.id
        topic = record.topic; modelA = record.modelA; modelB = record.modelB; mode = record.mode
        turns = record.turns.map { t in
            let live = LiveTurn(side: t.side, label: t.label, model: t.model)
            live.text = t.text; live.streaming = false
            return live
        }
        error = nil
        isRunning = false
        finished = true
    }

    var record: DebateRecord {
        DebateRecord(id: recordID, topic: topic, modelA: modelA, modelB: modelB, mode: mode,
                     turns: turns.map(\.snapshot))
    }

    private func run(rounds: Int, synthesis: Bool) async {
        let labels = mode.labels
        func labelFor(_ side: String) -> String { side == "A" ? labels.a : labels.b }
        var transcript: [DebateTurn] = []

        do {
            outer: for _ in 0..<rounds {
                for side in ["A", "B"] {
                    if Task.isCancelled { break outer }
                    let model = side == "A" ? modelA : modelB
                    let live = LiveTurn(side: side, label: labelFor(side), model: model)
                    turns.append(live)
                    let text = try await streamTurn(
                        model: model,
                        system: DebatePrompts.persona(mode: mode, side: side, topic: topic),
                        user: DebatePrompts.turnPrompt(topic: topic, transcript: transcript, label: labelFor(side), mode: mode),
                        into: live
                    )
                    live.streaming = false
                    transcript.append(live.snapshot)
                    _ = text
                }
            }

            if synthesis, !Task.isCancelled, !transcript.isEmpty {
                let live = LiveTurn(side: "S", label: "Synthesis", model: modelA)
                turns.append(live)
                _ = try await streamTurn(
                    model: modelA,
                    system: DebatePrompts.synthesisPersona(mode: mode, topic: topic),
                    user: DebatePrompts.synthesisPrompt(topic: topic, transcript: transcript, mode: mode),
                    into: live
                )
                live.streaming = false
                transcript.append(live.snapshot)
            }
        } catch is CancellationError {
            // user stopped — keep what streamed
        } catch let err as OllamaAPIError {
            if case .unauthorized = err { error = "Your key was rejected — reconnect in Settings." }
            else { error = "Something went wrong running the debate." }
        } catch {
            if !Task.isCancelled { self.error = "Something went wrong running the debate." }
        }

        turns.forEach { $0.streaming = false }
        isRunning = false
        finished = !turns.isEmpty
    }

    private func streamTurn(model: String, system: String, user: String, into live: LiveTurn) async throws -> String {
        let messages = [
            ChatRequestMessage(role: "system", content: system),
            ChatRequestMessage(role: "user", content: user),
        ]
        let (bytes, response) = try await OllamaAPIClient.shared.streamChat(model: model, messages: messages, think: false)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 { throw OllamaAPIError.unauthorized }

        var acc = ""
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) else { continue }
            if let content = chunk.message?.content, !content.isEmpty {
                acc += content
                live.text = acc
            }
            if chunk.done { break }
        }
        if acc.isEmpty { live.text = "(no response)" }
        return acc
    }
}

enum DebatePrompts {
    static func persona(mode: DebateMode, side: String, topic: String) -> String {
        if mode == .debate {
            let role = side == "A"
                ? "the PROPONENT, arguing IN FAVOR of the proposition"
                : "the OPPONENT, arguing AGAINST the proposition"
            return "You are \(role) in a structured debate. Topic: \"\(topic)\". Make your strongest case, directly rebut the other side's most recent points, and stay strictly on topic. Be substantive but concise: under 150 words. Do not restate your role, narrate stage directions, or prefix your name — just give the argument in plain persuasive prose."
        }
        let who = side == "A" ? "Analyst A" : "Analyst B"
        return "You are \(who), one of two thoughtful analysts discussing a question together. Topic: \"\(topic)\". Build on or respectfully challenge the other analyst's most recent points, add fresh angles, and avoid repeating what's already been said. Be concise: under 150 words. Do not prefix your name or narrate stage directions."
    }

    static func turnPrompt(topic: String, transcript: [DebateTurn], label: String, mode: DebateMode) -> String {
        if transcript.isEmpty {
            return mode == .debate
                ? "The debate topic is: \"\(topic)\". Open with your position as the \(label)."
                : "The question is: \"\(topic)\". Open the discussion with your initial take as \(label)."
        }
        let lines = transcript.map { "[\($0.label)]: \($0.text)" }.joined(separator: "\n\n")
        return "Topic: \"\(topic)\"\n\nConversation so far:\n\(lines)\n\nIt is now your turn as \(label). Respond directly to the most recent point."
    }

    static func synthesisPersona(mode: DebateMode, topic: String) -> String {
        if mode == .debate {
            return "You are an impartial moderator closing a debate on: \"\(topic)\". Read the full transcript and write a brief, neutral synthesis: the single strongest point from each side, any genuine common ground, and a balanced judgment of which case was more persuasive and why. Be fair to both sides. Under 180 words. Do not prefix your name."
        }
        return "You are synthesizing a discussion on: \"\(topic)\". Read the full transcript and summarize the key insights, where the analysts agreed and differed, and the most important takeaway. Neutral and concise — under 180 words. Do not prefix your name."
    }

    static func synthesisPrompt(topic: String, transcript: [DebateTurn], mode: DebateMode) -> String {
        let lines = transcript.map { "[\($0.label)]: \($0.text)" }.joined(separator: "\n\n")
        return "Topic: \"\(topic)\"\n\nFull transcript:\n\(lines)\n\nNow write the closing \(mode == .debate ? "synthesis and verdict" : "synthesis")."
    }
}
