import AppKit
import Carbon.HIToolbox

enum ChordRole: Equatable {
    case record
    case step
}

/// A global shortcut. Letters follow a US key cap so the label stays stable.
struct KeyChord: Equatable {
    var keyCode: UInt16
    var carbonModifiers: UInt32

    static let record = KeyChord(keyCode: UInt16(kVK_ANSI_R), carbonModifiers: UInt32(controlKey | optionKey))
    static let step = KeyChord(keyCode: UInt16(kVK_ANSI_L), carbonModifiers: UInt32(controlKey | optionKey))

    var label: String {
        KeyChord.modifierSymbols(carbonModifiers) + (KeyChord.keyLabels[keyCode] ?? "")
    }

    var stored: String {
        "\(keyCode):\(carbonModifiers)"
    }

    static func load(_ key: String, fallback: KeyChord) -> KeyChord {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return fallback }
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let code = UInt16(parts[0]), let mods = UInt32(parts[1]) else { return fallback }
        let chord = KeyChord(keyCode: code, carbonModifiers: mods)
        return chord.label.count > modifierSymbols(mods).count ? chord : fallback
    }

    static func isModifierKey(_ keyCode: UInt16) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    /// Control, Option, or Command. Shift may be added. A bare letter is not a shortcut.
    static func make(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> KeyChord? {
        if isModifierKey(keyCode) { return nil }
        let mods = carbon(from: flags)
        let required = UInt32(controlKey | optionKey | cmdKey)
        if mods & required == 0 { return nil }
        guard keyLabels[keyCode] != nil else { return nil }
        return KeyChord(keyCode: keyCode, carbonModifiers: mods)
    }

    static func carbon(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    private static func modifierSymbols(_ mods: UInt32) -> String {
        var text = ""
        if mods & UInt32(controlKey) != 0 { text += "⌃" }
        if mods & UInt32(optionKey) != 0 { text += "⌥" }
        if mods & UInt32(shiftKey) != 0 { text += "⇧" }
        if mods & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command), UInt16(kVK_Shift), UInt16(kVK_CapsLock), UInt16(kVK_Option),
        UInt16(kVK_Control), UInt16(kVK_RightCommand), UInt16(kVK_RightShift),
        UInt16(kVK_RightOption), UInt16(kVK_RightControl), UInt16(kVK_Function)
    ]

    private static let keyLabels: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_ANSI_Minus): "-", UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_LeftBracket): "[", UInt16(kVK_ANSI_RightBracket): "]",
        UInt16(kVK_ANSI_Backslash): "\\", UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'", UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Period): ".", UInt16(kVK_ANSI_Slash): "/",
        UInt16(kVK_ANSI_Grave): "`",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12"
    ]
}
