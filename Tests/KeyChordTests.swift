import AppKit
import XCTest

final class KeyChordTests: XCTestCase {
    func testDefaultRecordChordReadsControlOptionR() {
        XCTAssertEqual(KeyChord.record.label, "⌃⌥R")
    }

    func testDefaultStepChordReadsControlOptionL() {
        XCTAssertEqual(KeyChord.step.label, "⌃⌥L")
    }

    func testABareLetterIsNotAShortcut() {
        XCTAssertNil(KeyChord.make(keyCode: KeyChord.record.keyCode, flags: []))
    }

    func testCommandIsEnough() {
        let chord = KeyChord.make(keyCode: KeyChord.record.keyCode, flags: [.command])
        XCTAssertEqual(chord?.label, "⌘R")
    }

    func testShiftSitsBetweenOptionAndCommand() {
        let flags: NSEvent.ModifierFlags = [.control, .option, .shift]
        let chord = KeyChord.make(keyCode: KeyChord.step.keyCode, flags: flags)
        XCTAssertEqual(chord?.label, "⌃⌥⇧L")
    }
}
