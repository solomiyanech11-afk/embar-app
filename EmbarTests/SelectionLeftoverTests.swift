//
//  SelectionLeftoverTests.swift
//  EmbarTests
//
//  Межа пісочниці на прибиранні залишку виділення (ревʼю 2026-08-18,
//  знахідка 9).
//
//  Історія: EmbarSelection.applyAppWide на КОЖНОМУ старті кликало
//  UserDefaults.standard.removeObject(forKey: "AppleHighlightColor") —
//  без гейта пісочниці й без перевірки, чиє це значення. Тобто тестовий
//  режим писав у РЕАЛЬНІ налаштування (інваріант CLAUDE.md такого не
//  передбачає), а свідомий `defaults write` користувачки мовчки гинув
//  при кожному запуску.
//
//  Сам `UserDefaults.standard` у тесті чіпати не можна — тому рішення
//  живе окремою чистою функцією, і перевіряємо саме її.
//

import XCTest
@testable import Embar

final class SelectionLeftoverTests: XCTestCase {

    /// Значення нашого формату: «R G B Embar»
    private let ours = "0.870588 0.866667 0.854902 Embar"

    func testRemovesOurOwnLeftover() {
        XCTAssertTrue(EmbarDefaults.shouldRemoveLeftover(value: ours,
                                                         isSandbox: false))
    }

    func testKeepsValueWrittenByTheUser() {
        // Людина свідомо зробила `defaults write nechai.Embar
        // AppleHighlightColor …` — це її вибір, не наш бруд
        XCTAssertFalse(EmbarDefaults.shouldRemoveLeftover(
            value: "1.000000 0.800000 0.600000 Peach", isSandbox: false))
        XCTAssertFalse(EmbarDefaults.shouldRemoveLeftover(
            value: "0.5 0.5 0.5", isSandbox: false))
    }

    func testSandboxNeverTouchesTheRealDomain() {
        XCTAssertFalse(EmbarDefaults.shouldRemoveLeftover(value: ours,
                                                          isSandbox: true))
    }

    func testNothingToRemove() {
        XCTAssertFalse(EmbarDefaults.shouldRemoveLeftover(value: nil,
                                                          isSandbox: false))
    }

    /// Формат значення і підпис, за яким його впізнають, мусять
    /// сходитись: розійдуться — і залишок ніколи не приберемо
    func testAppliedValueCarriesTheSignature() {
        let applied = EmbarSelection.highlightValue
        XCTAssertTrue(applied.hasSuffix(EmbarDefaults.leftoverSignature))
        XCTAssertTrue(EmbarDefaults.shouldRemoveLeftover(value: applied,
                                                         isSandbox: false))
    }
}
