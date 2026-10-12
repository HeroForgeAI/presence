import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import Vision

/// Frames the webcam the way a Zoom tile does, then lays the person’s background behind them.
/// Touched only on the frame pump queue.
final class MeetingLook {
    var onAutoZoom: ((Double) -> Void)?

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let canvas = CGRect(x: 0, y: 0, width: PresenceFormat.width, height: PresenceFormat.height)
    private var pool: CVPixelBufferPool?
    private var zoom: CGFloat = 1.45
    private var allowsAutoZoom = false
    private var didAutoZoom = false
    private var faceSamples: [CGPoint] = []
    private var lockedFace: CGPoint?
    private var previousMask: CIImage?
    private var cachedMask: CIImage?
    private var maskSlots: [CVPixelBuffer] = []
    private var maskSlot = 0
    private var segmentTick = 0
    private var still: CIImage?
    private let video = VideoLoop()

    init() {
        preparePool()
    }

    func setZoom(_ value: CGFloat, allowsAuto: Bool) {
        zoom = min(2, max(1, value))
        clearMask()
        if !allowsAuto {
            allowsAutoZoom = false
            didAutoZoom = true
        } else {
            allowsAutoZoom = true
        }
    }

    func setPlate(url: URL?, video: Bool) {
        clearMask()
        if let url, video {
            still = nil
            self.video.setURL(url)
            return
        }
        self.video.setURL(nil)
        guard let url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            still = nil
            return
        }
        still = CIImage(cgImage: image)
    }

    func resetFraming() {
        faceSamples.removeAll()
        lockedFace = nil
        clearMask()
        didAutoZoom = !allowsAutoZoom
    }

    /// Holds the crop still for the take, so the loop does not drift.
    func beginTake() {
        guard lockedFace == nil else { return }
        let samples = faceSamples.isEmpty
            ? [CGPoint(x: canvas.midX, y: canvas.midY)]
            : faceSamples
        let count = CGFloat(samples.count)
        lockedFace = CGPoint(
            x: samples.reduce(0) { $0 + $1.x } / count,
            y: samples.reduce(0) { $0 + $1.y } / count
        )
        faceSamples.removeAll()
        clearMask()
    }

    func render(camera: CVPixelBuffer) -> CVPixelBuffer? {
        guard let filled = aspectFilled(CIImage(cvPixelBuffer: camera)) else { return nil }
        rememberFace(in: filled)
        let framed = zoomed(filled)
        guard let plate = plateImage() else { return render(framed) }
        guard let personBuffer = render(framed) else { return nil }
        let person = CIImage(cvPixelBuffer: personBuffer)
        segmentTick += 1
        let mask: CIImage
        if segmentTick % 2 == 0, let cachedMask {
            mask = cachedMask
        } else if let maskBuffer = personMask(from: personBuffer) {
            mask = softened(fitted(CIImage(cvPixelBuffer: maskBuffer), to: person.extent))
            cachedMask = mask
        } else if let cachedMask {
            mask = cachedMask
        } else {
            return render(person)
        }
        return render(composite(person: person, background: plate, mask: mask))
    }

    private func clearMask() {
        previousMask = nil
        cachedMask = nil
        segmentTick = 0
    }

    private func rememberFace(in image: CIImage) {
        guard lockedFace == nil else { return }
        guard let face = largestFace(in: image) else { return }
        let box = CGRect(
            x: image.extent.minX + face.boundingBox.minX * image.extent.width,
            y: image.extent.minY + face.boundingBox.minY * image.extent.height,
            width: face.boundingBox.width * image.extent.width,
            height: face.boundingBox.height * image.extent.height
        )
        if allowsAutoZoom, !didAutoZoom {
            let fraction = box.height / canvas.height
            if fraction > 0.08, fraction < 0.75 {
                zoom = min(2, max(1.1, 0.30 / fraction))
                didAutoZoom = true
                let value = Double(zoom)
                DispatchQueue.main.async { [weak self] in
                    self?.onAutoZoom?(value)
                }
            }
        }
        faceSamples.append(CGPoint(x: box.midX, y: box.midY))
        guard faceSamples.count >= 6 else { return }
        let count = CGFloat(faceSamples.count)
        lockedFace = CGPoint(
            x: faceSamples.reduce(0) { $0 + $1.x } / count,
            y: faceSamples.reduce(0) { $0 + $1.y } / count
        )
        faceSamples.removeAll()
        clearMask()
    }

    private func largestFace(in image: CIImage) -> VNFaceObservation? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return request.results?.max { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }
    }

    private func personMask(from buffer: CVPixelBuffer) -> CVPixelBuffer? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return request.results?.first?.pixelBuffer
    }

    private func plateImage() -> CIImage? {
        if let frame = video.image() { return frame }
        return still
    }

    /// Puts the face a little above center, at the person’s zoom.
    private func zoomed(_ image: CIImage) -> CIImage {
        let z = min(2, max(1, zoom))
        guard z > 1.01 else { return image }
        let cropWidth = canvas.width / z
        let cropHeight = canvas.height / z
        let anchor = lockedFace ?? CGPoint(x: canvas.midX, y: canvas.midY)
        let targetFromBottom = 0.58 * cropHeight
        var originX = anchor.x - cropWidth / 2
        var originY = anchor.y - targetFromBottom
        originX = min(max(originX, 0), canvas.width - cropWidth)
        originY = min(max(originY, 0), canvas.height - cropHeight)
        let crop = CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight)
        return image
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -originX, y: -originY))
            .transformed(by: CGAffineTransform(scaleX: z, y: z))
            .cropped(to: canvas)
    }

    private func composite(person: CIImage, background: CIImage, mask: CIImage) -> CIImage {
        let plate = aspectFilled(background) ?? background
        return person.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: plate,
            kCIInputMaskImageKey: mask
        ]).cropped(to: canvas)
    }

    private func softened(_ mask: CIImage) -> CIImage {
        let soft = mask
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.6])
            .cropped(to: canvas)
        guard let previousMask else {
            let flat = flatten(soft)
            self.previousMask = flat
            return flat
        }
        let mixed = soft.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: previousMask,
            kCIInputTimeKey: 0.3
        ]).cropped(to: canvas)
        let flat = flatten(mixed)
        self.previousMask = flat
        return flat
    }

    /// Keeps one flat mask. A filter chain here grew without limit and held about a gigabyte.
    private func flatten(_ image: CIImage) -> CIImage {
        if maskSlots.count < 2 {
            maskSlots = (0..<2).compactMap { _ in makeMaskBuffer() }
        }
        guard maskSlots.count == 2 else { return image }
        let buffer = maskSlots[maskSlot % 2]
        maskSlot += 1
        context.render(image, to: buffer, bounds: canvas, colorSpace: colorSpace)
        return CIImage(cvPixelBuffer: buffer)
    }

    private func makeMaskBuffer() -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: PresenceFormat.width,
            kCVPixelBufferHeightKey as String: PresenceFormat.height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            PresenceFormat.width,
            PresenceFormat.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &buffer
        )
        return buffer
    }

    private func fitted(_ image: CIImage, to extent: CGRect) -> CIImage {
        let scaleX = extent.width / max(image.extent.width, 1)
        let scaleY = extent.height / max(image.extent.height, 1)
        return image
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
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
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        context.render(image, to: buffer, bounds: canvas, colorSpace: colorSpace)
        return buffer
    }

    private func preparePool() {
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: PresenceFormat.width,
            kCVPixelBufferHeightKey as String: PresenceFormat.height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
    }
}

