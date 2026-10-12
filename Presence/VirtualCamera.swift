import CoreImage
import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation
import SystemExtensions

extension CMIOObjectPropertyAddress {
    init(_ selector: CMIOObjectPropertySelector, _ scope: CMIOObjectPropertyScope, _ element: CMIOObjectPropertyElement) {
        self.init(mSelector: selector, mScope: scope, mElement: element)
    }
}

extension CMIOObjectPropertyScope {
    static let global = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal)
}

extension CMIOObjectPropertyElement {
    static let main = CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
}

/// Sends frames into the Presence camera extension's sink stream.
final class VirtualCamera: NSObject, OSSystemExtensionRequestDelegate {
    enum PublishState: Equatable {
        case idle
        case needsApproval
        case connected(camera: String)
        case failed(String)
    }

    private(set) var state: PublishState = .idle
    var onState: ((PublishState) -> Void)?

    private var sinkQueue: CMSimpleQueue?
    private var ready = false
    private var started = false
    private var formatDescription: CMFormatDescription?
    private var pool: CVPixelBufferPool?
    private(set) var connectedUID: String?
    private var outputWidth = Int32(PresenceFormat.width)
    private var outputHeight = Int32(PresenceFormat.height)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let auxAttributes: CFDictionary = [kCVPixelBufferPoolAllocationThresholdKey: 8] as CFDictionary

    func activateExtension() {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: PresenceFormat.extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func connectIfNeeded() {
        guard sinkQueue == nil else { return }
        guard let sink = bestSink() else { return }
        let size = CameraPolicy.outputSize(name: sink.name, uid: sink.uid)
        outputWidth = size.width
        outputHeight = size.height
        preparePool()
        let pointerQueue = UnsafeMutablePointer<Unmanaged<CMSimpleQueue>?>.allocate(capacity: 1)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let result = CMIOStreamCopyBufferQueue(sink.stream, { _, _, refcon in
            guard let refcon else { return }
            let camera = Unmanaged<VirtualCamera>.fromOpaque(refcon).takeUnretainedValue()
            camera.ready = true
        }, refcon, pointerQueue)
        guard result == 0, let unmanaged = pointerQueue.pointee else { return }
        sinkQueue = unmanaged.takeUnretainedValue()
        if CMIODeviceStartStream(sink.objectID, sink.stream) == 0 {
            started = true
            ready = true
            connectedUID = sink.uid
            update(.connected(camera: sink.name))
        }
    }

    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        guard let queue = sinkQueue, started else { return }
        guard ready || CMSimpleQueueGetCount(queue) == 0 else { return }
        guard CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else { return }
        guard let formatDescription else { return }
        let pixelBuffer = fitted(pixelBuffer)
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
        guard status == 0, let sample else { return }
        let pointer = Unmanaged.passRetained(sample).toOpaque()
        if CMSimpleQueueEnqueue(queue, element: pointer) == 0 {
            ready = false
        } else {
            Unmanaged<CMSampleBuffer>.fromOpaque(pointer).release()
        }
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        update(.needsApproval)
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        if result == .completed {
            connectIfNeeded()
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        if case .connected = state { return }
        update(.failed(error.localizedDescription))
    }

    private func update(_ state: PublishState) {
        self.state = state
        onState?(state)
    }

    private struct ListedSink {
        var uid: String
        var name: String
        var objectID: CMIOObjectID
        var stream: CMIOStreamID
    }

    /// A real webcam has no sink stream. Zoom's camera is whichever virtual camera does.
    private func bestSink() -> ListedSink? {
        let found = listedSinks()
        guard let chosen = CameraPolicy.preferredSink(found.map { SinkCandidate(name: $0.name, uid: $0.uid) }) else {
            return nil
        }
        return found.first { $0.uid == chosen.uid }
    }

    private func listedSinks() -> [ListedSink] {
        var found: [ListedSink] = []
        for device in cmioDevices() {
            guard let uid = copyString(device, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID)),
                  let name = copyString(device, CMIOObjectPropertySelector(kCMIOObjectPropertyName)) else { continue }
            let streams = streamIDs(deviceID: device)
            guard streams.contains(where: { streamDirection($0) == 1 }),
                  let sink = streams.first(where: { streamDirection($0) == 0 }) else { continue }
            guard CameraPolicy.acceptsOutput(name: name, uid: uid) else { continue }
            found.append(ListedSink(uid: uid, name: name, objectID: device, stream: sink))
        }
        return found
    }

    private func cmioDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices), .global, .main)
        var dataSize: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == 0, dataSize > 0 else { return [] }
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, dataSize, &used, &devices) == 0 else { return [] }
        return devices
    }

    private func copyString(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> String? {
        var address = CMIOObjectPropertyAddress(selector, .global, .main)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size) == 0, size > 0 else { return nil }
        var value: CFString = "" as CFString
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &value) == 0 else { return nil }
        let text = String(value)
        return text.isEmpty ? nil : text
    }

    private func fitted(_ buffer: CVPixelBuffer) -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        if width == Int(outputWidth), height == Int(outputHeight) { return buffer }
        var scaled: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &scaled) == kCVReturnSuccess, let scaled else {
            return buffer
        }
        let image = CIImage(cvPixelBuffer: buffer)
        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return buffer }
        let canvas = CGRect(x: 0, y: 0, width: Int(outputWidth), height: Int(outputHeight))
        let scale = max(canvas.width / extent.width, canvas.height / extent.height)
        let filled = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (filled.extent.width - canvas.width) / 2
        let dy = (filled.extent.height - canvas.height) / 2
        let cropped = filled
            .transformed(by: CGAffineTransform(translationX: -filled.extent.origin.x - dx, y: -filled.extent.origin.y - dy))
            .cropped(to: canvas)
        context.render(cropped, to: scaled, bounds: canvas, colorSpace: CGColorSpaceCreateDeviceRGB())
        return scaled
    }

    private func streamIDs(deviceID: CMIODeviceID) -> [CMIOStreamID] {
        var address = CMIOObjectPropertyAddress(CMIOObjectPropertySelector(kCMIODevicePropertyStreams), .global, .main)
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == 0, dataSize > 0 else { return [] }
        let count = Int(dataSize) / MemoryLayout<CMIOStreamID>.size
        var streams = [CMIOStreamID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(deviceID, &address, 0, nil, dataSize, &used, &streams) == 0 else { return [] }
        return streams
    }

    private func streamDirection(_ stream: CMIOStreamID) -> UInt32? {
        var address = CMIOObjectPropertyAddress(CMIOObjectPropertySelector(kCMIOStreamPropertyDirection), .global, .main)
        var direction: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(stream, &address, 0, nil, size, &used, &direction) == 0 else { return nil }
        return direction
    }

    private func preparePool() {
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: outputWidth,
            height: outputHeight,
            extensions: nil,
            formatDescriptionOut: &description
        )
        formatDescription = description
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: outputWidth,
            kCVPixelBufferHeightKey as String: outputHeight,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        _ = auxAttributes
        _ = pool
    }
}
