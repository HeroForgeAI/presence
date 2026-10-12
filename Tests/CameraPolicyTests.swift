import XCTest

final class CameraPolicyTests: XCTestCase {
    func testALaptopCameraIsChosenWhenItIsTheOnlyWebcam() {
        let cameras = [WebcamCandidate(id: "1", name: "FaceTime HD Camera", kind: .builtIn)]
        XCTAssertEqual(CameraPolicy.orderedWebcams(cameras).map(\.name), ["FaceTime HD Camera"])
    }

    func testBuiltInBeatsANearbyPhone() {
        let cameras = [
            WebcamCandidate(id: "p", name: "iPhone", kind: .continuity),
            WebcamCandidate(id: "b", name: "FaceTime HD Camera", kind: .builtIn)
        ]
        XCTAssertEqual(CameraPolicy.orderedWebcams(cameras).first?.name, "FaceTime HD Camera")
    }

    func testFacecamStillLeadsWhenItIsPluggedIn() {
        let cameras = [
            WebcamCandidate(id: "b", name: "FaceTime HD Camera", kind: .builtIn),
            WebcamCandidate(id: "l", name: "Logitech StreamCam", kind: .external),
            WebcamCandidate(id: "f", name: "Elgato Facecam 4K", kind: .external)
        ]
        XCTAssertEqual(CameraPolicy.orderedWebcams(cameras).map(\.name), [
            "Elgato Facecam 4K",
            "Logitech StreamCam",
            "FaceTime HD Camera"
        ])
    }

    func testARenamedOBSCameraIsNotAWebcam() {
        let cameras = [
            WebcamCandidate(id: "7626645E-4425-469E-9D8B-97E0FA59AC75", name: "Renamed", kind: .external),
            WebcamCandidate(id: "built", name: "FaceTime HD Camera", kind: .builtIn)
        ]
        XCTAssertEqual(CameraPolicy.orderedWebcams(cameras).map(\.name), ["FaceTime HD Camera"])
    }

    func testVirtualCamerasAreNotWebcams() {
        let cameras = [
            WebcamCandidate(id: "e", name: "Elgato Virtual Camera", kind: .external),
            WebcamCandidate(id: "o", name: "OBS Virtual Camera", kind: .external),
            WebcamCandidate(id: "p", name: "Presence", kind: .external),
            WebcamCandidate(id: "b", name: "FaceTime HD Camera", kind: .builtIn)
        ]
        XCTAssertEqual(CameraPolicy.orderedWebcams(cameras).map(\.name), ["FaceTime HD Camera"])
    }

    func testSinkPrefersOBSThenElgato() {
        let sinks = [
            SinkCandidate(name: "Elgato Virtual Camera", uid: "elgato"),
            SinkCandidate(name: "ManyCam Virtual Webcam", uid: "many"),
            SinkCandidate(name: "OBS Virtual Camera", uid: "obs"),
            SinkCandidate(name: "FaceTime HD Camera", uid: "face")
        ]
        XCTAssertEqual(CameraPolicy.preferredSink(sinks)?.name, "OBS Virtual Camera")
    }

    func testSinkUsesElgatoWhenThatIsAllTheMacHas() {
        let sinks = [
            SinkCandidate(name: "Elgato Facecam 4K", uid: "face"),
            SinkCandidate(name: "Elgato Virtual Camera", uid: "elgato")
        ]
        XCTAssertEqual(CameraPolicy.preferredSink(sinks)?.name, "Elgato Virtual Camera")
    }

    func testNoSinkWhenTheMacOnlyHasABuiltInCamera() {
        let sinks = [SinkCandidate(name: "FaceTime HD Camera", uid: "face")]
        XCTAssertNil(CameraPolicy.preferredSink(sinks))
    }

    func testOBSSizeIs1080pAndANormalSinkStays720() {
        XCTAssertEqual(CameraPolicy.outputSize(name: "OBS Virtual Camera", uid: "x").width, 1920)
        XCTAssertEqual(CameraPolicy.outputSize(name: "Elgato Virtual Camera", uid: "x").width, 1280)
        XCTAssertEqual(CameraPolicy.outputSize(name: "Renamed", uid: "7626645E-4425-469E-9D8B-97E0FA59AC75").width, 1920)
        XCTAssertEqual(CameraPolicy.outputSize(name: "Renamed", uid: "7626645E-4425-469E-9D8B-97E0FA59AC75").height, 1080)
    }
}