/// Plays a Zoom video background on a loop and hands over the newest frame.
private final class VideoLoop {
    private var location: URL?
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var latest: CIImage?
    private var duration: TimeInterval = 1
    private var anchor = ProcessInfo.processInfo.systemUptime

    func setURL(_ url: URL?) {
        location = url
        latest = nil
        reader = nil
        output = nil
        anchor = ProcessInfo.processInfo.systemUptime
        if url != nil {
            open(at: .zero)
        }
    }

    func image() -> CIImage? {
        guard location != nil else { return nil }
        pull()
        return latest
    }

    private func open(at time: CMTime) {
        guard let location else { return }
        let asset = AVURLAsset(url: location)
        let seconds = CMTimeGetSeconds(asset.duration)
        if seconds.isFinite, seconds > 0.05 {
            duration = seconds
        }
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: time, duration: .positiveInfinity)
        guard reader.startReading() else { return }
        self.reader = reader
        self.output = output
    }

    private func pull() {
        let elapsed = ProcessInfo.processInfo.systemUptime - anchor
        let looped = elapsed.truncatingRemainder(dividingBy: duration)
        if reader == nil || reader?.status == .completed || reader?.status == .failed {
            open(at: .zero)
            anchor = ProcessInfo.processInfo.systemUptime
        }
        guard let output else { return }
        for _ in 0..<3 {
            guard let sample = output.copyNextSampleBuffer(),
                  let buffer = CMSampleBufferGetImageBuffer(sample) else {
                open(at: .zero)
                anchor = ProcessInfo.processInfo.systemUptime
                return
            }
            latest = CIImage(cvPixelBuffer: buffer)
            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            if time + 1.0 / 30.0 >= looped { break }
        }
    }
}
