import Foundation

enum WebcamKind: Int, Comparable {
    case external = 0
    case builtIn = 1
    case continuity = 2

    static func < (lhs: WebcamKind, rhs: WebcamKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct WebcamCandidate: Equatable {
    var id: String
    var name: String
    var kind: WebcamKind
}

struct SinkCandidate: Equatable {
    var name: String
    var uid: String
}

/// Which real webcam to open, and which already-trusted virtual camera Zoom should see.
enum CameraPolicy {
    private static let obsName = "OBS Virtual Camera"
    private static let obsUID = "7626645E-4425-469E-9D8B-97E0FA59AC75"
    private static let elgatoName = "Elgato Virtual Camera"

    static func isUsableWebcam(name: String, uid: String) -> Bool {
        rank(name: name, uid: uid) >= 9
    }

    /// A plugged-in camera leads. A built-in camera leads a nearby phone. Facecam leads other USB cameras.
    static func orderedWebcams(_ cameras: [WebcamCandidate]) -> [WebcamCandidate] {
        cameras.filter { isUsableWebcam(name: $0.name, uid: $0.id) }.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            let leftFace = lhs.name.localizedCaseInsensitiveContains("facecam")
            let rightFace = rhs.name.localizedCaseInsensitiveContains("facecam")
            if leftFace != rightFace { return leftFace }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func acceptsOutput(name: String, uid: String) -> Bool {
        rank(name: name, uid: uid) < 9
    }

    static func isOBS(name: String, uid: String) -> Bool {
        if name.compare(obsName, options: .caseInsensitive) == .orderedSame { return true }
        return uid.compare(obsUID, options: .caseInsensitive) == .orderedSame
    }

    /// OBS advertises only 1920x1080. Other sinks keep the 720p picture this app already draws.
    static func outputSize(name: String, uid: String) -> (width: Int32, height: Int32) {
        if isOBS(name: name, uid: uid) { return (1920, 1080) }
        return (Int32(PresenceFormat.width), Int32(PresenceFormat.height))
    }

    static func preferredSink(_ sinks: [SinkCandidate]) -> SinkCandidate? {
        sinks.filter { acceptsOutput(name: $0.name, uid: $0.uid) }.min { lhs, rhs in
            let left = rank(name: lhs.name, uid: lhs.uid)
            let right = rank(name: rhs.name, uid: rhs.uid)
            if left != right { return left < right }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// 0 Presence, 1 OBS, 2 Elgato, 3 any other virtual camera, 9 a real webcam.
    private static func rank(name: String, uid: String) -> Int {
        if name.compare(PresenceFormat.cameraName, options: .caseInsensitive) == .orderedSame { return 0 }
        if isOBS(name: name, uid: uid) { return 1 }
        if name.compare(elgatoName, options: .caseInsensitive) == .orderedSame { return 2 }
        if name.localizedCaseInsensitiveContains("virtual") { return 3 }
        return 9
    }
}
