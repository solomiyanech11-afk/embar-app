//
//  ReaderDateQuery.swift
//  Embar
//
//  Пошук за датою в блокноті (#6, міні-дизайн M5): якщо запит схожий
//  на дату — фільтруємо записи за тим днем, інакше звичайний пошук.
//  Формати: «сьогодні» · «вчора» · «5 лип» (назви місяців спільні
//  з дата-роздільниками, ReaderDateFormat) · «05.07» · «05.07.2026».
//
//  i18n 2026-08-03:
//  · «сьогодні»/«вчора» звіряються з перекладеними словами — користувач
//    набирає те, що бачить у роздільнику стрічки (todayWord/yesterdayWord);
//  · назви місяців беруться з локалі, крапка й регістр ігноруються
//    («5 лип», «5 лип.», «5 Jul»);
//  · порядок чисел у «05.07» читається з локалі: uk — день.місяць,
//    en(US) — місяць/день. Роздільник — крапка, слеш або дефіс.
//

import Foundation

enum ReaderDateQuery {

    /// Слово-запит «сьогодні» мовою інтерфейсу (те саме, що в роздільнику)
    static var todayWord: String {
        String(localized: "сьогодні", comment: "Дата-роздільник у стрічці рідера")
    }
    /// Слово-запит «вчора» мовою інтерфейсу
    static var yesterdayWord: String {
        String(localized: "вчора", comment: "Дата-роздільник у стрічці рідера")
    }

    /// Розпізнати запит-дату → інтервал доби; nil = це не дата
    static func dayInterval(from raw: String, now: Date = .now,
                            calendar: Calendar = .current,
                            locale: Locale = .autoupdatingCurrent) -> DateInterval? {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: locale)
        guard !query.isEmpty else { return nil }

        if query == todayWord.lowercased(with: locale) { return day(of: now, calendar) }
        if query == yesterdayWord.lowercased(with: locale) {
            guard let date = calendar.date(byAdding: .day, value: -1, to: now)
            else { return nil }
            return day(of: date, calendar)
        }

        // «05.07» / «5/7» / «05-07-2026»
        if let match = numeric.firstMatch(
            in: query, range: NSRange(query.startIndex..., in: query)) {
            let ns = query as NSString
            let first = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let second = Int(ns.substring(with: match.range(at: 2))) ?? 0
            let year = match.range(at: 3).location == NSNotFound
                ? calendar.component(.year, from: now)
                : Int(ns.substring(with: match.range(at: 3))) ?? 0
            // Хто перший — день чи місяць — вирішує формат локалі
            let (dayNum, month) = monthComesFirst(in: locale)
                ? (second, first) : (first, second)
            return day(year: year, month: month, dayNum: dayNum, calendar)
        }

        // «5 лип» — як у дата-роздільниках
        let parts = query.split(separator: " ")
        if parts.count == 2, let dayNum = Int(parts[0]) {
            let typed = normalizeMonth(String(parts[1]), locale)
            if let index = ReaderDateFormat.monthsShort
                .firstIndex(where: { normalizeMonth($0, locale) == typed }) {
                return day(year: calendar.component(.year, from: now),
                           month: index + 1, dayNum: dayNum, calendar)
            }
        }

        return nil
    }

    // «дд.мм», «дд/мм», «дд-мм» (+ необовʼязковий рік) — цілим рядком
    private static let numeric = try! NSRegularExpression(
        pattern: "^(\\d{1,2})[./-](\\d{1,2})(?:[./-](\\d{4}))?$")

    /// Скорочення місяця без крапки й регістру: «Лип.» == «лип»
    private static func normalizeMonth(_ raw: String, _ locale: Locale) -> String {
        raw.lowercased(with: locale)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    /// Чи йде місяць перед днем у короткому форматі цієї локалі (en_US — так)
    private static func monthComesFirst(in locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0,
                                              locale: locale) ?? "d.M.y"
        guard let monthIndex = format.firstIndex(of: "M"),
              let dayIndex = format.firstIndex(of: "d") else { return false }
        return monthIndex < dayIndex
    }

    private static func day(of date: Date, _ calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, duration: 86400)
    }

    private static func day(year: Int, month: Int, dayNum: Int,
                            _ calendar: Calendar) -> DateInterval? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayNum
        // Неіснуючі дати (32.13) відкидаємо — це не дата, шукаємо як текст
        guard components.isValidDate(in: calendar),
              let date = calendar.date(from: components) else { return nil }
        return day(of: date, calendar)
    }
}
