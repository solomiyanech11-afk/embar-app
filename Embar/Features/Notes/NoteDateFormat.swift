//
//  NoteDateFormat.swift
//  Embar
//
//  Відносний формат дати картки нотатки (прототип `noteRelativeDate`):
//  «щойно» / «N хв тому» / «сьогодні, HH:MM» / «вчора» / «N дн. тому» / «5 трав».
//
//  i18n 2026-08-03: локаль більше не прибита до uk_UA — беремо мову
//  системи. «N хв/дн. тому» — не склейка числа зі словом, а ключ із
//  множинами: в українській три форми (хвилина/хвилини/хвилин),
//  в англійській дві.
//

import Foundation

enum NoteDateFormat {
    static func relative(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        let seconds = now.timeIntervalSince(date)

        if seconds < 60 {
            return String(localized: "щойно",
                          comment: "Мета-рядок нотатки: змінено щойно")
        }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return String(localized: "\(minutes) хв тому",
                          comment: "Мета-рядок нотатки: скільки хвилин тому змінено")
        }

        if cal.isDate(date, inSameDayAs: now) {
            // Спільний годинник — 12/24 за налаштуванням системи
            return String(localized: "сьогодні, \(ReaderDateFormat.time(date))",
                          comment: "Мета-рядок нотатки: сьогодні о вказаній годині")
        }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
           cal.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "вчора",
                          comment: "Мета-рядок нотатки: змінено вчора")
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        if days < 7 {
            return String(localized: "\(days) дн. тому",
                          comment: "Мета-рядок нотатки: скільки днів тому змінено")
        }

        // Спільний форматер — «13 лип» / «Jul 13», уже без крапки
        return ReaderDateFormat.dayMonth(date)
    }

    /// Мітка провенансу для картки/мета-рядка
    static func provenance(_ bornType: String?) -> String? {
        switch bornType {
        case "sticky":
            String(localized: "зі стікера",
                   comment: "Звідки взялась нотатка — мета-рядок картки")
        case "reader":
            String(localized: "з читання",
                   comment: "Звідки взялась нотатка — мета-рядок картки")
        default:
            nil
        }
    }
}
