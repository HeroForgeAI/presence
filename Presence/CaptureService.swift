import AVFoundation
import CoreMedia
import Foundation

struct CameraChoice: Identifiable, Equatable {
    var id: String
    var name: String
}

/// Owns the physical webcam. Zoom never opens this device. Presence does.
final class CaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "presence.capture")
    private let frames = DispatchQueue(label: "presence.frames")
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var configuredID: String?
    private var excludedID: String?
    var onInterruption: ((String?) -> Void)?

    func latestFrame() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func setExcludedCaptureID(_ id: String?) {
        lock.lock()
        excludedID = id
        lock.unlock()
    }

    func currentDeviceID() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return configuredID
    }

    func availableCameras() -> [CameraChoice] {
        let excluded = excludedCaptureID()
        let candidates = Self.discoveryDevices().compactMap { device -> WebcamCandidate? in
            if device.uniqueID == excluded { return nil }
            return WebcamCandidate(id: device.uniqueID, name: device.localizedName, kind: Self.kind(of: device))
        }
        return CameraPolicy.orderedWebcams(candidates).map { CameraChoice(id: $0.id, name: $0.name) }
    }

    func start(deviceID: String?) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configure(deviceID: deviceID)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configure(deviceID: deviceID)
                    } else {
                        self?.onInterruption?("Camera access is off.")
                    }
                }
            }
        default:
            onInterruption?("Camera access is off.")
        }
    }

    func configure(deviceID: String?) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            accessWatch?.cancel()
            queue.async { [weak self] in
                self?.configureOnQueue(deviceID: deviceID)
            }
        case .notDetermined:
            DispatchQueue.main.async { [weak self] in
                self?.onInterruption?("Allow Presence to use the camera.")
            }
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configure(deviceID: deviceID)
                    } else {
                        self?.onInterruption?("Camera access is off.")
                        self?.watchAccess(deviceID)
                    }
                }
            }
            watchAccess(deviceID)
        default:
            DispatchQueue.main.async { [weak self] in
                self?.onInterruption?("Camera access is off.")
            }
            watchAccess(deviceID)
        }
    }

    private var accessWatch: DispatchWorkItem?

    private func watchAccess(_ deviceID: String?) {
        accessWatch?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                self.configure(deviceID: deviceID)
            } else {
                self.watchAccess(deviceID)
            }
        }
        accessWatch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func configureOnQueue(deviceID: String?) {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        var shouldRun = false
        defer {
            session.commitConfiguration()
            if shouldRun {
                session.startRunning()
            }
        }
        for input in session.inputs {
            session.removeInput(input)
        }
        guard let device = resolvedDevice(id: deviceID) else {
            DispatchQueue.main.async { [weak self] in
                self?.onInterruption?("No camera is connected.")
            }
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard attach(input) else {
                DispatchQueue.main.async { [weak self] in
                    self?.onInterruption?(Self.busyNote)
                }
                return
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onInterruption?(Self.busyNote)
            }
            return
        }
        if session.outputs.isEmpty {
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: frames)
            guard session.canAddOutput(output) else {
                DispatchQueue.main.async { [weak self] in
                    self?.onInterruption?("This webcam’s picture can’t be used.")
                }
                return
            }
            session.addOutput(output)
        }
        lock.lock()
        configuredID = device.uniqueID
        lock.unlock()
        shouldRun = true
        DispatchQueue.main.async { [weak self] in
            self?.onInterruption?(nil)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        latest = buffer
        lock.unlock()
    }

    private static let busyNote = "This webcam is busy. In Zoom, choose the virtual camera, then pick it here again."

    private func excludedCaptureID() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return excludedID
    }

    private func resolvedDevice(id: String?) -> AVCaptureDevice? {
        let choices = availableCameras()
        let chosen = choices.first { $0.id == id } ?? choices.first
        guard let chosen else { return nil }
        return Self.discoveryDevices().first { $0.uniqueID == chosen.id }
    }

    /// 720p when the webcam has it. Otherwise a size the camera actually supports. The composer scales the picture.
    private func attach(_ input: AVCaptureDeviceInput) -> Bool {
        let presets: [AVCaptureSession.Preset] = [.hd1280x720, .high, .medium, .vga640x480]
        for preset in presets {
            guard input.device.supportsSessionPreset(preset) else { continue }
            guard session.canSetSessionPreset(preset) else { continue }
            session.sessionPreset = preset
            if session.canAddInput(input) {
                session.addInput(input)
                return true
            }
        }
        return false
    }

    private static func discoveryDevices() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [
            .external,
            .builtInWideAngleCamera,
            .continuityCamera,
            .deskViewCamera
        ]
        let discovered = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
        var seen = Set<String>()
        return (discovered + AVCaptureDevice.devices(for: .video)).filter { seen.insert($0.uniqueID).inserted }
    }

    private static func kind(of device: AVCaptureDevice) -> WebcamKind {
        if device.isContinuityCamera { return .continuity }
        switch device.deviceType {
        case .builtInWideAngleCamera:
            return .builtIn
        case .continuityCamera, .deskViewCamera:
            return .continuity
        default:
            return .external
        }
    }
}
