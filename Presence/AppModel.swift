import AppKit
import AVFoundation
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Mode: Equatable {
        case live
        case recording(endsAt: Date)
        case ready
        case away
    }

    @Published var mode: Mode = .live
    @Published var duration: TakeDuration = .eight
    @Published var preview: NSImage?
    @Published var cameras: [CameraChoice] = []
    @Published var cameraID: String?
    @Published var cameraNote: String?
    @Published var publishNote: String?
    @Published var publishOpensSettings = false
    @Published var backgrounds: [ZoomBackground] = []
    @Published var backgroundID: String?
    @Published var thumbs: [String: NSImage] = [:]
    @Published var frameZoom: Double = 1.45
    @Published var glass: Double = 0.35
    @Published var recordChord: KeyChord = .record
    @Published var stepChord: KeyChord = .step
    @Published var listening: ChordRole?
    @Published var chordNote: String?

    var hasTake: Bool { engine.hasTake }
    var isRecording: Bool {
        if case .recording = mode { return true }
        return false
    }
    var isAway: Bool { mode == .away }

    private let engine = PresenceEngine()
    private let hotkeys = Hotkeys()
    private var recordingTask: Task<Void, Never>?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        hotkeys.onRecord = { [weak self] in self?.recordPressed() }
        hotkeys.onStep = { [weak self] in self?.stepPressed() }
        if UserDefaults.standard.object(forKey: Keys.glass) != nil {
            glass = min(1, max(0, UserDefaults.standard.double(forKey: Keys.glass)))
        }
        recordChord = KeyChord.load(Keys.recordChord, fallback: .record)
        stepChord = KeyChord.load(Keys.stepChord, fallback: .step)
        hotkeys.install()
        if !hotkeys.apply(record: recordChord, step: stepChord) {
            recordChord = .record
            stepChord = .step
            _ = hotkeys.apply(record: recordChord, step: stepChord)
        }
        engine.onPreview = { [weak self] image in
            self?.preview = image
        }
        engine.onPublish = { [weak self] state in
            self?.apply(state)
        }
        engine.onCameraNote = { [weak self] note in
            self?.cameraNote = note
        }
        engine.onAutoZoom = { [weak self] value in
            guard let self, abs(self.frameZoom - value) > 0.02 else { return }
            self.frameZoom = value
            UserDefaults.standard.set(value, forKey: Keys.zoom)
        }
        backgrounds = ZoomBackgroundLibrary.load()
        let hasZoom = UserDefaults.standard.object(forKey: Keys.zoom) != nil
        if hasZoom {
            frameZoom = min(2, max(1, UserDefaults.standard.double(forKey: Keys.zoom)))
        }
        engine.setFrameZoom(frameZoom, allowsAuto: !hasZoom)
        restoreBackground()
        loadThumbnails()
        if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
            NSApp.activate(ignoringOtherApps: true)
            openCameraSettings()
        }
        engine.start()
        cameras = engine.cameras()
        cameraID = cameras.first?.id
        engine.useCamera(cameraID)
        NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCameras()
            }
        }
    }

    func recordPressed() {
        if isRecording {
            cancelRecording()
            return
        }
        if isAway {
            returnToLive()
        }
        beginRecording()
    }

    func stepPressed() {
        guard hasTake, !isRecording else { return }
        if isAway {
            returnToLive()
        } else {
            mode = .away
            engine.setPhase(.away)
        }
    }

    func selectCamera(_ id: String) {
        cameraID = id
        engine.useCamera(id)
        engine.resetFraming()
    }

    func selectBackground(_ id: String?) {
        backgroundID = id
        if let id {
            UserDefaults.standard.set(id, forKey: Keys.background)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.background)
        }
        guard let id, let item = backgrounds.first(where: { $0.id == id }) else {
            engine.setPlate(url: nil, video: false)
            return
        }
        engine.setPlate(url: item.url, video: item.kind == .video)
    }

    func chooseBackgroundFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use"
        guard panel.runModal() == .OK, let url = panel.url, let item = ZoomBackgroundLibrary.item(forChosenFile: url) else { return }
        if let index = backgrounds.firstIndex(where: { $0.id == item.id }) {
            backgrounds.remove(at: index)
        }
        backgrounds.insert(item, at: 0)
        selectBackground(item.id)
        loadThumbnails(for: [item])
    }

    func setFrameZoom(_ value: Double) {
        let next = min(2, max(1, value))
        frameZoom = next
        UserDefaults.standard.set(next, forKey: Keys.zoom)
        engine.setFrameZoom(next, allowsAuto: false)
    }

    func setGlass(_ value: Double) {
        let next = min(1, max(0, value))
        glass = next
        UserDefaults.standard.set(next, forKey: Keys.glass)
    }

    func toggleListening(_ role: ChordRole) {
        if listening == role {
            cancelListening()
            return
        }
        listening = role
        chordNote = nil
        hotkeys.suspend()
    }

    func cancelListening() {
        listening = nil
        chordNote = nil
        _ = hotkeys.apply(record: recordChord, step: stepChord)
    }

    func assignChord(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard let listening else { return }
        if KeyChord.isModifierKey(keyCode) { return }
        guard let chord = KeyChord.make(keyCode: keyCode, flags: flags) else {
            chordNote = "Hold Control, Option, or Command."
            return
        }
        let other = listening == .record ? stepChord : recordChord
        if chord == other {
            chordNote = "Use a different shortcut for each."
            return
        }
        var nextRecord = recordChord
        var nextStep = stepChord
        if listening == .record {
            nextRecord = chord
        } else {
            nextStep = chord
        }
        guard hotkeys.apply(record: nextRecord, step: nextStep) else {
            chordNote = "That shortcut is already used."
            _ = hotkeys.apply(record: recordChord, step: stepChord)
            return
        }
        recordChord = nextRecord
        stepChord = nextStep
        UserDefaults.standard.set(nextRecord.stored, forKey: Keys.recordChord)
        UserDefaults.standard.set(nextStep.stored, forKey: Keys.stepChord)
        self.listening = nil
        chordNote = nil
    }

    var yourBackgrounds: [ZoomBackground] {
        backgrounds.filter { $0.origin != .library }
    }

    var libraryBackgrounds: [ZoomBackground] {
        backgrounds.filter { $0.origin == .library }
    }

    var backgroundTitle: String {
        guard let backgroundID, let item = backgrounds.first(where: { $0.id == backgroundID }) else {
            return "None"
        }
        return item.title
    }

    func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    func openExtensionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") else { return }
        NSWorkspace.shared.open(url)
    }

    private func beginRecording() {
        let seconds = duration.seconds
        let ends = Date().addingTimeInterval(seconds)
        mode = .recording(endsAt: ends)
        engine.setPhase(.recording(until: ProcessInfo.processInfo.systemUptime + seconds))
        recordingTask?.cancel()
        recordingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.completeRecording()
        }
    }

    private func cancelRecording() {
        recordingTask?.cancel()
        engine.cancelRecording()
        mode = engine.hasTake ? .ready : .live
    }

    private func completeRecording() {
        guard isRecording else { return }
        let frames = engine.finishRecording()
        mode = frames > 0 ? .ready : .live
    }

    private func returnToLive() {
        mode = .live
        engine.setPhase(.live)
    }

    private func refreshCameras() {
        let previous = cameraID
        cameras = engine.cameras()
        guard cameraID == nil || !cameras.contains(where: { $0.id == cameraID }) else { return }
        guard let next = cameras.first?.id else { return }
        cameraID = next
        if next != previous {
            engine.useCamera(next)
        }
    }

    private func restoreBackground() {
        guard let saved = UserDefaults.standard.string(forKey: Keys.background), !saved.isEmpty else { return }
        if backgrounds.contains(where: { $0.id == saved }) {
            selectBackground(saved)
            return
        }
        let url = URL(fileURLWithPath: saved)
        guard FileManager.default.fileExists(atPath: saved), let item = ZoomBackgroundLibrary.item(forChosenFile: url) else { return }
        backgrounds.insert(item, at: 0)
        selectBackground(item.id)
    }

    private func loadThumbnails() {
        loadThumbnails(for: yourBackgrounds)
        let library = libraryBackgrounds
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            self.loadThumbnails(for: library)
        }
    }

    private func loadThumbnails(for items: [ZoomBackground]) {
        guard !items.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            let made = ZoomBackgroundLibrary.thumbnails(for: items)
            await self?.mergeThumbs(made)
        }
    }

    private func mergeThumbs(_ made: [String: NSImage]) {
        guard !made.isEmpty else { return }
        var next = thumbs
        for (id, image) in made {
            next[id] = image
        }
        thumbs = next
    }

    private func apply(_ state: VirtualCamera.PublishState) {
        switch state {
        case .idle:
            publishNote = nil
            publishOpensSettings = false
        case .connected(let camera) where camera == PresenceFormat.cameraName:
            publishNote = nil
            publishOpensSettings = false
            refreshCameras()
        case .connected(let camera) where CameraPolicy.isOBS(name: camera, uid: ""):
            publishNote = "Zoom uses OBS Virtual Camera. Stop it in OBS."
            publishOpensSettings = false
            refreshCameras()
        case .connected(let camera):
            publishNote = "Zoom uses \(camera)."
            publishOpensSettings = false
            refreshCameras()
        case .needsApproval:
            publishNote = "Approve Presence under Camera Extensions."
            publishOpensSettings = true
        case .failed:
            publishNote = "Install OBS to put this picture in Zoom."
            publishOpensSettings = false
        }
    }
}

