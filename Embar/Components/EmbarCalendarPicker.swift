//
//  EmbarCalendarPicker.swift
//  Embar
//
//  Власний вибір дати й часу (редизайн 2026-08-18) — замість системного
//  DatePicker зі степером. Один компонент для всіх місць, де обирається
//  дата: дедлайн стіка, нагадування, події Home (там — лише EmbarTimeStepper).
//
//  Календар: шапка місяця з ‹ ›, локалізований рядок днів тижня з правильним
//  першим днем (укр — понеділок, US — неділя), сітка без днів сусідніх
//  місяців; вибране число — чорне коло з білим текстом, сьогодні — тонке
//  обведення, минулі дні приглушені й невибірні.
//
//  Час: степери − / + для годин і хвилин; сегмент AM/PM існує ТІЛЬКИ в
//  12-годинній локалі (рішення як для решти часу: формат вирішує система,
//  ReaderDateFormat.uses12HourClock). У 24-годинній — години 0–23 без сегмента.
//
//  Клавіатура: стрілки ходять по днях (±1 / ±7), Enter підтверджує (onCommit).
//

import SwiftUI

struct EmbarCalendarPicker: View {
    @Binding var date: Date
    /// Крок хвилинного степера: 5 хв для дедлайнів/нагадувань
    var minuteStep: Int = 5
    /// Чорнила кольорової поверхні (стік, SPEC §15.57); nil = панельні
    var inks: StickyInk.Tokens? = nil
    /// Enter у сфокусованому календарі (закрити острівець тощо)
    var onCommit: () -> Void = {}

    // Панельні фолбеки — календар уміє жити і на білому
    private var cInk: Color { inks?.ink ?? EmbarColors.ink }
    private var cInk2: Color { inks?.ink2 ?? EmbarColors.ink2 }
    private var cInk3: Color { inks?.ink3 ?? EmbarColors.ink3 }

    /// Перше число місяця, який зараз видно (гортається незалежно від вибору)
    @State private var shownMonth: Date = .now
    /// Повний місяць розкрито вручну (фідбек 2026-08-18: за замовчуванням —
    /// компактний тиждень, календар на весь місяць — за окремою кнопкою)
    @State private var expanded = false
    @FocusState private var focused: Bool

    private var cal: Calendar { Calendar.autoupdatingCurrent }

    var body: some View {
        VStack(spacing: 6) {
            if showsMonth {
                monthHeader
                weekdayRow
                dayGrid
            } else {
                weekRow
            }
            HStack(spacing: 6) {
                EmbarTimeStepper(hour: hourBinding, minute: minuteBinding,
                                 minuteStep: minuteStep, inks: inks,
                                 onEditSubmit: onCommit,
                                 // Набраний час лягає в дату ОДНИМ записом:
                                 // господар (дедлайн) відхиляє минуле, і
                                 // проміжна година зʼїдала половину набраного
                                 onWholeTime: { h, m in setTime(hour: h, minute: m) })
                Spacer(minLength: 4)
                expandButton
            }
            .padding(.top, 4)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.leftArrow) { shiftDay(-1); return .handled }
        .onKeyPress(.rightArrow) { shiftDay(1); return .handled }
        .onKeyPress(.upArrow) { shiftDay(-7); return .handled }
        .onKeyPress(.downArrow) { shiftDay(7); return .handled }
        .onKeyPress(.return) { onCommit(); return .handled }
        .onAppear {
            shownMonth = startOfMonth(date)
            focused = true
        }
        .onChange(of: date) { _, new in shownMonth = startOfMonth(new) }
    }

    // MARK: - Компактний тиждень (вигляд за замовчуванням)

