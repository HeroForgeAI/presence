import Foundation

/// How two stored frames combine at one moment in a loop.
struct LoopBlend: Equatable {
    var index: Int
    var other: Int
    /// 0 shows `index`. 1 shows `other`.
    var mix: Double
}

enum LoopMath {
    /// Crossfade the tail of a take into its first frame so the repeat joins cleanly.
    static func blend(frame: Int, count: Int, fadeFrames: Int) -> LoopBlend {
        guard count > 1 else {
            return LoopBlend(index: 0, other: 0, mix: 0)
        }
        let index = ((frame % count) + count) % count
        let fade = min(max(fadeFrames, 0), count / 2)
        guard fade > 0, index >= count - fade else {
            return LoopBlend(index: index, other: index, mix: 0)
        }
        // Two frames is a cut onto the first frame. A half mix on the frame before it ghosts.
        if fade <= 2 {
            guard index == count - 1 else {
                return LoopBlend(index: index, other: index, mix: 0)
            }
            return LoopBlend(index: index, other: 0, mix: 1)
        }
        let mix = Double(index - (count - fade) + 1) / Double(fade)
        return LoopBlend(index: index, other: 0, mix: min(max(mix, 0), 1))
    }
}

/// Picks where a take should end so the repeat joins on a similar moment.
enum LoopJoin {
    static func distance(_ a: [UInt8], _ b: [UInt8]) -> Float {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var sum = 0
        for index in 0..<count {
            sum += abs(Int(a[index]) - Int(b[index]))
        }
        return Float(sum) / Float(count)
    }

    static func distancesToFirst(_ marks: [[UInt8]]) -> [Float] {
        guard let first = marks.first else { return [] }
        return marks.map { distance($0, first) }
    }

    /// Keeps the back of the take through the frame most like the first one.
    static func trimLength(distancesToFirst: [Float], minimumFraction: Double = 0.62) -> Int {
        let count = distancesToFirst.count
        guard count > 8 else { return count }
        let start = min(count - 2, max(1, Int(Double(count) * minimumFraction)))
        var bestIndex = count - 1
        var best = Float.greatestFiniteMagnitude
        for index in start..<count {
            let distance = distancesToFirst[index]
            if distance < best {
                best = distance
                bestIndex = index
            }
        }
        return bestIndex + 1
    }
}

enum TakeDuration: Int, CaseIterable, Identifiable {
    case five = 5
    case eight = 8
    case ten = 10
    case twenty = 20
    case forty = 40

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var label: String { "\(rawValue)" }
}

enum PresenceFormat {
    static let width = 1280
    static let height = 720
    static let frameRate = 30
    static let cameraName = "Presence"
    static let bundleIdentifier = "com.makallen.presence"
    static let extensionIdentifier = "com.makallen.presence.camera"
    /// Two frames. The last one is the first frame, so the repeat does not ghost.
    static let fadeFrames = 2
}