private enum Keys {
    static let background = "presence.backgroundPath"
    static let zoom = "presence.frameZoom"
    static let glass = "presence.glass"
    static let recordChord = "presence.recordChord"
    static let stepChord = "presence.stepChord"
}

/// Capture, compose, and publish off the main actor.
final class PresenceEngine: @unchecked Sendable {
    var onPreview: ((NSImage) -> Void)?
    var onPublish: ((VirtualCamera.PublishState) -> Void)?
    var onCameraNote: ((String?) -> Void)?
    var onAutoZoom: ((Double) -> Void)?

    private let capture = CaptureService()
    private let look = MeetingLook()
    private let composer = FrameComposer()
    private let virtual = VirtualCamera()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "presence.pump", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var lastPreview: TimeInterval = 0
    private var appliedSink: String?
    private let stateLock = NSLock()
    private var takeCount = 0

    var hasTake: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return takeCount > 0
    }

    func start() {
        capture.onInterruption = { [weak self] note in
            self?.onCameraNote?(note)
        }
        look.onAutoZoom = { [weak self] value in
            self?.onAutoZoom?(value)
        }
        virtual.onState = { [weak self] state in
            DispatchQueue.main.async { self?.onPublish?(state) }
        }
        capture.start(deviceID: nil)
        DispatchQueue.main.async { [weak self] in
            self?.virtual.activateExtension()
        }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(40), repeating: 1.0 / Double(PresenceFormat.frameRate), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    func cameras() -> [CameraChoice] {
        capture.availableCameras()
    }

    func useCamera(_ id: String?) {
        capture.configure(deviceID: id)
    }

    func resetFraming() {
        queue.async { [look] in
            look.resetFraming()
        }
    }

    func setFrameZoom(_ value: Double, allowsAuto: Bool) {
        queue.async { [look] in
            look.setZoom(CGFloat(value), allowsAuto: allowsAuto)
        }
    }

    func setPlate(url: URL?, video: Bool) {
        queue.async { [look] in
            look.setPlate(url: url, video: video)
        }
    }

    func setPhase(_ phase: FrameComposer.Phase) {
        composer.setPhase(phase)
        if case .recording = phase {
            queue.async { [look] in
                look.beginTake()
            }
        }
    }

    func cancelRecording() {
        composer.discardRecording()
    }

    func finishRecording() -> Int {
        let count = composer.finishRecording()
        stateLock.lock()
        takeCount = count
        stateLock.unlock()
        return count
    }

    private func tick() {
        virtual.connectIfNeeded()
        let sink = virtual.connectedUID
        if sink != appliedSink {
            appliedSink = sink
            capture.setExcludedCaptureID(sink)
            if let sink, capture.currentDeviceID() == sink {
                capture.configure(deviceID: nil)
            }
        }
        let camera = capture.latestFrame()
        let framed = camera.flatMap { look.render(camera: $0) } ?? camera
        guard let output = composer.render(camera: framed) else { return }
        virtual.enqueue(output.zoom)
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPreview >= 1.0 / 15.0 else { return }
        lastPreview = now
        let image = CIImage(cvPixelBuffer: output.preview)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        let preview = NSImage(cgImage: cgImage, size: NSSize(width: 640, height: 360))
        DispatchQueue.main.async { [weak self] in
            self?.onPreview?(preview)
        }
    }
}
