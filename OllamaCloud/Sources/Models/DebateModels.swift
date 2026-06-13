import Foundation

/// AI Debate is intentionally NOT a SwiftData model — adding a @Model to the
/// schema would force a store migration/reset (no migration plan exists) and
/// wipe chats. Debates are plain Codable records persisted to a JSON file,
/// mirroring how the manticthink.com web app stores them in localStorage.

enum DebateMode: String, Codable, CaseIterable, Identifiable {
    case debate
    case discuss
    var id: String { rawValue }
    var title: String { self == .debate ? "Debate" : "Discussion" }
    /// Speaker labels for each side.
    var labels: (a: String, b: String) {
        self == .debate ? ("Proponent", "Opponent") : ("Analyst A", "Analyst B")
    }
}

struct DebateTurn: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// "A", "B", or "S" (synthesis).
    let side: String
    let label: String
    let model: String
    var text: String
}

struct DebateRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    let topic: String
    let modelA: String
    let modelB: String
    let mode: DebateMode
    var turns: [DebateTurn]
    var savedAt: Date = Date()
}

/// File-backed library of saved debates.
@MainActor
final class DebateStore: ObservableObject {
    @Published private(set) var debates: [DebateRecord] = []

    private let url: URL

    init() {
        let dir = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        url = dir.appendingPathComponent("seer-debates.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([DebateRecord].self, from: data) else { return }
        debates = decoded
    }

    func save(_ record: DebateRecord) {
        debates.removeAll { $0.id == record.id }
        debates.insert(record, at: 0)
        if debates.count > 200 { debates.removeLast(debates.count - 200) }
        persist()
    }

    func delete(_ id: UUID) {
        debates.removeAll { $0.id == id }
        persist()
    }

    func contains(_ id: UUID) -> Bool { debates.contains { $0.id == id } }

    private func persist() {
        guard let data = try? JSONEncoder().encode(debates) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
