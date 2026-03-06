import XCTest
@testable import OllamaCloud

final class CodeExecutionServiceTests: XCTestCase {
    func testRequiresInteractiveInputDetectsPythonInput() {
        let code = """
        name = input("Name: ")
        print(name)
        """

        XCTAssertTrue(CodeExecutionService.requiresInteractiveInput(code: code, language: .python))
    }

    func testRequiresInteractiveInputDetectsJavaScriptPrompt() {
        let code = """
        const age = prompt("Age?");
        console.log(age);
        """

        XCTAssertTrue(CodeExecutionService.requiresInteractiveInput(code: code, language: .javascript))
    }

    func testRequiresInteractiveInputDetectsShellRead() {
        let code = """
        echo "Enter value"
        read value
        echo "$value"
        """

        XCTAssertTrue(CodeExecutionService.requiresInteractiveInput(code: code, language: .shell))
    }

    func testRequiresInteractiveInputFalseForNonInteractivePython() {
        let code = """
        value = 42
        print(value)
        """

        XCTAssertFalse(CodeExecutionService.requiresInteractiveInput(code: code, language: .python))
    }
}
