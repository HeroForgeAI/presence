import XCTest

final class LoopMathTests: XCTestCase {
    func testMiddleOfTakeDoesNotBlend() {
        let blend = LoopMath.blend(frame: 10, count: 100, fadeFrames: 12)
        XCTAssertEqual(blend, LoopBlend(index: 10, other: 10, mix: 0))
    }

    func testTailDissolvesIntoTheFirstFrame() {
        let blend = LoopMath.blend(frame: 90, count: 100, fadeFrames: 10)
        XCTAssertEqual(blend.index, 90)
        XCTAssertEqual(blend.other, 0)
        XCTAssertEqual(blend.mix, 0.1, accuracy: 0.0001)
    }

    func testLastFrameIsTheFirstFrame() {
        let blend = LoopMath.blend(frame: 99, count: 100, fadeFrames: 10)
        XCTAssertEqual(blend.mix, 1, accuracy: 0.0001)
        XCTAssertEqual(blend.other, 0)
    }

    func testATwoFrameJoinDoesNotGhostTheFrameBeforeTheEnd() {
        let before = LoopMath.blend(frame: 98, count: 100, fadeFrames: 2)
        XCTAssertEqual(before.mix, 0, accuracy: 0.0001)
        let last = LoopMath.blend(frame: 99, count: 100, fadeFrames: 2)
        XCTAssertEqual(last.mix, 1, accuracy: 0.0001)
        XCTAssertEqual(last.other, 0)
    }

    func testSingleFrameDoesNotBlend() {
        let blend = LoopMath.blend(frame: 0, count: 1, fadeFrames: 12)
        XCTAssertEqual(blend.mix, 0)
    }
}
