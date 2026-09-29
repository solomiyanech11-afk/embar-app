//
//  VoiceWaveformTests.swift
//  EmbarTests
//
//  Хвиля голосового запису (SPEC §4.3): бари детерміновані від id —
//  однакові між рендерами і перезапусками, в межах 7–22px.
//

import XCTest
@testable import Embar

final class VoiceWaveformTests: XCTestCase {

    func testDeterministicForSameSeed() {
        let id = UUID(uuidString: "AA0BF858-0001-4000-8000-000000000001")!
        XCTAssertEqual(VoiceWaveform.heights(seed: id, count: 26),
                       VoiceWaveform.heights(seed: id, count: 26))
    }

    func testHeightsWithinPrototypeRange() {
        let heights = VoiceWaveform.heights(seed: UUID(), count: 40)
        XCTAssertEqual(heights.count, 40)
        XCTAssertTrue(heights.allSatisfy { $0 >= 7 && $0 <= 22 })
    }

    func testDifferentSeedsDiffer() {
        let a = VoiceWaveform.heights(
            seed: UUID(uuidString: "AA0BF858-0001-4000-8000-000000000001")!,
            count: 26)
        let b = VoiceWaveform.heights(
            seed: UUID(uuidString: "BB1CF858-0002-4000-8000-000000000002")!,
            count: 26)
        XCTAssertNotEqual(a, b)
    }

    func testBarsVaryWithinOneWave() {
        let heights = VoiceWaveform.heights(seed: UUID(), count: 26)
        XCTAssertTrue(Set(heights).count > 3, "хвиля не має бути пласкою")
    }
}
