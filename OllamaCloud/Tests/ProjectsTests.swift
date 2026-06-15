import XCTest
import SwiftData
@testable import OllamaCloud

/// End-to-end coverage for the lightweight Projects data layer: context
/// compilation (injected on every send), chat grouping by `projectID`, exclusion
/// of project chats from the global list, and cascade delete of context files.
@MainActor
final class ProjectsTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Conversation.self,
            Message.self,
            ChatProject.self,
            ProjectContextFile.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    func testCompileIncludesNameInstructionsAndFiles() throws {
        let context = try makeContainer().mainContext
        let project = ChatProject(name: "Weather CLI", accountScopeKey: "s", instructions: "Be terse.")
        context.insert(project)
        context.insert(ProjectContextFile(name: "spec.md", content: "Output JSON.", project: project))
        try context.save()

        let compiled = ProjectContextCompiler.compile(project)
        XCTAssertTrue(compiled.contains("## Project: Weather CLI"))
        XCTAssertTrue(compiled.contains("Be terse."))
        XCTAssertTrue(compiled.contains("### Project file: spec.md"))
        XCTAssertTrue(compiled.contains("Output JSON."))
        XCTAssertTrue(compiled.contains("Use the project context above"))
    }

    func testCompileEmptyProjectHasHeaderButNoFiles() throws {
        let context = try makeContainer().mainContext
        let project = ChatProject(name: "Empty", accountScopeKey: "s")
        context.insert(project)
        try context.save()

        let compiled = ProjectContextCompiler.compile(project)
        XCTAssertTrue(compiled.contains("## Project: Empty"))
        XCTAssertFalse(compiled.contains("### Project file:"))
    }

    func testChatsAreGroupedByProjectIDAndExcludedFromGlobalList() throws {
        let context = try makeContainer().mainContext
        let project = ChatProject(name: "P", accountScopeKey: "s")
        context.insert(project)

        let inProject = Conversation(accountScopeKey: "s", projectID: project.id)
        let normal = Conversation(accountScopeKey: "s")
        context.insert(inProject)
        context.insert(normal)
        try context.save()

        // Grouping + global exclusion are done in Swift, NOT in a #Predicate:
        // a SwiftData predicate comparing the optional `projectID` to a UUID
        // crashes at evaluation time. Mirror the real (client-side) filtering.
        let all = try context.fetch(FetchDescriptor<Conversation>())

        let grouped = all.filter { $0.projectID == project.id }
        XCTAssertEqual(grouped.map(\.id), [inProject.id])

        let global = all.filter { $0.projectID == nil }
        XCTAssertTrue(global.contains { $0.id == normal.id })
        XCTAssertFalse(global.contains { $0.id == inProject.id })
    }

    func testDeletingProjectCascadesContextFiles() throws {
        let context = try makeContainer().mainContext
        let project = ChatProject(name: "P", accountScopeKey: "s")
        context.insert(project)
        context.insert(ProjectContextFile(name: "a.txt", content: "x", project: project))
        try context.save()

        context.delete(project)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<ProjectContextFile>())
        XCTAssertTrue(remaining.isEmpty)
    }
}
