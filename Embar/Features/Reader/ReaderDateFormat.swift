//
//  ReaderDateFormat.swift
//  Embar
//
//  Час і дата-роздільники стрічки рідера (SPEC §4.3; прототип
//  fmtTimeReader/dayLabelReader). Назви місяців спільні з пошуком
//  за датою (крок 8) — єдине джерело правди для «5 лип».
//
//  i18n 2026-08-03: назви місяців більше не таблиця українських рядків,
//  а символи локалі; «13 лип» збирається форматером за шаблоном dMMM,
//  бо в англійській порядок інший — «Jul 13», а не «13 Jul».
//

import Foundation

enum ReaderDateFormat {

    /// Скорочені назви місяців мовою інтерфейсу — індекс 0 = січень.
    /// Потрібні пошуку за датою, щоб розпізнати набране «5 лип» / «5 jul».
    static var monthsShort: [String] {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        return f.shortStandaloneMonthSymbols ?? f.shortMonthSymbols ?? []
    }

    /// «13 лип» (uk) · «Jul 13» (en) — день і скорочений місяць
    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }()

    /// «14:05» / «2:05 PM» — час запису в лівій колонці.
    ///
    /// 12 чи 24 години вирішує НЕ застосунок, а перемикач «24-Hour Time»
    /// у системних налаштуваннях: `timeStyle = .short` його поважає
    /// (i18n 2026-08-07 — раніше було прибито `%02d:%02d`).
    /// Українською вигляд не змінився: локаль так само дає «09:30».
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static func time(_ date: Date) -> String {
        clock.string(from: date)
    }

    /// Чи показує система 12-годинний час (у форматі є AM/PM).
    /// Локаль параметром — щоб тести могли перевірити ОБИДВІ гілки,
    /// а не лише ту, на якій стоїть машина розробника
    static func uses12HourClock(_ locale: Locale = .autoupdatingCurrent) -> Bool {
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0,
                                  locale: locale) ?? "").contains("a")
    }

    /// Ширина колонки часу у стрічці записів.
    ///
    /// Прототип малює 32pt під «14:05». У 12-годинному форматі рядок
    /// довший — «9:26 AM», — і в тій самій колонці він ломався на два
    /// рядки: «9:26 A» / «M» (баг 2026-08-09). Українською вигляд
    /// лишається точно як був
    static func timeColumnWidth(_ locale: Locale = .autoupdatingCurrent) -> CGFloat {
        uses12HourClock(locale) ? 50 : 32
    }

    /// Підпис години на осі таймлайну Home: «14:00» при 24-годинному
    /// форматі, «2 PM» при 12-годинному (як у Календарі — там година з
    /// AM/PM самодостатня, а «:00» лише зашумило б вісь).
    static func hourLabel(_ hour: Int, locale: Locale = .autoupdatingCurrent) -> String {
        guard uses12HourClock(locale) else {
            // 24-годинний вигляд лишаємо точно як був, разом із «24:00»
            // на кінцевій зарубці доби
            return "\(hour):00"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("j")
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        // Година 24 — кінець доби; показуємо її як опівніч
        let date = cal.date(byAdding: .hour, value: hour % 24, to: start) ?? start
        return formatter.string(from: date)
    }

    /// «13 лип» / «Jul 13».
    /// Крапку скорочення прибираємо: локаль дає українською «13 лип.», а в
    /// застосунку скрізь без крапки (так було до i18n і так у прототипі).
    /// Безпечно для обох мов, які ми шлемо: en взагалі без крапок.
    static func dayMonth(_ date: Date) -> String {
        dayMonth.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    /// «сьогодні» / «вчора» / «5 лип» — лейбл дата-роздільника
    static func dayLabel(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) {
            return String(localized: "сьогодні",
                          comment: "Дата-роздільник у стрічці рідера")
        }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
           cal.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "вчора",
                          comment: "Дата-роздільник у стрічці рідера")
        }
        return dayMonth(date)
    }
}
