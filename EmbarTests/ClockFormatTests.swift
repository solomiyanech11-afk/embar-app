//
//  ClockFormatTests.swift
//  EmbarTests
//
//  Формат часу йде за системою (рішення 2026-08-07): 12 чи 24 години
//  вирішує перемикач «24-Hour Time» у налаштуваннях macOS, а не застосунок.
//
//  Вісь таймлайну перевіряється з ЯВНОЮ локаллю в обидві сторони — інакше
//  на машині з 12-годинним форматом 24-годинна гілка (український вигляд,
//  який я не мав зламати) лишилась би не перевіреною взагалі.
//

import XCTest
@testable import Embar

final class ClockFormatTests: XCTestCase {

    private let calendar = Calendar.current
    /// Локаль із 24-годинним форматом
    private let uk = Locale(identifier: "uk_UA")
    /// Локаль із 12-годинним
    private let us = Locale(identifier: "en_US")

    private func date(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 13,
                                           hour: hour, minute: minute))!
    }

    // MARK: - Розпізнавання формату

    func testClockDetection() {
        XCTAssertFalse(ReaderDateFormat.uses12HourClock(uk))
        XCTAssertTrue(ReaderDateFormat.uses12HourClock(us))
    }

    /// Колонка часу мусить вміщати НАЙДОВШИЙ рядок своєї локалі —
    /// інакше «9:26 AM» переноситься на два рядки (баг 2026-08-09)
    func testTimeColumnFitsBothFormats() {
        XCTAssertEqual(ReaderDateFormat.timeColumnWidth(uk), 32,
                       "українською вигляд не мав змінитись")
        XCTAssertGreaterThan(ReaderDateFormat.timeColumnWidth(us),
                             ReaderDateFormat.timeColumnWidth(uk),
                             "12-годинний рядок довший — колонка мусить бути ширшою")
    }

    // MARK: - Час запису

    /// Час читається як час: є хвилини й розділювач
    func testTimeHasMinutes() {
        let text = ReaderDateFormat.time(date(14, 5))
        XCTAssertTrue(text.contains("05"), "хвилини загубились: \(text)")
        XCTAssertTrue(text.contains(":") || text.contains("."),
                      "немає розділювача годин і хвилин: \(text)")
    }

    /// Позначка «після полудня» СВОЄЮ мовою: українською це «пп», а не
    /// «PM». Тест раніше шукав літерали і падав на 12-годинній системі
    /// з українським інтерфейсом (2026-08-12)
    private var pmSymbol: String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        return f.pmSymbol ?? "PM"
    }

    /// Іде за системою: 24 години — без позначки, 12 — з нею і без «14»
    func testTimeFollowsSystemClock() {
        let afternoon = ReaderDateFormat.time(date(14, 5))
        if ReaderDateFormat.uses12HourClock() {
            XCTAssertTrue(afternoon.localizedCaseInsensitiveContains(pmSymbol),
                          "12-годинна система, а позначки «\(pmSymbol)» немає: \(afternoon)")
            XCTAssertTrue(afternoon.contains("2"), "очікували 2:05 \(pmSymbol): \(afternoon)")
        } else {
            XCTAssertTrue(afternoon.contains("14"),
                          "24-годинна система, а години не 14: \(afternoon)")
            XCTAssertFalse(afternoon.localizedCaseInsensitiveContains(pmSymbol),
                           "24-годинна система, а позначка «\(pmSymbol)» є: \(afternoon)")
        }
    }

    // MARK: - Вісь таймлайну Home

    /// 24 години: вигляд осі точно як був до правки, включно з «24:00»
    /// на кінцевій зарубці доби
    func testHourLabelUnchangedFor24Hour() {
        XCTAssertEqual(ReaderDateFormat.hourLabel(0, locale: uk), "0:00")
        XCTAssertEqual(ReaderDateFormat.hourLabel(9, locale: uk), "9:00")
        XCTAssertEqual(ReaderDateFormat.hourLabel(14, locale: uk), "14:00")
        XCTAssertEqual(ReaderDateFormat.hourLabel(24, locale: uk), "24:00")
    }

    /// 12 годин: вісь підписана як у Календарі — «12 AM» / «2 PM»
    func testHourLabelUsesPeriodFor12Hour() {
        let midnight = ReaderDateFormat.hourLabel(0, locale: us)
        let afternoon = ReaderDateFormat.hourLabel(14, locale: us)
        XCTAssertTrue(midnight.localizedCaseInsensitiveContains("am"), midnight)
        XCTAssertTrue(afternoon.localizedCaseInsensitiveContains("pm"), afternoon)
        XCTAssertTrue(afternoon.contains("2"), afternoon)
        // Хвилин на осі немає — година з AM/PM самодостатня
        XCTAssertFalse(afternoon.contains(":"), afternoon)
        // Кінець доби = опівніч, а не «24»
        XCTAssertEqual(ReaderDateFormat.hourLabel(24, locale: us), midnight)
    }

    /// Жоден підпис осі не порожній — 25 зарубок від 0 до 24, обидві мови
    func testEveryHourLabelIsNonEmpty() {
        for locale in [uk, us] {
            for hour in 0...24 {
                XCTAssertFalse(ReaderDateFormat.hourLabel(hour, locale: locale).isEmpty,
                               "порожній підпис для години \(hour)")
            }
        }
    }
}
