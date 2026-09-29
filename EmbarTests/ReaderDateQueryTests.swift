//
//  ReaderDateQueryTests.swift
//  EmbarTests
//
//  Розпізнавання дати в пошуковому запиті блокнота (#6, SPEC M5).
//
//  i18n 2026-08-03: тести більше не прибиті до українських слів —
//  запит будується з тих самих джерел, що бачить користувач
//  (todayWord/yesterdayWord, ReaderDateFormat.monthsShort), тож вони
//  проходять і коли тест-хост запущено англійською. Порядок чисел
//  («05.07» vs «07/05») перевіряється з явною локаллю.
//

import XCTest
@testable import Embar

final class ReaderDateQueryTests: XCTestCase {

    private let calendar = Calendar.current
    private let uk = Locale(identifier: "uk_UA")
    private let us = Locale(identifier: "en_US")

    // Фіксоване «зараз», щоб тести не залежали від дня запуску
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: 15))!
    }

    private func start(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testToday() {
        let interval = ReaderDateQuery.dayInterval(from: ReaderDateQuery.todayWord,
                                                   now: now)
        XCTAssertEqual(interval?.start, start(2026, 7, 7))
        XCTAssertEqual(interval?.duration, 86400)
    }

    func testYesterdayCaseInsensitiveAndTrimmed() {
        let typed = "  " + ReaderDateQuery.yesterdayWord.uppercased() + " "
        let interval = ReaderDateQuery.dayInterval(from: typed, now: now)
        XCTAssertEqual(interval?.start, start(2026, 7, 6))
    }

    func testDottedDayMonthUkrainianOrder() {
        XCTAssertEqual(ReaderDateQuery.dayInterval(from: "05.07", now: now,
                                                   locale: uk)?.start,
                       start(2026, 7, 5))
        XCTAssertEqual(ReaderDateQuery.dayInterval(from: "5.7", now: now,
                                                   locale: uk)?.start,
                       start(2026, 7, 5))
    }

    /// en_US читає ті самі числа навпаки — місяць першим
    func testNumericAmericanOrder() {
        XCTAssertEqual(ReaderDateQuery.dayInterval(from: "07/05", now: now,
                                                   locale: us)?.start,
                       start(2026, 7, 5))
    }

    func testDottedWithYear() {
        XCTAssertEqual(ReaderDateQuery.dayInterval(from: "31.12.2025", now: now,
                                                   locale: uk)?.start,
                       start(2025, 12, 31))
    }

    func testDayMonthAbbrev() {
        // Липень — сьомий місяць; беремо скорочення мовою інтерфейсу
        let july = ReaderDateFormat.monthsShort[6]
        XCTAssertEqual(ReaderDateQuery.dayInterval(from: "5 \(july)", now: now)?.start,
                       start(2026, 7, 5))
    }

    /// Крапка й регістр у скороченні місяця не заважають
    func testDayMonthAbbrevIgnoresDotAndCase() {
        let july = ReaderDateFormat.monthsShort[6]
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .uppercased()
        XCTAssertEqual(ReaderDateQuery.dayInterval(from: "5 \(july).", now: now)?.start,
                       start(2026, 7, 5))
    }

    func testInvalidDateFallsThrough() {
        XCTAssertNil(ReaderDateQuery.dayInterval(from: "32.13", now: now, locale: uk))
        XCTAssertNil(ReaderDateQuery.dayInterval(from: "0.5", now: now, locale: uk))
    }

    func testPlainTextIsNotADate() {
        XCTAssertNil(ReaderDateQuery.dayInterval(from: "філософія", now: now))
        XCTAssertNil(ReaderDateQuery.dayInterval(from: "5 думок", now: now))
        XCTAssertNil(ReaderDateQuery.dayInterval(from: "", now: now))
    }
}
