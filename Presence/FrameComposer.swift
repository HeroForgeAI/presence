import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Builds the frame Zoom should see, and the frame the window should show.
final class FrameComposer {
    struct Output {
        var zoom: CVPixelBuffer
        var preview: CVPixelBuffer
    }

    enum Phase: Equatable {
        case live
        case recording(until: TimeInterval)
        case review
        case away
    }

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var pool: CVPixelBufferPool?
    private var formatDescription: CMFormatDescription?
    private let lock = NSLock()
    private var phase: Phase = .live
    private var recording: [Data] = []
    private var recordingMarks: [[UInt8]] = []
    private var markBuffer: CVPixelBuffer?
    private var take: [Data] = []
    private var loopStarted: TimeInterval?
    private let canvas = CGRect(x: 0, y: 0, width: PresenceFormat.width, height: PresenceFormat.height)

    init() {
        preparePool()
    }

    func setPhase(_ phase: Phase) {
        lock.lock()
        defer { lock.unlock() }
        if case .recording = phase, case .recording = self.phase {
            self.phase = phase
            return
        }
        if case .recording = phase {
            recording.removeAll(keepingCapacity: true)
            recordingMarks.removeAll(keepingCapacity: true)
        }
        if phase == .away, self.phase != .away {
            loopStarted = ProcessInfo.processInfo.systemUptime
        }
        if phase != .away {
            loopStarted = nil
        }
        self.phase = phase
    }

    func discardRecording() {
        lock.lock()
        recording.removeAll(keepingCapacity: true)
        recordingMarks.removeAll(keepingCapacity: true)
        if case .recording = phase { phase = take.isEmpty ? .live : .review }
        lock.unlock()
    }

    func finishRecording() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let distances = LoopJoin.distancesToFirst(recordingMarks)
        let kept = min(LoopJoin.trimLength(distancesToFirst: distances), recording.count)
        take = Array(recording.prefix(kept))
        recording.removeAll(keepingCapacity: true)
        recordingMarks.removeAll(keepingCapacity: true)
        phase = take.isEmpty ? .live : .review
        return take.count
    }

    var storedFrameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return take.count
    }

    func render(camera: CVPixelBuffer?) -> Output? {
        guard let camera, let live = aspectFilled(CIImage(cvPixelBuffer: camera)) else { return nil }
        lock.lock()
        let phase = self.phase
        let until: TimeInterval? = {
            if case .recording(let until) = phase { return until } else { return nil }
        }()
        lock.unlock()

        if let until, let jpeg = jpegData(from: live), let mark = signature(of: live) {
            lock.lock()
            if ProcessInfo.processInfo.systemUptime < until {
                recording.append(jpeg)
                recordingMarks.append(mark)
            }
            lock.unlock()
        }

        let zoomImage: CIImage
        let previewImage: CIImage
        switch phase {
        case .live, .recording:
            zoomImage = live
            previewImage = live
        case .review:
            zoomImage = live
            previewImage = loopedImage() ?? live
        case .away:
            let looped = loopedImage() ?? live
            zoomImage = looped
            previewImage = looped
        }

        guard let zoom = render(zoomImage), let preview = render(previewImage) else { return nil }
        return Output(zoom: zoom, preview: preview)
    }

    private func loopedImage() -> CIImage? {
        lock.lock()
        let frames = take
        let started = loopStarted ?? ProcessInfo.processInfo.systemUptime
        lock.unlock()
        guard !frames.isEmpty else { return nil }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let index = Int(elapsed * Double(PresenceFormat.frameRate))
        let blend = LoopMath.blend(frame: index, count: frames.count, fadeFrames: PresenceFormat.fadeFrames)
        guard let base = decoded(frames, blend.index) else { return nil }
        guard blend.mix > 0.001, let other = decoded(frames, blend.other) else { return base }
        return base.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: other,
            kCIInputTimeKey: blend.mix
        ]).cropped(to: canvas)
    }

    private func decoded(_ frames: [Data], _ index: Int) -> CIImage? {
        guard frames.indices.contains(index) else { return nil }
        guard let source = CGImageSourceCreateWithData(frames[index] as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CIImage(cgImage: image)
    }

    private func jpegData(from image: CIImage) -> Data? {
        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.9
        ]
        return context.jpegRepresentation(of: image, colorSpace: colorSpace, options: options)
    }

    /// A tiny luma picture, so the loop can end on a moment that looks like the start.
    private func signature(of image: CIImage) -> [UInt8]? {
        let width = 16
        let height = 9
        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return nil }
        if markBuffer == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                attributes as CFDictionary,
                &markBuffer
            )
        }
        guard let markBuffer else { return nil }
        let fitted = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / extent.width, y: CGFloat(height) / extent.height))
        context.render(
            fitted,
            to: markBuffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: colorSpace
        )
        CVPixelBufferLockBaseAddress(markBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(markBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(markBuffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(markBuffer)
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let offset = x * 4
                let blue = Int(row[offset])
                let green = Int(row[offset + 1])
                let red = Int(row[offset + 2])
                bytes.append(UInt8((red * 3 + green * 6 + blue) / 10))
            }
        }
        return bytes
    }

    private func aspectFilled(_ image: CIImage) -> CIImage? {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return nil }
        let scale = max(canvas.width / extent.width, canvas.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (scaled.extent.width - canvas.width) / 2
        let dy = (scaled.extent.height - canvas.height) / 2
        return scaled
            .transformed(by: CGAffineTransform(translationX: -scaled.extent.origin.x - dx, y: -scaled.extent.origin.y - dy))
            .cropped(to: canvas)
    }

    private func render(_ image: CIImage) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard status == kCVReturnSuccess, let buffer else { return nil }
        context.render(image, to: buffer, bounds: canvas, colorSpace: colorSpace)
        return buffer
    }

    private func preparePool() {
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(PresenceFormat.width),
            height: Int32(PresenceFormat.height),
            extensions: nil,
            formatDescriptionOut: &description
        )
        formatDescription = description
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: PresenceFormat.width,
            kCVPixelBufferHeightKey as String: PresenceFormat.height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
    }
}
