//
//  HeroGreetingTests.swift
//  EmbarTests
//
//  Імʼя для привітання hero-картки Settings (SPEC §6).
//
//  Імʼя вводить користувач (поле зʼявиться разом з онбордингом), тож
//  тут перевіряється дві речі: як порожнє значення перетворюється на
//  привітання без імені, і що кламп 30 символів не ріже графеми навпіл.
//

import XCTest
@testable import Embar

final class HeroGreetingTests: XCTestCase {

    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = EmbarDefaults.store.string(forKey: HeroGreeting.storageKey)
    }

    override func tearDown() {
        if let saved { EmbarDefaults.store.set(saved, forKey: HeroGreeting.storageKey) }
        else { EmbarDefaults.store.removeObject(forKey: HeroGreeting.storageKey) }
        super.tearDown()
    }

    // MARK: - Показ

    func testEmptyNameMeansNoName() {
        XCTAssertNil(HeroGreeting.name(from: ""))
        XCTAssertNil(HeroGreeting.name(from: "   "))
        XCTAssertNil(HeroGreeting.name(from: "\n\t "))
    }

    func testNameIsTrimmed() {
        XCTAssertEqual(HeroGreeting.name(from: "  Соломія "), "Соломія")
    }

    /// Імʼя — дані користувача: не чіпаємо ні регістр, ні розкладку
    func testNameIsNotAlteredOtherwise() {
        XCTAssertEqual(HeroGreeting.name(from: "Соломія"), "Соломія")
        XCTAssertEqual(HeroGreeting.name(from: "o'Brien"), "o'Brien")
        XCTAssertEqual(HeroGreeting.name(from: "ANNA-MARIA"), "ANNA-MARIA")
    }

    // MARK: - Кламп

    func testShortNamePassesThrough() {
        XCTAssertEqual(HeroGreeting.clamped("Соломія"), "Соломія")
    }

    func testNameIsClampedToLimit() {
        let long = String(repeating: "я", count: 60)
        XCTAssertEqual(HeroGreeting.clamped(long).count, HeroGreeting.maxLength)
    }

    func testExactlyLimitIsUntouched() {
        let exact = String(repeating: "я", count: HeroGreeting.maxLength)
        XCTAssertEqual(HeroGreeting.clamped(exact), exact)
    }

    /// Ріжемо по символах, а не байтах — інакше емодзі чи літера
    /// з діакритикою розпалась би навпіл
    func testClampCountsCharactersNotBytes() {
        let emoji = String(repeating: "👩‍👩‍👧", count: 40)
        let clamped = HeroGreeting.clamped(emoji)
        XCTAssertEqual(clamped.count, HeroGreeting.maxLength)
        XCTAssertTrue(emoji.hasPrefix(clamped), "графему розрізало навпіл")
    }

    /// Обрізали посеред пробілу — хвіст не лишаємо
    func testClampTrimsTailAfterCut() {
        let name = String(repeating: "a", count: HeroGreeting.maxLength - 1) + " хвіст"
        XCTAssertFalse(HeroGreeting.clamped(name).hasSuffix(" "))
    }

    func testClampTrimsEdges() {
        XCTAssertEqual(HeroGreeting.clamped("   Соломія  "), "Соломія")
    }

    // MARK: - Сховище

    func testStoreClampsBeforeSaving() {
        HeroGreeting.store("  " + String(repeating: "я", count: 60) + "  ")
        XCTAssertEqual(HeroGreeting.stored.count, HeroGreeting.maxLength)
    }

    func testStoredIsEmptyByDefault() {
        EmbarDefaults.store.removeObject(forKey: HeroGreeting.storageKey)
        XCTAssertEqual(HeroGreeting.stored, "")
        XCTAssertNil(HeroGreeting.name(from: HeroGreeting.stored))
    }

    func testStoreRoundTrip() {
        HeroGreeting.store("Соломія")
        XCTAssertEqual(HeroGreeting.stored, "Соломія")
        XCTAssertEqual(HeroGreeting.name(from: HeroGreeting.stored), "Соломія")
    }
}
