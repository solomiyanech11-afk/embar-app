//
//  StickyNotify.swift
//  Embar
//
//  «Нагадати» — коли саме прийде сповіщення про дедлайн стіка.
//
//  Рішення 2026-08-19: окремого нагадування більше немає. Є дедлайн і зсув
//  до нього: у момент / за 5 хв / за 30 хв / за годину / за день. Одне
//  значення на стік; nil означає «дедлайн є, сповіщення не треба».
//

import Foundation

enum StickyNotify {
    /// Зсуви у хвилинах, у порядку показу
    static let presets = [0, 5, 30, 60, 1440]

    /// Дедлайн без сповіщення
    static var offLabel: String {
        String(localized: "Не нагадувати", comment: "Дедлайн без сповіщення")
    }

    /// Усі варіанти по порядку — від «не нагадувати» до «за день». Саме
    /// цим порядком ходить степер у редакторі стіка
    static let ordered: [Int?] = [nil] + presets.map { Optional($0) }

    /// Підписи всіх варіантів — щоб степер міг зарезервувати ширину за
    /// найдовшим і не смикатись при зміні значення (мова тут будь-яка)
    static var allLabels: [String] {
        [offLabel] + presets.map(label(for:))
    }

    /// Наступний/попередній варіант. На краях лишаємось на місці —
    /// перебір по колу плутав би: «за день» не має ставати «вимкнено».
    ///
    /// `deadline` звужує вибір: сповіщення «навздогін» не буває, тож
    /// варіанти, чий час уже минув, пропускаємо. «Сьогодні» (23:59) о
    /// десятій ранку не може бути «за день» — це вчора. Без цього степер
    /// доходив до «за день», картка малювала дзвіночок, тост обіцяв
    /// «Нагадаю ‹вчора›», а системі не ставилось нічого (ревʼю
    /// 2026-08-20). Мовчазна зупинка на межі — та сама поведінка, що вже
    /// є на краях списку
    static func step(from current: Int?, by direction: Int,
                     deadline: Date? = nil, now: Date = .now) -> Int? {
        let index = ordered.firstIndex(where: { $0 == current }) ?? 0
        var next = index
        while true {
            let candidate = next + direction
            // Доступного в цьому напрямку не лишилось — стоїмо на місці
            guard ordered.indices.contains(candidate) else { return ordered[index] }
            next = candidate
            if isReachable(ordered[next], deadline: deadline, now: now) {
                return ordered[next]
            }
        }
    }

    /// Чи цей зсув іще попереду. «Не нагадувати» доступне завжди;
    /// без дедлайну обмежувати нема від чого
    static func isReachable(_ minutes: Int?, deadline: Date?,
                            now: Date = .now) -> Bool {
        guard let minutes, let deadline else { return true }
        return triggerDate(deadline: deadline, offsetMinutes: minutes) > now
    }

    /// Найбільший зсув, що не перевищує поточний і чий час іще попереду.
    /// Потрібен, коли дедлайн переїхав ближче й наявний зсув став
    /// недосяжним («за день» при дедлайні сьогодні). nil — навіть «у
    /// момент» уже минув: сповіщення не буде, і дзвіночка теж не має бути
    static func nearestReachable(_ current: Int?, deadline: Date,
                                 now: Date = .now) -> Int? {
        guard let current else { return nil }
        return presets.last {
            $0 <= current && triggerDate(deadline: deadline, offsetMinutes: $0) > now
        }
    }

    static func label(for minutes: Int) -> String {
        switch minutes {
        case 0: String(localized: "У момент", comment: "Коли нагадати про дедлайн стіка")
        case 5: String(localized: "За 5 хв", comment: "Коли нагадати про дедлайн стіка")
        case 30: String(localized: "За 30 хв", comment: "Коли нагадати про дедлайн стіка")
        case 60: String(localized: "За годину", comment: "Коли нагадати про дедлайн стіка")
        default: String(localized: "За день", comment: "Коли нагадати про дедлайн стіка")
        }
    }

    /// Привести довільний зсув (у хвилинах) до найближчого пресету.
    /// Точний збіг лишається як є, інакше беремо найбільший пресет, що не
    /// перевищує значення — сповіщення прийде якнайближче до старого часу,
    /// але не раніше. Відʼємне (нагадування пізніше за дедлайн) → «у момент»
    static func snapDown(_ minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        return presets.last { $0 <= minutes } ?? 0
    }

    /// Коли має спрацювати сповіщення
    static func triggerDate(deadline: Date, offsetMinutes: Int) -> Date {
        deadline.addingTimeInterval(-Double(offsetMinutes) * 60)
    }
}
