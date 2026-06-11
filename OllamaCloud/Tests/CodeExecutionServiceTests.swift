import XCTest
@testable import OllamaCloud

final class CodeExecutionServiceTests: XCTestCase {
    func testLanguageMappingFromMarkdownTags() {
        XCTAssertEqual(ExecutableLanguage.from(markdownLanguage: "python3"), .python)
        XCTAssertEqual(ExecutableLanguage.from(markdownLanguage: "py"), .python)
        XCTAssertEqual(ExecutableLanguage.from(markdownLanguage: "node"), .javascript)
        XCTAssertEqual(ExecutableLanguage.from(markdownLanguage: "JS"), .javascript)
        XCTAssertEqual(ExecutableLanguage.from(markdownLanguage: "zsh"), .shell)
        XCTAssertNil(ExecutableLanguage.from(markdownLanguage: "swift"))
        XCTAssertNil(ExecutableLanguage.from(markdownLanguage: nil))
    }

    func testPlatformAvailability() {
        #if os(iOS)
        XCTAssertTrue(ExecutableLanguage.javascript.isAvailableOnCurrentPlatform)
        XCTAssertFalse(ExecutableLanguage.python.isAvailableOnCurrentPlatform)
        XCTAssertFalse(ExecutableLanguage.shell.isAvailableOnCurrentPlatform)
        #else
        XCTAssertTrue(ExecutableLanguage.python.isAvailableOnCurrentPlatform)
        XCTAssertTrue(ExecutableLanguage.javascript.isAvailableOnCurrentPlatform)
        XCTAssertTrue(ExecutableLanguage.shell.isAvailableOnCurrentPlatform)
        #endif
    }

    func testDetectsNodeStyleInteractiveJavaScript() {
        let code = """
        const readline = require('readline');
        const rl = readline.createInterface({ input: process.stdin });
        """

        XCTAssertTrue(CodeExecutionService.usesNodeStyleInteractiveJavaScript(code))
    }

    func testDetectsPromptStyleJavaScript() {
        let code = """
        const age = prompt("Age?");
        console.log(age);
        """

        XCTAssertTrue(CodeExecutionService.usesPromptStyleJavaScript(code))
    }

    func testNonInteractiveJavaScriptIsNotFlagged() {
        let code = """
        const value = 42;
        console.log(value);
        """

        XCTAssertFalse(CodeExecutionService.usesNodeStyleInteractiveJavaScript(code))
        XCTAssertFalse(CodeExecutionService.usesPromptStyleJavaScript(code))
    }
}
