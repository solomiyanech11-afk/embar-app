//
//  ReaderServiceTests.swift
//  EmbarTests
//
//  Чисті функції рідера: нормалізація URL джерела і виведення label
//  з домену (SPEC §11.8; поведінка дзеркалить прототип saveReaderLink).
//

import XCTest
@testable import Embar

final class ReaderServiceTests: XCTestCase {

    // MARK: - normalizedURL

    func testBareDomainGetsHTTPS() {
        XCTAssertEqual(ReaderService.normalizedURL("example.com"), "https://example.com")
    }

    func testPathKeptAfterNormalization() {
        XCTAssertEqual(ReaderService.normalizedURL("site.ua/стаття/1"),
                       "https://site.ua/стаття/1")
    }

    func testExistingHTTPSUntouched() {
        XCTAssertEqual(ReaderService.normalizedURL("https://example.com/a"),
                       "https://example.com/a")
    }

    func testExistingHTTPUntouched() {
        // Як у прототипі: http не апгрейдимо примусово
        XCTAssertEqual(ReaderService.normalizedURL("http://old.site"), "http://old.site")
    }

    // MARK: - sourceLabel

    func testLabelIsHostWithoutProtocol() {
        XCTAssertEqual(ReaderService.sourceLabel("https://example.com/read/1"), "example.com")
    }

    func testLabelFromBareDomain() {
        XCTAssertEqual(ReaderService.sourceLabel("example.com"), "example.com")
    }

    func testLabelKeepsWWW() {
        // Прототип НЕ зрізає www — лишаємо його поведінку
        XCTAssertEqual(ReaderService.sourceLabel("www.site.com/path"), "www.site.com")
    }

    func testLabelFromHTTPURL() {
        XCTAssertEqual(ReaderService.sourceLabel("http://a.ua/b/c"), "a.ua")
    }
}

// MARK: - Курсор інлайн-редактора

/// Багаторядковий запис відкривається з початку: інакше NSTextView
/// прокручує стрічку до курсора в кінці тексту, і при кліку «редагувати»
/// список стрибав униз (баг 2026-08-09)
final class ReaderEditCaretTests: XCTestCase {

    func testSingleLineOpensAtEnd() {
        XCTAssertEqual(ReaderEditCaret.location(in: "коротка думка"), 13)
        XCTAssertEqual(ReaderEditCaret.location(in: ""), 0)
    }

    func testMultilineOpensAtStart() {
        XCTAssertEqual(ReaderEditCaret.location(in: "перший\nдругий"), 0)
        XCTAssertEqual(ReaderEditCaret.location(in: "абзац\n\nще абзац"), 0)
    }

    /// Емодзі рахуються в UTF-16, як і селекція NSTextView
    func testEndUsesUTF16Length() {
        XCTAssertEqual(ReaderEditCaret.location(in: "ok 🙂"), ("ok 🙂" as NSString).length)
    }
}
