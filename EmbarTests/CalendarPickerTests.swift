//
//  CalendarPickerTests.swift
//  EmbarTests
//
//  Власний календар (редизайн острівців 2026-08-18): рядок днів тижня
//  мусить починатися з правильного першого дня ЛОКАЛІ (укр — понеділок,
//  US — неділя). Локалі явні з обох боків — інакше на машині розробника
//  перевірялась би лише одна гілка (той самий підхід, що в ClockFormatTests).
//

import XCTest
import SwiftUI
@testable import Embar

final class CalendarPickerTests: XCTestCase {

    /// Календар локалі — так, як його бачить користувач цієї локалі
    private func calendar(_ localeID: String) -> Calendar {
        let locale = Locale(identifier: localeID)
        var cal = locale.calendar
        cal.locale = locale
        return cal
    }

    func testWeekdayRowStartsMondayForUkrainian() {
        let symbols = EmbarCalendarPicker.weekdaySymbols(calendar("uk_UA"))
        XCTAssertEqual(symbols.count, 7)
        XCTAssertEqual(symbols.first, "П", "укр тиждень починається з понеділка")
        XCTAssertEqual(symbols.last, "Н", "неділя мусить бути останньою")
    }

    func testWeekdayRowStartsSundayForUS() {
        let symbols = EmbarCalendarPicker.weekdaySymbols(calendar("en_US"))
        XCTAssertEqual(symbols.count, 7)
        XCTAssertEqual(symbols.first, "S", "US тиждень починається з неділі")
        XCTAssertEqual(symbols[1], "M", "понеділок другий")
    }

    /// 3:33 → 3:35, кратна лишається, перехід через годину працює
    func testRoundUpToStep() {
        let cal = Calendar.current
        func time(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 8, day: 18,
                                          hour: h, minute: m, second: s))!
        }
        XCTAssertEqual(EmbarTimeStepper.roundUpToStep(time(3, 33)), time(3, 35))
        XCTAssertEqual(EmbarTimeStepper.roundUpToStep(time(3, 35, 20)), time(3, 35),
                       "кратна хвилина лишається, секунди зрізаються")
        XCTAssertEqual(EmbarTimeStepper.roundUpToStep(time(3, 58)), time(4, 0),
                       "округлення перелазить через годину")
        XCTAssertEqual(EmbarTimeStepper.roundUpToStep(time(2, 56)), time(3, 0),
                       "2:56 → 3:00, а не назад до 2:00 (фідбек 2026-08-18)")
    }

    /// «Серпень 2026» / «August 2026» — з великої літери обома мовами
    func testMonthTitleCapitalized() {
        let august = Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let uk = EmbarCalendarPicker.monthTitle(august, locale: Locale(identifier: "uk_UA"))
        let us = EmbarCalendarPicker.monthTitle(august, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(uk.hasPrefix("Серпень"), uk)
        XCTAssertTrue(uk.contains("2026"), uk)
        XCTAssertTrue(us.hasPrefix("August"), us)
        XCTAssertTrue(us.contains("2026"), us)
    }

    // MARK: - Набраний повний час (ревʼю 2026-08-20)

    /// ❗ «14:45» мусить лягти ОДНИМ записом. Двома окремими (спершу
    /// година, потім хвилини) господар бачить проміжні 14:00; дедлайн
    /// відхиляє минуле, і о 14:30 при дедлайні 15:00 набране «14:45»
    /// приземлялось як 15:45
    func testWholeTimeIsWrittenOnce() {
        var hourWrites = 0, minuteWrites = 0
        var received: (hour: Int, minute: Int)?

        let stepper = EmbarTimeStepper(
            hour: Binding(get: { 15 }, set: { _ in hourWrites += 1 }),
            minute: Binding(get: { 0 }, set: { _ in minuteWrites += 1 }),
            onWholeTime: { h, m in received = (h, m) })

        stepper.applyWholeTime(hour: 14, minute: 45)

        XCTAssertEqual(received?.hour, 14)
        XCTAssertEqual(received?.minute, 45)
        XCTAssertEqual(hourWrites, 0, "проміжної години не існує")
        XCTAssertEqual(minuteWrites, 0)
    }

    /// Без господаря, який уміє прийняти час цілком, лишається старий
    /// шлях — обидва біндінги, але значення ті самі.
    ///
    /// Година 14 навмисно: у 12-годинній локалі числа 1–12 читаються в
    /// межах поточної половини доби (набрали «9» при пп → 21), і тест
    /// залежав би від машини. 14 однакове в обох форматах
    func testWholeTimeFallsBackToBothBindings() {
        var written: (hour: Int?, minute: Int?) = (nil, nil)

        let stepper = EmbarTimeStepper(
            hour: Binding(get: { 15 }, set: { written.hour = $0 }),
            minute: Binding(get: { 0 }, set: { written.minute = $0 }))

        stepper.applyWholeTime(hour: 14, minute: 7)

        XCTAssertEqual(written.hour, 14)
        XCTAssertEqual(written.minute, 7)
    }

    /// Хвилини за межами доби підрізаються, година поза діапазоном не
    /// приймається зовсім
    func testWholeTimeClampsMinutesAndRejectsBadHour() {
        var received: (Int, Int)?
        let stepper = EmbarTimeStepper(
            hour: .constant(10), minute: .constant(0),
            onWholeTime: { h, m in received = (h, m) })

        stepper.applyWholeTime(hour: 10, minute: 99)
        XCTAssertEqual(received?.1, 59)

        received = nil
        stepper.applyWholeTime(hour: 31, minute: 15)
        XCTAssertNil(received, "такої години не буває — не чіпаємо нічого")
    }
}
