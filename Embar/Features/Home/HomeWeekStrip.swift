//
//  HomeWeekStrip.swift
//  Embar
//
//  Тижнева смужка (SPEC §5.1–5.2). Ковзне вікно −3…+3: сьогодні по центру.
//  Тут — закрита смужка у футері панелі; відкритий ряд з кільцями — крок 4.
//

import SwiftUI
import SwiftData

/// Скорочення днів тижня, індекс = Calendar.weekday (1=НД…7=СБ).
///
/// i18n 2026-08-03: був прибитий український масив ["НД","ПН",…] —
/// тепер символи локалі («нд/пн» для uk, «Sun/Mon» для en). Смужка
/// ковзна (−3…+3 навколо сьогодні), тож перший день тижня тут ні на
/// що не впливає — важливі лише самі назви.
enum Weekday {
    static var short: [String] {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        let symbols = f.shortStandaloneWeekdaySymbols ?? f.shortWeekdaySymbols ?? []
        return symbols.map { $0.uppercased(with: .autoupdatingCurrent) }
    }
    static func label(_ date: Date) -> String {
        let index = Calendar.current.component(.weekday, from: date) - 1
        let symbols = short
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
    static func dayNumber(_ date: Date) -> String {
        "\(Calendar.current.component(.day, from: date))"
    }
    /// Вікно −3…+3 навколо якоря
    static func window(around anchor: Date) -> [Date] {
        let cal = Calendar.current
        return (-3...3).compactMap { cal.date(byAdding: .day, value: $0, to: anchor) }
    }
}

/// Закрита смужка у футері: тап відкриває шторку.
/// `onOpen: nil` — смужка ПАСИВНА (Home сховано з v1, HomeFeature):
/// показує тиждень, але жесту не має взагалі — жодної реакції на клік
struct HomeWeekStripClosed: View {
    let todayAnchor: Date
    var onOpen: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Weekday.window(around: todayAnchor), id: \.self) { day in
                let isToday = Calendar.current.isDate(day, inSameDayAs: todayAnchor)
                VStack(spacing: 2) {
                    Text(Weekday.label(day))
                        .font(.emUI(8.5, weight: .medium))
                        .tracking(0.85)
                        .foregroundStyle(EmbarColors.ink3)
                    Text(Weekday.dayNumber(day))
                        .font(.emUI(14, weight: isToday ? .medium : .regular).monospacedDigit())
                        .foregroundStyle(isToday ? EmbarColors.ink : EmbarColors.ink2)
                    Circle()
                        .fill(isToday ? EmbarColors.ink : .clear)
                        .frame(width: 3, height: 3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
        }
        .contentShape(Rectangle())
        .modifier(TapIfEnabled(action: onOpen))
    }
}

/// Тап лише коли дія є: пасивній смужці не вішаємо жест узагалі —
/// «мовчазний» onTapGesture усе одно їв би кліки
private struct TapIfEnabled: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.onTapGesture(perform: action)
        } else {
            content
        }
    }
}

// MARK: - Кільце дня (SPEC §5.2)

/// Кільце прогресу звичок за день. Сьогодні — accent, минулі — accent 50%,
/// майбутні — пунктир без заповнення. Вибраний (не сьогодні) — обвід ink.
struct HomeDayRing: View {
    let pct: Double
    let dayNumber: String
    let isToday: Bool
    let isFuture: Bool
    let isSelected: Bool
    let accent: Color

    private var ringColor: Color { isToday ? accent : accent.opacity(0.5) }

    var body: some View {
        ZStack {
            if isFuture {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
                    .foregroundStyle(Color.black.opacity(0.1))
            } else {
                Circle().stroke(Color.black.opacity(0.07), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: pct)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(dayNumber)
                .font(.emUI(13, weight: isToday ? .medium : .regular).monospacedDigit())
                .foregroundStyle(isToday ? EmbarColors.ink : EmbarColors.ink2)
        }
        .frame(width: 30, height: 30)
        .overlay {
            if isSelected && !isToday {
                Circle().stroke(EmbarColors.ink, lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Відкритий ряд тижня (у шторці)

struct HomeWeekRow: View {
    @ObservedObject var home: HomeModel
    let accent: Color
    @Query(sort: \Habit.createdAt) private var allHabits: [Habit]

    private var habits: [Habit] { allHabits.filter { $0.deletedAt == nil } }

    var body: some View {
        // Повернення до сьогодні — просто кліком на центральний день
        HStack(spacing: 0) {
            ForEach(Weekday.window(around: home.todayAnchor), id: \.self) { day in
                dayCell(day)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDate(day, inSameDayAs: home.todayAnchor)
        let isSelected = cal.isDate(day, inSameDayAs: home.selectedDate)
        let isFuture = day > home.todayAnchor
        return Button {
            home.selectedDate = day // вибір дня — миттєвий (§7.2-A)
        } label: {
            VStack(spacing: 5) {
                Text(Weekday.label(day))
                    .font(.emUI(9, weight: .medium)).tracking(0.9)
                    .foregroundStyle(isToday ? EmbarColors.ink : EmbarColors.ink3)
                HomeDayRing(
                    pct: HomeService.ringPct(day: day, habits: habits),
                    dayNumber: Weekday.dayNumber(day),
                    isToday: isToday, isFuture: isFuture,
                    isSelected: isSelected, accent: accent
                )
                Circle().fill(isToday ? EmbarColors.ink : .clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
