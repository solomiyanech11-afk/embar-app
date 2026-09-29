//
//  ReaderQuoteBuilderTests.swift
//  EmbarTests
//
//  Блок цитати для quoteToNote (SPEC §12.3): атрибути тіла й підпису,
//  формат підпису, парсинг лінка "book|entry".
//
//  i18n 2026-08-03: лапки, мітки типів і «Без назви» тепер перекладаються,
//  тож очікування будуються з тих самих джерел, що й сам білдер — інакше
//  тести залежали б від мови, якою запущено тест-хост.
//

import XCTest
@testable import Embar

final class ReaderQuoteBuilderTests: XCTestCase {

    private let bookID = UUID(uuidString: "AA0BF858-0001-4000-8000-000000000001")!
    private let entryID = UUID(uuidString: "BB1CF858-0002-4000-8000-000000000002")!

    /// Текст у лапках мовою інтерфейсу («…» для uk, “…” для en)
    private func quoted(_ text: String) -> String {
        String(localized: "«\(text)»")
    }

    func testSourceValueRoundTrip() {
        let raw = ReaderQuoteBuilder.sourceValue(book: bookID, entry: entryID)
        let parsed = try! XCTUnwrap(ReaderQuoteBuilder.parseSource(raw))
        XCTAssertEqual(parsed.book, bookID)
        XCTAssertEqual(parsed.entry, entryID)
        XCTAssertNil(ReaderQuoteBuilder.parseSource("сміття"))
        XCTAssertNil(ReaderQuoteBuilder.parseSource("a|b"))
    }

    func testQuoteBodyWrappedAndMarked() {
        let block = ReaderQuoteBuilder.block(
            bookID: bookID, bookTitle: "Дизайн", entryID: entryID,
            kind: .quote, text: "форма слідує за функцією",
            author: "Салліван")
        XCTAssertTrue(block.string.hasPrefix(quoted("форма слідує за функцією") + "\n"))
        // Тіло позначене .embarReaderQuote (світла риска .qn-quote) і курсивом
        XCTAssertEqual(block.attribute(.embarReaderQuote, at: 0, effectiveRange: nil)
            as? NSNumber, NSNumber(value: true))
        XCTAssertEqual(block.attribute(.embarItalic, at: 0, effectiveRange: nil)
            as? NSNumber, NSNumber(value: true))
    }

    func testCaptionCarriesSourceAndAuthor() {
        let block = ReaderQuoteBuilder.block(
            bookID: bookID, bookTitle: "Дизайн", entryID: entryID,
            kind: .quote, text: "т", author: "Салліван")
        let ns = block.string as NSString
        let captionStart = ns.range(of: "\n").location + 1
        let raw = block.attribute(.embarReaderSource, at: captionStart,
                                  effectiveRange: nil) as? String
        XCTAssertEqual(raw, ReaderQuoteBuilder.sourceValue(book: bookID, entry: entryID))
        XCTAssertTrue(block.string.contains("САЛЛІВАН · ДИЗАЙН"))
        XCTAssertEqual(block.attribute(.embarQuoteAuthor, at: captionStart,
                                       effectiveRange: nil) as? NSNumber,
                       NSNumber(value: true))
    }

    func testNonQuoteUsesTypeLabelAndPlainBody() {
        let block = ReaderQuoteBuilder.block(
            bookID: bookID, bookTitle: "Книга", entryID: entryID,
            kind: .thought, text: "проста думка", author: nil)
        XCTAssertTrue(block.string.hasPrefix("проста думка\n")) // без лапок
        let thought = ReaderQuoteBuilder.typeLabel(.thought).uppercased()
        XCTAssertTrue(block.string.contains("\(thought) · КНИГА"))
        XCTAssertFalse(block.string.contains("СТ."))
    }

    func testUntitledBookFallback() {
        let block = ReaderQuoteBuilder.block(
            bookID: bookID, bookTitle: "", entryID: entryID,
            kind: .thought, text: "т", author: nil)
        let untitled = String(localized: "Без назви").uppercased()
        XCTAssertTrue(block.string.contains(untitled))
    }

    func testBlockEndsWithEmptyParagraph() {
        let block = ReaderQuoteBuilder.block(
            bookID: bookID, bookTitle: "К", entryID: entryID,
            kind: .quote, text: "т", author: nil)
        XCTAssertTrue(block.string.hasSuffix("\n\n"))
    }
}
