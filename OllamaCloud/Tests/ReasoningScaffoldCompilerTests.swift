import XCTest
@testable import OllamaCloud

final class ReasoningScaffoldCompilerTests: XCTestCase {
    func testCompilerProducesDeterministicSectionOrder() throws {
        let scaffold = ReasoningScaffold(
            accountScopeKey: "scope-a",
            name: "Analyst",
            summary: "Analyze decisions with constraints.",
            role: "Analyst",
            perspective: "Evidence first.",
            tone: "Direct",
            reasoningSteps: ["Understand the problem", "Assess tradeoffs"],
            outputFormat: "bullet_points",
            mustInclude: ["Recommendation"],
            neverInclude: ["Speculation"],
            disclaimers: ["Not legal advice."],
            prohibitedActions: ["Fabricating facts"]
        )

        let compiled = ReasoningScaffoldCompiler.compile(scaffold)

        XCTAssertTrue(compiled.contains("## Reasoning Scaffold"))
        XCTAssertTrue(compiled.contains("## Role"))
        XCTAssertTrue(compiled.contains("## Perspective"))
        XCTAssertTrue(compiled.contains("## Reasoning Steps"))
        XCTAssertTrue(compiled.contains("## Flexibility"))
        XCTAssertTrue(compiled.contains("## Output Guidance"))
        XCTAssertTrue(compiled.contains("## Safety Hints"))

        let roleIndex = try XCTUnwrap(compiled.range(of: "## Role")?.lowerBound)
        let perspectiveIndex = try XCTUnwrap(compiled.range(of: "## Perspective")?.lowerBound)
        let stepsIndex = try XCTUnwrap(compiled.range(of: "## Reasoning Steps")?.lowerBound)
        XCTAssertLessThan(roleIndex, perspectiveIndex)
        XCTAssertLessThan(perspectiveIndex, stepsIndex)
    }

    func testCompilerOmitsEmptyOptionalSections() {
        let scaffold = ReasoningScaffold(
            accountScopeKey: "scope-b",
            name: "Minimal",
            role: "Guide",
            perspective: "Keep it concise.",
            reasoningSteps: ["Answer directly"]
        )

        let compiled = ReasoningScaffoldCompiler.compile(scaffold)
        XCTAssertFalse(compiled.contains("## Output Guidance"))
        XCTAssertFalse(compiled.contains("## Safety Hints"))
        XCTAssertFalse(compiled.contains("## Tone"))
        XCTAssertTrue(compiled.contains("## Flexibility"))
    }

    func testValidateEnforcesRequiredFields() {
        let issues = ReasoningScaffoldCompiler.validate(.empty)
        XCTAssertTrue(issues.contains(where: { $0.field == "name" }))
        XCTAssertTrue(issues.contains(where: { $0.field == "role" }))
        XCTAssertTrue(issues.contains(where: { $0.field == "perspective" }))
        XCTAssertTrue(issues.contains(where: { $0.field == "reasoning_steps" }))
    }

    func testAccountScopeKeyStabilityAndDifferences() {
        let k1 = AccountScope.scopeKey(apiBaseURL: "https://ollama.com", apiKey: "abc")
        let k2 = AccountScope.scopeKey(apiBaseURL: "https://ollama.com", apiKey: "abc")
        let k3 = AccountScope.scopeKey(apiBaseURL: "https://ollama.com", apiKey: "def")
        let k4 = AccountScope.scopeKey(apiBaseURL: "https://example.com", apiKey: "abc")

        XCTAssertEqual(k1, k2)
        XCTAssertNotEqual(k1, k3)
        XCTAssertNotEqual(k1, k4)
    }
}
