//
//  PaywallDialogLedgerTests.swift
//  EmbarTests
//
//  Книга спроб системного діалогу (рецензія 2026-09-17, правки 3 і 4):
//  рівень пейвола й панель повертає лише власник найновішого талона.
//  Стара спроба, що відповіла після «Спробувати ще раз» або після
//  закриття й повторного відкриття вікна, нічого не піднімає.
//
//  Самі вікна тут не створюються (справжній пейвол читав би реальну
//  базу заради лічильника думок) - правило перевіряється на чистій
//  структурі, якою контролер і керується.
//

import XCTest
@testable import Embar

final class PaywallDialogLedgerTests: XCTestCase {

    func testLatestTokenOwnsRestore() {
        var ledger = SystemDialogLedger()
        let a = ledger.begin()
        XCTAssertTrue(ledger.owns(a), "єдина спроба - власник")

        let b = ledger.begin()
        XCTAssertFalse(ledger.owns(a),
                       "стара спроба після нової більше не повертає рівень")
        XCTAssertTrue(ledger.owns(b))
    }

    /// Сценарій рецензії: покупка A зависла → хрестик → відкрити знову →
    /// покупка B. Відповідь A не має опустити діалог B
    func testCloseInvalidatesPendingAttempt() {
        var ledger = SystemDialogLedger()
        let a = ledger.begin()
        ledger.invalidate()                 // хрестик посеред покупки
        XCTAssertFalse(ledger.owns(a), "після закриття вікна A - чужа")

        let b = ledger.begin()              // нове вікно, нова покупка
        XCTAssertFalse(ledger.owns(a))
        XCTAssertTrue(ledger.owns(b))
    }

    /// «Спробувати ще раз» талонів не чіпає: якщо нової спроби не
    /// буде, стара, коли таки відповість, сама все поверне
    func testGiveUpWithoutNewAttemptLeavesOwnerIntact() {
        var ledger = SystemDialogLedger()
        let a = ledger.begin()
        // giveUpWaiting() у моделі книгу не чіпає - тут нічого не робимо
        XCTAssertTrue(ledger.owns(a),
                      "без нової спроби відповідь A повертає рівень і панель")
    }
}
