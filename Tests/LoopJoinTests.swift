import XCTest

final class LoopJoinTests: XCTestCase {
    func testShortTakeStaysWhole() {
        XCTAssertEqual(LoopJoin.trimLength(distancesToFirst: [0, 3, 2, 4]), 4)
    }

    func testEmptyTakeStaysEmpty() {
        XCTAssertEqual(LoopJoin.trimLength(distancesToFirst: []), 0)
    }

    func testEndLandsOnTheClosestLaterPose() {
        let distances: [Float] = [0, 1, 9, 9, 9, 9, 9, 9, 4, 8]
        XCTAssertEqual(LoopJoin.trimLength(distancesToFirst: distances), 9)
    }

    func testAnEarlyMatchDoesNotCutTheTakeShort() {
        let distances: [Float] = [0, 0.2, 8, 8, 8, 8, 8, 8, 7, 6]
        let kept = LoopJoin.trimLength(distancesToFirst: distances)
        XCTAssertGreaterThan(kept, 6)
    }
}