    /// Сьогодні + шість наступних днів
    private var weekDays: [Date] {
        let today = cal.startOfDay(for: .now)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    private var selectionInWeek: Bool {
        weekDays.contains { cal.isDate($0, inSameDayAs: date) }
    }

    /// Місяць показуємо, якщо розкрили вручну АБО вибір поза найближчим
    /// тижнем (компактний ряд його просто не має де показати)
    private var showsMonth: Bool { expanded || !selectionInWeek }

    /// «ЧТ ПТ СБ …» над числами — сьогодні і далі, без гортання
    private var weekRow: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                VStack(spacing: 3) {
                    Text(weekdayShort(day))
                        .font(.emUI(8.5, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(cInk3)
                    dayCell(day)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// «ЧТ» / «THU» — скорочена назва дня конкретної дати
    private func weekdayShort(_ day: Date) -> String {
        let symbols = cal.shortStandaloneWeekdaySymbols
        let index = cal.component(.weekday, from: day) - 1
        let locale = cal.locale ?? .autoupdatingCurrent
        return symbols[index].uppercased(with: locale)
    }

    /// Компактний ↔ повний: календарик відкриває місяць, шеврон згортає.
    /// Згортати нема куди, коли вибір поза найближчим тижнем — кнопки нема
    @ViewBuilder private var expandButton: some View {
        // Розкриття анімуємо явно: разом із календарем плавно їде і все,
        // що від його висоти залежить (у стіку — сам тулбар і підйом
        // картки). Крива — та сама, що в морфі тулбара
        if !showsMonth {
            monthArrow("calendar") { withAnimation(Self.expandAnimation) { expanded = true } }
        } else if selectionInWeek {
            monthArrow("chevron.up") { withAnimation(Self.expandAnimation) { expanded = false } }
        }
    }

    static let expandAnimation = Animation.easeOut(duration: 0.2)

    // MARK: - Шапка місяця

    private var monthHeader: some View {
        HStack {
            monthArrow("chevron.left") { shiftMonth(-1) }
            Spacer()
            Text(Self.monthTitle(shownMonth))
                .font(.emUI(13, weight: .semibold))
                .foregroundStyle(cInk)
            Spacer()
            monthArrow("chevron.right") { shiftMonth(1) }
        }
    }

    private func monthArrow(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(cInk2)
                .frame(width: 22, height: 22)
                .background(Circle().fill(inks?.buttonBg ?? Color.black.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverDarken(Circle())
    }

    /// «Серпень 2026» / «August 2026» — standalone-назва місяця, з великої
    static func monthTitle(_ month: Date,
                           locale: Locale = .autoupdatingCurrent) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        let s = f.string(from: month)
        return s.prefix(1).uppercased(with: locale) + s.dropFirst()
    }

    // MARK: - Дні тижня

    /// Однобуквені символи, повернуті так, щоб перший = firstWeekday локалі
    /// (укр — понеділок, US — неділя). Локаль параметром — для тестів
    static func weekdaySymbols(_ calendar: Calendar = .autoupdatingCurrent) -> [String] {
        var c = calendar
        c.locale = calendar.locale ?? .autoupdatingCurrent
        let symbols = c.veryShortStandaloneWeekdaySymbols // індекс 0 = неділя
        let first = c.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.weekdaySymbols(cal).enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(.emUI(9.5, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(cInk3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Сітка чисел

    /// Дні видимого місяця + провідні nil-и, щоб 1-ше стало у свою колонку.
    /// Дні сусідніх місяців не показуємо (порожні клітинки)
    private var gridDays: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: shownMonth)
        else { return [] }
        let first = startOfMonth(shownMonth)
        let weekday = cal.component(.weekday, from: first) // 1 = неділя
        let lead = (weekday - cal.firstWeekday + 7) % 7
        let days: [Date?] = range.compactMap {
            cal.date(byAdding: .day, value: $0 - 1, to: first)
        }
        return Array(repeating: nil, count: lead) + days
    }

    private var dayGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0),
                                 count: 7), spacing: 2) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 24)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = cal.isDate(day, inSameDayAs: date)
        let today = cal.isDateInToday(day)
        let past = day < cal.startOfDay(for: .now)
        return Button {
            pick(day)
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.emUI(11, weight: selected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(selected ? .white : cInk)
                .frame(width: 24, height: 24)
                .background {
                    if selected {
                        // Вибране коло лишається чорним завжди — це той
                        // самий ідіом, що чорна пігулка сегмента
                        Circle().fill(EmbarColors.ink)
                    } else if today {
                        Circle().stroke(cInk2, lineWidth: 1)
                    }
                }
                .hoverDarken(Circle(), strength: past || selected ? 0 : 0.07)
                .opacity(past ? 0.3 : 1)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(past)
    }

    // MARK: - Логіка

    private func startOfMonth(_ d: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
    }

    /// Нове число, той самий час (год/хв беремо з поточного вибору)
    private func pick(_ day: Date) {
        let time = cal.dateComponents([.hour, .minute], from: date)
        date = cal.date(bySettingHour: time.hour ?? 0,
                        minute: time.minute ?? 0,
                        second: 0, of: day) ?? day
    }

    private func shiftDay(_ delta: Int) {
        guard let new = cal.date(byAdding: .day, value: delta, to: date),
              new >= cal.startOfDay(for: .now) else { return }
        date = new
    }

    private func shiftMonth(_ delta: Int) {
        shownMonth = cal.date(byAdding: .month, value: delta, to: shownMonth)
            ?? shownMonth
    }

    private var hourBinding: Binding<Int> {
        Binding(get: { cal.component(.hour, from: date) },
                set: { h in
            date = cal.date(bySettingHour: h,
                            minute: cal.component(.minute, from: date),
                            second: 0, of: date) ?? date
        })
    }

    private var minuteBinding: Binding<Int> {
        Binding(get: { cal.component(.minute, from: date) },
                set: { m in
            date = cal.date(bySettingHour: cal.component(.hour, from: date),
                            minute: m, second: 0, of: date) ?? date
        })
    }

    /// Година й хвилини разом — один запис у дату (див. `onWholeTime`)
    private func setTime(hour: Int, minute: Int) {
        date = cal.date(bySettingHour: hour, minute: minute,
                        second: 0, of: date) ?? date
    }
}

// MARK: - Степер часу (спільний: календар і події Home)

/// «− 6 + : − 00 + [AM][PM]». Години/хвилини як Int — щоб і Date-місця
/// (дедлайн, нагадування), і події Home (Double-години) користувались одним
/// компонентом. AM/PM лише в 12-годинній локалі (ReaderDateFormat).
struct EmbarTimeStepper: View {
    @Binding var hour: Int   // 0–23 (або 24, якщо hourRange дозволяє)
    @Binding var minute: Int
    var minuteStep: Int = 5
    /// Події Home мають кінець «24:00»; для звичайних дат — 0...23
    var hourRange: ClosedRange<Int> = 0...23
    /// Чорнила кольорової поверхні (стік, SPEC §15.57); nil = панельні
    var inks: StickyInk.Tokens? = nil
    /// Enter у полі вводу: значення вже закомічено, господар може закрити
    /// острівець (фідбек 2026-08-18: Enter закривав ВЕСЬ стік)
    var onEditSubmit: () -> Void = {}
    /// Набраний повний час («2:23») одним записом.
    ///
    /// ❗ Господар, який ПЕРЕВІРЯЄ значення (дедлайн не приймає минулого),
    /// зобовʼязаний це передати. Дві окремі зміни — година, потім
    /// хвилини — дають проміжний час, якого людина не набирала: о 14:30
    /// при дедлайні 15:00 ввід «14:45» спершу пробує 14:00, той летить у
    /// минуле і відхиляється, а далі лягають самі хвилини — виходить
    /// 15:45 (ревʼю 2026-08-20). nil = біндінги пишуться по черзі, як
    /// раніше
    var onWholeTime: ((Int, Int) -> Void)? = nil

    /// Клік по числу відкриває ввід із клавіатури (фідбек 2026-08-18:
    /// не клацати «+» до конкретної хвилини)
    enum Field { case hour, minute }
    @State private var editing: Field?
    @State private var editText = ""
    @FocusState private var editFocus: Field?

    private var twelveHour: Bool { ReaderDateFormat.uses12HourClock() }

    var body: some View {
        HStack(spacing: 6) {
            stepperPill(.hour, value: hourLabel,
                        minus: { stepHour(-1) }, plus: { stepHour(1) })
            Text(":")
                .font(.emUI(12, weight: .medium))
                .foregroundStyle(inks?.ink3 ?? EmbarColors.ink3)
            // Сегмент одразу після хвилин, не біля правого краю
            // (фідбек 2026-08-18)
            stepperPill(.minute, value: String(format: "%02d", displayMinute),
                        minus: { stepMinute(-1) }, plus: { stepMinute(1) })
            if twelveHour {
                amPmSegment
            }
        }
        // Фокус пішов деінде (клік повз, Tab) — комітимо, що встигли набрати
        .onChange(of: editFocus) { _, focus in
            if let field = editing, focus != field { commitEdit(field) }
        }
        // ❗ Степер зникає (галочка, згортання морфа) з недокоміченим
        // текстом — без цього господар встигав застосувати округлений
        // ДЕФОЛТ замість набраного: «вписала 2:23, зберегло 2:25»
        // (фідбек 2026-08-20). Коміт із onDisappear досі пише в живі
        // біндінги — останнє слово за набраним
        .onDisappear {
            if let field = editing { commitEdit(field) }
        }
    }

    /// Найближча МАЙБУТНЯ хвилина, кратна кроку: 3:33 → 3:35 (щоб степер
    /// не ходив по 33/38/43). Дефолт для «зараз» у дедлайні/нагадуванні
    static func roundUpToStep(_ date: Date, step: Int = 5) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute],
                                       from: date)
        let truncated = cal.date(from: comps) ?? date
        let rem = (comps.minute ?? 0) % step
        guard rem != 0 else { return truncated }
        return cal.date(byAdding: .minute, value: step - rem, to: truncated)
            ?? truncated
    }

    // MARK: Пігулка «− значення +»

    private func stepperPill(_ field: Field, value: String,
                             minus: @escaping () -> Void,
                             plus: @escaping () -> Void) -> some View {
        EmbarStepper(inks: inks, onMinus: minus, onPlus: plus) {
            if editing == field {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.emUI(11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(inks?.ink ?? EmbarColors.ink)
                    .multilineTextAlignment(.center)
                    .frame(width: 24)
                    .focused($editFocus, equals: field)
                    // Enter споживаємо ТУТ (.handled), інакше він долітав
                    // до onKeyPress редактора стіка і закривав його весь
                    .onKeyPress(.return) {
                        commitEdit(field); onEditSubmit(); return .handled
                    }
                    .onSubmit { commitEdit(field); onEditSubmit() }
                    .submitScope() // сабміт не спливає до полів господаря
                    .onExitCommand { editing = nil }
            } else {
                Text(value)
                    .font(.emUI(11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(inks?.ink ?? EmbarColors.ink)
                    .frame(minWidth: 24)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEdit(field) }
            }
        }
    }

    // MARK: AM/PM

    /// Символи з локалі (не свої рядки) — «дп/пп», «AM/PM» тощо
    private static var amPm: (am: String, pm: String) {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        return (f.amSymbol ?? "AM", f.pmSymbol ?? "PM")
    }

    /// Той самий сегмент, що «Архівувати через» (фідбек 2026-08-18):
    /// тонований контейнер і чорна пігулка, що їде між дп і пп.
    /// .mini — в один зріст із пігулками степера (23pt)
    private var amPmSegment: some View {
        let symbols = Self.amPm
        return EmbarSegment(
            options: [.init(id: false, label: symbols.am),
                      .init(id: true, label: symbols.pm)],
            selection: hour % 24 >= 12,
            style: .tinted, size: .mini, fillWidth: false, inks: inks
        ) { setPM($0) }
    }

    // MARK: Логіка

    /// 24-годинна локаль: 0–23 (і 24 на кінці доби подій).
    /// 12-годинна: 12, 1…11; «24» показуємо як 12 (AM, опівніч кінця доби)
    private var hourLabel: String {
        guard twelveHour else { return "\(hour)" }
        let h = hour % 12
        return "\(h == 0 ? 12 : h)"
    }

    /// Година 24 (кінець доби подій) — хвилин уже нема, тримаємо 00
    private var displayMinute: Int { hour == 24 ? 0 : minute }

    private func stepHour(_ delta: Int) {
        let new = hour + delta
        guard hourRange.contains(new) else { return }
        hour = new
        if hour == 24 { minute = 0 }
    }

    private func stepMinute(_ delta: Int) {
        guard hour != 24 else { // з 24:00 можна тільки назад — на 23:xx
            if delta < 0 { hour = 23; minute = 60 - minuteStep }
            return
        }
        // Некратне значення (набране руками або «зараз» зі старих даних)
        // спершу вирівнюємо до кратного В НАПРЯМКУ кроку: 33 «+» → 35,
        // 33 «−» → 30 — степер не ходить по 33/38/43 (фідбек 2026-08-18)
        var new: Int
        if minute % minuteStep == 0 {
            new = minute + delta * minuteStep
        } else if delta > 0 {
            new = (minute / minuteStep + 1) * minuteStep
        } else {
            new = minute / minuteStep * minuteStep
        }
        if new >= 60 { new = 0 } else if new < 0 { new = 60 - minuteStep }
        minute = new
    }

    // MARK: Ввід із клавіатури

    private func beginEdit(_ field: Field) {
        // ❗ Перехід година → хвилини (клік по сусідній пігулці) не жене
        // фокус через onChange до того, як ми перепишемо editing, — без
        // явного коміту набране в першому полі мовчки губилось, і «ввід
        // працює через раз» (фідбек 2026-08-20)
        if let current = editing, current != field { commitEdit(current) }
        editText = ""
        editing = field
        editFocus = field
    }

    /// Набране число в години/хвилини; порожнє чи не число — без змін.
    /// Точність не обрізаємо до кроку: людина набирає САМЕ 3:37.
    /// «2:23» із двокрапкою в будь-якому полі — це одразу і година, і
    /// хвилини (фідбек 2026-08-20: людина думає про час, не про пігулки)
    private func commitEdit(_ field: Field) {
        defer { editing = nil }
        let raw = editText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }

        // Повний час одним рядком: «2:23», «14.05», «2 23»
        let parts = raw.split(whereSeparator: { ":.,; ".contains($0) })
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
            applyWholeTime(hour: h, minute: m)
            return
        }

        guard let value = Int(raw) else { return }
        switch field {
        case .minute:
            guard hour != 24 else { return } // 24:00 — хвилин уже нема
            minute = min(max(value, 0), 59)
        case .hour:
            applyHour(value)
        }
    }

    /// «2:23» — це ОДИН час, а не дві окремі зміни (див. `onWholeTime`).
    /// Не private: саме цей шлях перевіряється тестом напряму — «скільки
    /// разів торкнулись біндінгів» інакше не побачити
    func applyWholeTime(hour h: Int, minute m: Int) {
        guard let resolved = resolvedHour(h) else { return }
        let clamped = resolved == 24 ? 0 : min(max(m, 0), 59)
        if let onWholeTime {
            onWholeTime(resolved, clamped)
        } else {
            hour = resolved
            minute = clamped
        }
    }

    /// Набране число → година доби, або nil, якщо такої не приймаємо.
    /// Чиста функція: нею користуються і покроковий ввід, і повний час
    func resolvedHour(_ value: Int) -> Int? {
        if twelveHour, (1...12).contains(value) {
            // 12-годинний ввід у межах поточної половини доби:
            // набрали «3» при пп → 15; «12» — це 12 дня або 0 ночі
            let base = (hour % 24 >= 12) ? 12 : 0
            return base + value % 12
        }
        // Повна година (у 12-год теж можна набрати «14»)
        return hourRange.contains(value) ? value : nil
    }

    private func applyHour(_ value: Int) {
        guard let resolved = resolvedHour(value) else { return }
        hour = resolved
        if resolved == 24 { minute = 0 }
    }

    private func setPM(_ pm: Bool) {
        let h = hour % 24
        if pm, h < 12 { hour = h + 12 }
        if !pm, h >= 12 { hour = h - 12 }
    }
}
