//
//  HomeService.swift
//  Embar
//
//  Дата-операції Home (SPEC §5, §11.9–11.12). Чисті функції над ModelContext;
//  тости/undo — у View. Звички derived від `completions` (без «скиду»).
//

import Foundation
import SwiftData

// MARK: - Вбудовані теги (теки каруселі)

enum HomeTags {
    static let family = "сім'я"
    static let work = "робота"
    static let home = "дім"
    /// Порядок тек після «Всі» (як folderDefs прототипу)
    static let builtinOrder = [family, work, home]

    /// Індекс кольору тега в палітру. Вбудовані — фіксовані слоти;
    /// кастомні — стабільний слот від назви.
    static func colorIndex(for tagName: String) -> Int {
        switch tagName {
        case work: return 1    // sticky-2 (blue)
        case home: return 2    // sticky-3 (green)
        case family: return 3  // sticky-4 (pink)
        default:
            let sum = tagName.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
            return abs(sum) % 5
        }
    }

    static func isBuiltin(_ name: String) -> Bool { builtinOrder.contains(name) }
}

enum HomeService {

    // MARK: - Дні (чисті, nonisolated — лише Calendar)

    nonisolated static func startOfDay(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }

    /// Wall-clock година дня (0…24) для таймлайну. Через компоненти
    /// календаря, НЕ interval/3600: у дні переведення годинника доба має
    /// 23/25 год, і інтервальна математика розходилась із підписами сітки
    /// на 1 годину (code review 2026-07-04).
    /// ❗ Для КІНЦЯ події не годиться: 24:00 = північ наступного дня → 0.
    /// Для подій — eventHours
    nonisolated static func hourOfDay(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    /// Години події відносно ЇЇ власного дня (якір — день startDate):
    /// кінець рівно о 24:00 коректно дає 24, а не 0 (code review 2026-07-04)
    nonisolated static func eventHours(_ event: Event) -> (start: Double, end: Double) {
        let anchorDay = startOfDay(event.startDate ?? .now)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: anchorDay) ?? anchorDay
        func hour(_ d: Date) -> Double {
            if d >= nextDay { return 24 }
            if d < anchorDay { return 0 }
            return hourOfDay(d)
        }
        return (hour(event.startDate ?? anchorDay), hour(event.endDate ?? anchorDay))
    }

    /// Дата на конкретний день і wall-clock годину-float. bySettingHour
    /// коректно оминає неіснуючу годину весняного переведення
    nonisolated static func date(day: Date, hour: Double) -> Date {
        let start = startOfDay(day)
        if hour >= 24 {
            return Calendar.current.date(byAdding: .day, value: 1, to: start)
                ?? start.addingTimeInterval(24 * 3600)
        }
        let h = Int(hour)
        let m = Int(((hour - Double(h)) * 60).rounded())
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: start)
            ?? start.addingTimeInterval(hour * 3600)
    }

    // MARK: - Звички

    static func isDone(_ habit: Habit, on day: Date) -> Bool {
        let d = startOfDay(day)
        return habit.completions.contains { startOfDay($0) == d }
    }

    static func toggleDone(_ habit: Habit, on day: Date) {
        let d = startOfDay(day)
        if let idx = habit.completions.firstIndex(where: { startOfDay($0) == d }) {
            habit.completions.remove(at: idx)
        } else {
            habit.completions.append(d)
        }
        habit.updatedAt = .now
    }

    /// Стрік = послідовні дні до сьогодні (або вчора, якщо сьогодні ще не done)
    static func streak(_ habit: Habit, today: Date = .now) -> Int {
        let cal = Calendar.current
        let days = Set(habit.completions.map { startOfDay($0) })
        var cursor = startOfDay(today)
        if !days.contains(cursor) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    /// Кільце дня: частка звичок, виконаних у день D (SPEC §5.2)
    static func ringPct(day: Date, habits: [Habit]) -> Double {
        let active = habits.filter { $0.deletedAt == nil }
        guard !active.isEmpty else { return 0 }
        let done = active.filter { isDone($0, on: day) }.count
        return Double(done) / Double(active.count)
    }

    @discardableResult
    static func addHabit(_ text: String, in context: ModelContext) -> Habit? {
        // Home вимкнено (HomeFeature.enabled=false), але гейт режиму
        // читання стоїть уже зараз - щоб увімкнення Home його не забуло.
        // Тихий (без тосту): UI-точки Home підключать ProGate самі
        guard EntitlementStore.shared.canCreate else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let habit = Habit(text: t)
        context.insert(habit)
        return habit
    }

    static func softDelete(_ habit: Habit) { habit.deletedAt = .now; habit.updatedAt = .now }
    static func undoDelete(_ habit: Habit) { habit.deletedAt = nil; habit.updatedAt = .now }

    // MARK: - Тудушки

    @discardableResult
    static func addTodo(_ text: String, tag: String?, in context: ModelContext) -> Todo? {
        guard EntitlementStore.shared.canCreate else { return nil } // як addHabit
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let todo = Todo(text: t, tagName: tag)
        context.insert(todo)
        return todo
    }

    static func toggleDone(_ todo: Todo) {
        todo.done.toggle()
        todo.completedAt = todo.done ? .now : nil
        todo.updatedAt = .now
    }

    static func softDelete(_ todo: Todo) { todo.deletedAt = .now; todo.updatedAt = .now }
    static func undoDelete(_ todo: Todo) { todo.deletedAt = nil; todo.updatedAt = .now }

    // MARK: - Кастомні теги

    @discardableResult
    static func createCustomTag(_ name: String, existing: [HomeTag], in context: ModelContext) -> HomeTag? {
        guard EntitlementStore.shared.canCreate else { return nil } // як addHabit
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !existing.contains(where: { $0.name == n }) else { return nil }
        let tag = HomeTag(name: n)
        context.insert(tag)
        return tag
    }

    // MARK: - Події
    // Колір нової події — рандомний з палітри на кожну спробу
    // (генерується у точці створення: кнопка/drag), не ротація

    /// Створити подію на день `day` (start/end — години-float). Валідація end>start.
    @discardableResult
    static func addEvent(label: String, day: Date, startHour: Double, endHour: Double,
                         colorIndex: Int, in context: ModelContext) -> Event? {
        guard EntitlementStore.shared.canCreate else { return nil } // як addHabit
        guard endHour > startHour else { return nil }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = Event(label: name.isEmpty ? String(localized: "Подія", comment: "Назва події за замовчуванням у таймлайні Home") : name,
                          startDate: date(day: day, hour: startHour),
                          endDate: date(day: day, hour: endHour))
        event.colorIndex = colorIndex
        context.insert(event)
        return event
    }

    static func softDelete(_ event: Event) { event.deletedAt = .now; event.updatedAt = .now }
    static func undoDelete(_ event: Event) { event.deletedAt = nil; event.updatedAt = .now }

    /// Події конкретного дня, відсортовані (start, потім end)
    static func events(on day: Date, from all: [Event]) -> [Event] {
        let d = startOfDay(day)
        return all
            .filter { $0.deletedAt == nil && ($0.startDate.map(startOfDay) == d) }
            .sorted {
                let s0 = $0.startDate ?? .distantPast, s1 = $1.startDate ?? .distantPast
                if s0 != s1 { return s0 < s1 }
                return ($0.endDate ?? .distantPast) < ($1.endDate ?? .distantPast)
            }
    }
}
