import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation
import IOKit.audio

private let frameRate = 30
private let cameraWidth: Int32 = 1280
private let cameraHeight: Int32 = 720
private let cameraName = "Presence"

final class PresenceProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: PresenceDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = PresenceDeviceSource(localizedName: cameraName)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Could not publish the Presence camera: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = "Presence"
        }
        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

final class PresenceDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private let sourceStream: PresenceSourceStream
    private let sinkStream: PresenceSinkStream
    private let timerQueue = DispatchQueue(label: "presence.camera.timer", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var streamingClients = 0
    private var sinkClients = 0
    private var sinkRunning = false
    private var formatDescription: CMFormatDescription!
    private var bufferPool: CVPixelBufferPool!

    init(localizedName: String) {
        let deviceID = UUID()
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: cameraWidth,
            height: cameraHeight,
            extensions: nil,
            formatDescriptionOut: &description
        )
        formatDescription = description
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: cameraWidth,
            kCVPixelBufferHeightKey as String: cameraHeight,
            kCVPixelBufferPixelFormatTypeKey as String: description?.mediaSubType ?? kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        bufferPool = pool
        let format = CMIOExtensionStreamFormat(
            formatDescription: description!,
            maxFrameDuration: CMTime(value: 1, timescale: Int32(frameRate)),
            minFrameDuration: CMTime(value: 1, timescale: Int32(frameRate)),
            validFrameDurations: nil
        )
        sourceStream = PresenceSourceStream(localizedName: "Presence.Video", streamID: UUID(), format: format)
        sinkStream = PresenceSinkStream(localizedName: "Presence.Video.Sink", streamID: UUID(), format: format)
        super.init()
        device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: deviceID,
            legacyDeviceID: deviceID.uuidString,
            source: self
        )
        sourceStream.device = device
        sinkStream.device = device
        do {
            try device.addStream(sourceStream.stream)
            try device.addStream(sinkStream.stream)
        } catch {
            fatalError("Could not add Presence streams: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = "Presence"
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    func startStreaming() {
        streamingClients += 1
        guard streamingClients == 1 else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(frameRate), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.sendPlaceholder()
        }
        timer.resume()
        self.timer = timer
    }

    func stopStreaming() {
        streamingClients = max(0, streamingClients - 1)
        guard streamingClients == 0 else { return }
        timer?.cancel()
        timer = nil
    }

    func startSink(client: CMIOExtensionClient) {
        sinkClients += 1
        sinkRunning = true
        consume(from: client)
    }

    func stopSink() {
        sinkRunning = false
        sinkClients = max(0, sinkClients - 1)
    }

    private func sendPlaceholder() {
        guard !sinkRunning else { return }
        guard let sample = makeSampleBuffer(fill: CGColor(gray: 0.09, alpha: 1)) else { return }
        let hostTime = UInt64(sample.presentationTimeStamp.seconds * Double(NSEC_PER_SEC))
        sourceStream.stream.send(sample, discontinuity: [], hostTimeInNanoseconds: hostTime)
    }

    private func consume(from client: CMIOExtensionClient) {
        guard sinkRunning else { return }
        sinkStream.stream.consumeSampleBuffer(from: client) { [weak self] sample, sequence, _, _, _ in
            guard let self else { return }
            if let sample, self.streamingClients > 0 {
                let hostTime = UInt64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * Double(NSEC_PER_SEC))
                self.sourceStream.stream.send(sample, discontinuity: [], hostTimeInNanoseconds: hostTime)
                let output = CMIOExtensionScheduledOutput(sequenceNumber: sequence, hostTimeInNanoseconds: hostTime)
                self.sinkStream.stream.notifyScheduledOutputChanged(output)
            }
            self.consume(from: client)
        }
    }

    private func makeSampleBuffer(fill color: CGColor) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, bufferPool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer),
           let context = CGContext(
            data: base,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
           ) {
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: Int(cameraWidth), height: Int(cameraHeight)))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        var timing = CMSampleTimingInfo()
        timing.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        )
        return status == 0 ? sample : nil
    }
}

final class PresenceSourceStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat
    weak var device: CMIOExtensionDevice?

    init(localizedName: String, streamID: UUID, format: CMIOExtensionStreamFormat) {
        self.format = format
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: .source, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }
    var availableProperties: Set<CMIOExtensionProperty> { [.streamActiveFormatIndex, .streamFrameDuration] }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { streamProperties.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }

    func startStream() throws {
        (device?.source as? PresenceDeviceSource)?.startStreaming()
    }

    func stopStream() throws {
        (device?.source as? PresenceDeviceSource)?.stopStreaming()
    }
}

final class PresenceSinkStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat
    weak var device: CMIOExtensionDevice?
    private var client: CMIOExtensionClient?

    init(localizedName: String, streamID: UUID, format: CMIOExtensionStreamFormat) {
        self.format = format
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: .sink, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }
    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { streamProperties.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
        }
        if properties.contains(.streamSinkBufferQueueSize) { streamProperties.sinkBufferQueueSize = 3 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { streamProperties.sinkBuffersRequiredForStartup = 1 }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        guard let client else { return }
        (device?.source as? PresenceDeviceSource)?.startSink(client: client)
    }

    func stopStream() throws {
        (device?.source as? PresenceDeviceSource)?.stopSink()
    }
}
