import AppKit
import SwiftUI
import XCTest
@testable import MyMacFinder

@MainActor
final class PathInputFieldTests: XCTestCase {
    func testReturnSubmitsCurrentEditorTextBeforeBindingCatchesUp() {
        let newlineCommands = [
            #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
        ]

        for command in newlineCommands {
            var boundText = "/Users/biglol"
            var submittedTexts: [String] = []
            let field = PathInputField(
                text: Binding(
                    get: { boundText },
                    set: { boundText = $0 }
                ),
                isFocused: false,
                onFocusChange: { _ in },
                onSubmit: { submittedTexts.append($0) }
            )
            let coordinator = field.makeCoordinator()
            let textField = NSTextField()
            let editor = NSTextView()
            editor.string = "/Users/biglol/Documents"

            let handled = coordinator.control(
                textField,
                textView: editor,
                doCommandBy: command
            )

            XCTAssertTrue(handled, "Expected \(command) to submit the path input.")
            XCTAssertEqual(boundText, "/Users/biglol/Documents")
            XCTAssertEqual(submittedTexts, ["/Users/biglol/Documents"])
        }
    }

    func testTextFieldActionSubmitsBackingStringWhenCommandDelegateIsNotUsed() {
        var boundText = "/Users/biglol"
        var submittedTexts: [String] = []
        let field = PathInputField(
            text: Binding(
                get: { boundText },
                set: { boundText = $0 }
            ),
            isFocused: false,
            onFocusChange: { _ in },
            onSubmit: { submittedTexts.append($0) }
        )
        let coordinator = field.makeCoordinator()
        let textField = NSTextField()
        textField.stringValue = "/Users/biglol/Documents"

        coordinator.submitFromTextField(textField)

        XCTAssertEqual(boundText, "/Users/biglol/Documents")
        XCTAssertEqual(submittedTexts, ["/Users/biglol/Documents"])
    }

    func testExternalPathUpdateReplacesActiveEditorText() throws {
        var boundText = "/Users/biglol"
        let field = PathInputField(
            text: Binding(
                get: { boundText },
                set: { boundText = $0 }
            ),
            isFocused: false,
            onFocusChange: { _ in },
            onSubmit: { _ in }
        )
        let coordinator = field.makeCoordinator()
        let textField = ActiveEditorTextField()
        textField.stringValue = boundText
        let editor = NSTextView()
        editor.string = boundText
        textField.stubbedEditor = editor

        coordinator.applyTextIfNeeded("/Users/biglol/Documents", to: textField)

        XCTAssertEqual(textField.stringValue, "/Users/biglol/Documents")
        XCTAssertEqual(try XCTUnwrap(textField.currentEditor()).string, "/Users/biglol/Documents")
    }

    func testSyncFocusFalseKeepsActiveEditorWithoutClearRequest() throws {
        let field = PathInputField(
            text: .constant("/Users/biglol"),
            isFocused: false,
            onFocusChange: { _ in },
            onSubmit: { _ in }
        )
        let coordinator = field.makeCoordinator()
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(textField)
        XCTAssertTrue(window.makeFirstResponder(textField))
        XCTAssertNotNil(textField.currentEditor())

        coordinator.syncFocus(for: textField, shouldFocus: false)

        XCTAssertNotNil(textField.currentEditor())
    }

    func testFocusClearRequestResignsActiveEditor() throws {
        let field = PathInputField(
            text: .constant("/Users/biglol"),
            isFocused: false,
            focusClearSequence: 0,
            onFocusChange: { _ in },
            onSubmit: { _ in }
        )
        let coordinator = field.makeCoordinator()
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(textField)
        XCTAssertTrue(window.makeFirstResponder(textField))
        XCTAssertNotNil(textField.currentEditor())

        coordinator.applyFocusClearIfNeeded(1, to: textField)

        XCTAssertNil(textField.currentEditor())
    }

    func testReturnKeyDetectionIgnoresCommandEditingShortcuts() throws {
        let returnEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
        let commandReturnEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
        let commandCopyEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        ))

        XCTAssertTrue(PathInputField.Coordinator.isPlainReturnKey(returnEvent))
        XCTAssertFalse(PathInputField.Coordinator.isPlainReturnKey(commandReturnEvent))
        XCTAssertFalse(PathInputField.Coordinator.isPlainReturnKey(commandCopyEvent))
    }
}

private final class ActiveEditorTextField: NSTextField {
    var stubbedEditor: NSText?

    override func currentEditor() -> NSText? {
        stubbedEditor
    }
}
