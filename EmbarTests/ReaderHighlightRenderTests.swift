//
//  ReaderHighlightRenderTests.swift
//  EmbarTests
//
//  Валідація діапазонів UTF-16 і зведення сегментів (SPEC §11.6):
//  накладання «останній виграє», комбо заливка+лінія, биті діапазони.
//

import XCTest
@testable import Embar

final class ReaderHighlightRenderTests: XCTestCase {

    private func span(_ start: Int, _ end: Int, _ color: String = "yellow",
                      _ mode: String = "highlight") -> HighlightSpan {
        HighlightSpan(start: start, end: end, colorName: color, mode: mode)
    }

    // MARK: - Валідність

    func testValidRange() {
        XCTAssertTrue(ReaderHighlightRender.isValid(span(0, 5), length: 10))
        XCTAssertTrue(ReaderHighlightRender.isValid(span(9, 10), length: 10))
    }

    func testInvalidRanges() {
        XCTAssertFalse(ReaderHighlightRender.isValid(span(-1, 3), length: 10))
        XCTAssertFalse(ReaderHighlightRender.isValid(span(5, 5), length: 10))
        XCTAssertFalse(ReaderHighlightRender.isValid(span(7, 3), length: 10))
        XCTAssertFalse(ReaderHighlightRender.isValid(span(0, 11), length: 10))
    }

    // MARK: - Сегменти

    func testSingleFillSegment() {
        let segments = ReaderHighlightRender.segments(length: 10, spans: [span(2, 5)])
        XCTAssertEqual(segments, [
            .init(range: NSRange(location: 0, length: 2), fill: nil, stroke: nil),
            .init(range: NSRange(location: 2, length: 3), fill: "yellow", stroke: nil),
            .init(range: NSRange(location: 5, length: 5), fill: nil, stroke: nil),
        ])
    }

    func testLastFillWinsOnOverlap() {
        let segments = ReaderHighlightRender.segments(
            length: 10,
            spans: [span(0, 6, "yellow"), span(4, 8, "red")])
        // 4..6 — перетин: виграє пізніший red
        XCTAssertEqual(segments[1],
                       .init(range: NSRange(location: 4, length: 2),
                             fill: "red", stroke: nil))
        XCTAssertEqual(segments[0].fill, "yellow")
        XCTAssertEqual(segments[2].fill, "red")
    }

    func testFillAndUnderlineCombine() {
        let segments = ReaderHighlightRender.segments(
            length: 6,
            spans: [span(0, 6, "yellow", "highlight"),
                    span(2, 4, "blue", "underline")])
        let middle = segments.first { $0.range.location == 2 }
        XCTAssertEqual(middle?.fill, "yellow")
        XCTAssertEqual(middle?.stroke, "blue")
    }

    func testBrokenSpansIgnored() {
        let segments = ReaderHighlightRender.segments(
            length: 5, spans: [span(3, 99), span(-2, 2), span(1, 1)])
        XCTAssertTrue(segments.isEmpty)
    }

    // MARK: - Шматки слова (word-flow, точність до півслова)

    func testHalfWordSplitsAtBoundary() {
        // Слово 0..6, хайлайт 2..4 → [чисте 0-2][заливка 2-4][чисте 4-6]
        let pieces = ReaderHighlightRender.wordPieces(
            word: NSRange(location: 0, length: 6), length: 10,
            spans: [span(2, 4)])
        XCTAssertEqual(pieces.map(\.range),
                       [NSRange(location: 0, length: 2),
                        NSRange(location: 2, length: 2),
                        NSRange(location: 4, length: 2)])
        XCTAssertEqual(pieces.map(\.fill), [nil, "yellow", nil])
        // Смуга починається і закінчується всередині слова — обидва краї круглі
        XCTAssertFalse(pieces[1].fillContinuesLeft)
        XCTAssertFalse(pieces[1].fillContinuesRight)
    }

    func testContinuationAcrossWordEdges() {
        // Хайлайт 0..10 накриває слово 2..5 повністю і триває далі
        let pieces = ReaderHighlightRender.wordPieces(
            word: NSRange(location: 2, length: 3), length: 10,
            spans: [span(0, 10)])
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].fill, "yellow")
        XCTAssertTrue(pieces[0].fillContinuesLeft)
        XCTAssertTrue(pieces[0].fillContinuesRight)
    }

    func testNoSpansSinglePlainPiece() {
        let pieces = ReaderHighlightRender.wordPieces(
            word: NSRange(location: 3, length: 4), length: 10, spans: [])
        XCTAssertEqual(pieces,
                       [.init(range: NSRange(location: 3, length: 4),
                              fill: nil, stroke: nil,
                              fillContinuesLeft: false, fillContinuesRight: false)])
    }

    func testUnderlineBoundaryDoesNotBreakFillContinuity() {
        // Заливка 0..8 + підкреслення 3..5 ріже сегменти, але заливка
        // на межі 3 і 5 ТРИВАЄ — кути там мають бути квадратні
        let pieces = ReaderHighlightRender.wordPieces(
            word: NSRange(location: 0, length: 8), length: 8,
            spans: [span(0, 8, "yellow", "highlight"),
                    span(3, 5, "blue", "underline")])
        XCTAssertEqual(pieces.count, 3)
        XCTAssertTrue(pieces[0].fillContinuesRight)
        XCTAssertTrue(pieces[1].fillContinuesLeft)
        XCTAssertTrue(pieces[1].fillContinuesRight)
        XCTAssertTrue(pieces[2].fillContinuesLeft)
        XCTAssertEqual(pieces[1].stroke, "blue")
    }
}
