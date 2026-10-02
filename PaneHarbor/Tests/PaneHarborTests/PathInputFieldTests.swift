import AppKit
import SwiftUI
import XCTest
@testable import PaneHarbor

@MainActor
final class PathInputFieldTests: XCTestCase {
    func testReturnSubmitsCurrentEditorTextBeforeBindingCatchesUp() {
        let newlineCommands = [
            #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
        ]

        for command in newlineCommands {
            var boundText = "/Users/example"
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
            editor.string = "/Users/example/Documents"

            let handled = coordinator.control(
                textField,
                textView: editor,
                doCommandBy: command
            )

            XCTAssertTrue(handled, "Expected \(command) to submit the path input.")
            XCTAssertEqual(boundText, "/Users/example/Documents")
            XCTAssertEqual(submittedTexts, ["/Users/example/Documents"])
        }
    }

    func testTextFieldActionSubmitsBackingStringWhenCommandDelegateIsNotUsed() {
        var boundText = "/Users/example"
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
        textField.stringValue = "/Users/example/Documents"

        coordinator.submitFromTextField(textField)

        XCTAssertEqual(boundText, "/Users/example/Documents")
        XCTAssertEqual(submittedTexts, ["/Users/example/Documents"])
    }

    func testReturnEndEditingSubmitsAccessibilityEditedText() {
        var boundText = "/Users/example"
        var focusStates: [Bool] = []
        var submittedTexts: [String] = []
        let field = PathInputField(
            text: Binding(
                get: { boundText },
                set: { boundText = $0 }
            ),
            isFocused: false,
            onFocusChange: { focusStates.append($0) },
            onSubmit: { submittedTexts.append($0) }
        )
        let coordinator = field.makeCoordinator()
        let textField = PathInputTextField()
        textField.stringValue = boundText
        coordinator.attach(textField)
        textField.setAccessibilityValue("/tmp/mfe/source")

        coordinator.controlTextDidEndEditing(Notification(
            name: NSControl.textDidEndEditingNotification,
            object: textField,
            userInfo: [NSText.movementUserInfoKey: NSTextMovement.return.rawValue]
        ))

        XCTAssertEqual(focusStates, [false])
        XCTAssertEqual(boundText, "/tmp/mfe/source")
        XCTAssertEqual(submittedTexts, ["/tmp/mfe/source"])
    }

    func testManualTextChangeClearsStaleAccessibilityTextBeforeReturnEndEditing() {
        var boundText = "/Users/example"
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
        let textField = PathInputTextField()
        textField.stringValue = boundText
        coordinator.attach(textField)
        textField.setAccessibilityValue("/tmp/mfe/source")

        textField.stringValue = "/tmp/mfe/preview"
        coordinator.controlTextDidChange(Notification(
            name: NSControl.textDidChangeNotification,
            object: textField
        ))
        coordinator.controlTextDidEndEditing(Notification(
            name: NSControl.textDidEndEditingNotification,
            object: textField,
            userInfo: [NSText.movementUserInfoKey: NSTextMovement.return.rawValue]
        ))

        XCTAssertEqual(boundText, "/tmp/mfe/preview")
        XCTAssertEqual(submittedTexts, ["/tmp/mfe/preview"])
    }

    func testExternalPathUpdateReplacesActiveEditorText() throws {
        var boundText = "/Users/example"
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

        coordinator.applyTextIfNeeded("/Users/example/Documents", to: textField)

        XCTAssertEqual(textField.stringValue, "/Users/example/Documents")
        XCTAssertEqual(try XCTUnwrap(textField.currentEditor()).string, "/Users/example/Documents")
    }

    func testExternalPathUpdateDoesNotOverwriteAnotherTextFieldsSharedEditor() throws {
        let field = PathInputField(
            text: .constant("/Users/example"),
            isFocused: false,
            onFocusChange: { _ in },
            onSubmit: { _ in }
        )
        let coordinator = field.makeCoordinator()
        let pathField = NSTextField(frame: NSRect(x: 0, y: 32, width: 320, height: 28))
        let renameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 96),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(pathField)
        window.contentView?.addSubview(renameField)
        pathField.stringValue = "/Users/example"
        renameField.stringValue = "rename-me.txt"
        XCTAssertTrue(window.makeFirstResponder(renameField))
        let renameEditor = try XCTUnwrap(renameField.currentEditor())
        renameEditor.string = "renamed.txt"

        coordinator.applyTextIfNeeded("/Users/example/Documents", to: pathField)

        XCTAssertEqual(pathField.stringValue, "/Users/example/Documents")
        XCTAssertEqual(renameEditor.string, "renamed.txt")
        XCTAssertTrue(window.firstResponder === renameEditor)
    }

    func testSyncFocusFalseKeepsActiveEditorWithoutClearRequest() throws {
        let field = PathInputField(
            text: .constant("/Users/example"),
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
            text: .constant("/Users/example"),
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

    func testFocusClearRequestDoesNotResignAnotherTextFieldsSharedEditor() throws {
        let field = PathInputField(
            text: .constant("/Users/example"),
            isFocused: false,
            focusClearSequence: 0,
            onFocusChange: { _ in },
            onSubmit: { _ in }
        )
        let coordinator = field.makeCoordinator()
        let pathField = NSTextField(frame: NSRect(x: 0, y: 32, width: 320, height: 28))
        let renameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 96),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(pathField)
        window.contentView?.addSubview(renameField)
        XCTAssertTrue(window.makeFirstResponder(renameField))
        let renameEditor = try XCTUnwrap(renameField.currentEditor())

        coordinator.applyFocusClearIfNeeded(1, to: pathField)

        XCTAssertTrue(window.firstResponder === renameEditor)
        XCTAssertNotNil(renameField.currentEditor())
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
