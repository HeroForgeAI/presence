import Carbon.HIToolbox
import Foundation

/// Global hotkeys that work while Zoom is the front app.
final class Hotkeys {
    var onRecord: (() -> Void)?
    var onStep: (() -> Void)?

    private var recordKey: EventHotKeyRef?
    private var stepKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            Hotkeys.shared?.dispatch(hotKeyID.id)
            return noErr
        }, 1, &spec, nil, &handler)
        Hotkeys.shared = self
    }

    func suspend() {
        clearKeys()
    }

    @discardableResult
    func apply(record: KeyChord, step: KeyChord) -> Bool {
        clearKeys()
        guard register(record, id: 1, into: &recordKey),
              register(step, id: 2, into: &stepKey) else {
            clearKeys()
            return false
        }
        return true
    }

    private static weak var shared: Hotkeys?

    private func register(_ chord: KeyChord, id: UInt32, into ref: inout EventHotKeyRef?) -> Bool {
        let hotKeyID = EventHotKeyID(signature: OSType(0x5052_5343), id: id)
        let status = RegisterEventHotKey(UInt32(chord.keyCode), chord.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    private func clearKeys() {
        if let recordKey {
            UnregisterEventHotKey(recordKey)
            self.recordKey = nil
        }
        if let stepKey {
            UnregisterEventHotKey(stepKey)
            self.stepKey = nil
        }
    }

    private func dispatch(_ id: UInt32) {
        DispatchQueue.main.async { [weak self] in
            if id == 1 {
                self?.onRecord?()
            } else if id == 2 {
                self?.onStep?()
            }
        }
    }
}
