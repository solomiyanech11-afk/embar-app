//
//  HomeEventModal.swift
//  Embar
//
//  Модал події (SPEC §5.3). Sticky-стиль: картка тонується в колір події.
//  Час — 30-хв кроки, свотчі палітри, валідація end>start. Read-only режим
//  для минулих днів (SPEC §5.2).
//

import SwiftUI

struct HomeEventModal: View {
    enum Mode {
        case new(start: Double, end: Double, color: Int)
        case edit(Event)
        case view(Event) // read-only (минулий день)
    }

    let mode: Mode
    let palette: Palette
    var onSave: (_ label: String, _ notes: String, _ start: Double, _ end: Double, _ colorIndex: Int) -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    @State private var label = ""
    @State private var notes = ""
    @State private var startHour = 9.0
    @State private var endHour = 10.0
    @State private var colorIndex = 0
    @State private var showError = false
    @State private var colorPanelOpen = false
    enum TimeEdge { case start, end }
    @State private var openStepper: TimeEdge?
    @FocusState private var titleFocus: Bool

    private let ink = Color.black.opacity(0.85)
    private let ink2 = Color.black.opacity(0.55)

    private var isReadOnly: Bool { if case .view = mode { return true }; return false }
    private var isEdit: Bool { if case .edit = mode { return true }; return false }
    private var cardColor: Color { palette.sticky[min(colorIndex, palette.sticky.count - 1)] }

    var body: some View {
        ZStack {
            Color(red: 40/255, green: 30/255, blue: 20/255).opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            card
                .padding(.horizontal, 18)
                .transition(.opacity.combined(with: .offset(y: 6)))
        }
        .onAppear(perform: loadState)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            timeRow
            if isReadOnly {
                Text("День минув - лише перегляд")
                    .font(.emUI(11)).foregroundStyle(ink2)
                    .padding(.horizontal, 14).padding(.bottom, 10)
            } else if showError {
                Text("Кінець має бути пізніше за початок")
                    .font(.emUI(11)).foregroundStyle(EmbarColors.danger)
                    .padding(.horizontal, 14).padding(.bottom, 10)
            }
            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
                .padding(.horizontal, 14)
            notesField
            bottom
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(cardColor))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .fixedSize(horizontal: false, vertical: true)
        .onExitCommand(perform: onClose) // Esc закриває
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            // Однорядкове поле: Enter зберігає і закриває (фідбек 2026-07-04);
            // авто-фокус — щоб клавіатура одразу була тут, а не в тудушці
            TextField("Назва події…", text: $label)
                .textFieldStyle(.plain)
                .font(.emUI(16, weight: .medium)).foregroundStyle(ink)
                .focused($titleFocus)
                .onSubmit { if !isReadOnly { save() } }
                .disabled(isReadOnly)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12))
                    .foregroundStyle(ink2)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.black.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
    }

    // MARK: - Time + color

    private var timeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock").font(.system(size: 12)).foregroundStyle(ink2)
            timeControl(hour: $startHour, edge: .start)
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Color.black.opacity(0.4))
            timeControl(hour: $endHour, edge: .end)
            Spacer()
            colorMenu
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    /// Пігулка часу; тап відкриває спільний степер (EmbarTimeStepper — той
    /// самий, що в календарі дедлайнів). Редизайн 2026-08-18: замість
    /// системного меню на 49 пунктів
    private func timeControl(hour: Binding<Double>, edge: TimeEdge) -> some View {
        Button { openStepper = edge } label: {
            Text(timeLabel(hour.wrappedValue))
                .font(.emUI(12.5).monospacedDigit())
                .foregroundStyle(Color.black.opacity(0.75))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .popover(isPresented: Binding(
            get: { openStepper == edge },
            set: { if !$0 { openStepper = nil } }
        ), arrowEdge: .bottom) {
            EmbarTimeStepper(hour: intHour(hour), minute: intMinute(hour),
                             minuteStep: 30, hourRange: 0...24,
                             // Година й хвилини — одне число (Double), тож
                             // і писати їх треба разом
                             onWholeTime: { h, m in
                                 hour.wrappedValue = Double(h) + Double(m) / 60
                             })
                .padding(10)
        }
    }

    /// Година події (Double, 9.5 = 9:30) → Int-година для степера
    private func intHour(_ hour: Binding<Double>) -> Binding<Int> {
        Binding(get: { Int(hour.wrappedValue) },
                set: { hour.wrappedValue = Double($0) + hour.wrappedValue.truncatingRemainder(dividingBy: 1) })
    }

    private func intMinute(_ hour: Binding<Double>) -> Binding<Int> {
        Binding(get: { Int((hour.wrappedValue.truncatingRemainder(dividingBy: 1)) * 60 + 0.5) },
                set: { hour.wrappedValue = Double(Int(hour.wrappedValue)) + Double($0) / 60 })
    }

    /// Пігулка «Колір» як у прототипі: сірий фон, кружок поточного кольору
    /// з темним кільцем; попап — білий острівець з 5 свотчами
    private var colorMenu: some View {
        Button { colorPanelOpen = true } label: {
            HStack(spacing: 6) {
                Circle().fill(cardColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(EmbarColors.ink, lineWidth: 1.5))
                Text("Колір").font(.emUI(11.5)).foregroundStyle(Color.black.opacity(0.7))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .popover(isPresented: $colorPanelOpen, arrowEdge: .bottom) {
            HStack(spacing: 6) {
                ForEach(0..<palette.sticky.count, id: \.self) { i in
                    Button { colorIndex = i; colorPanelOpen = false } label: {
                        Circle().fill(palette.sticky[i])
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().stroke(
                                    colorIndex == i ? EmbarColors.ink : Color.black.opacity(0.12),
                                    lineWidth: colorIndex == i ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Notes

    private var notesField: some View {
        TextField("Додаткові деталі…", text: $notes, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.emUI(13)).foregroundStyle(ink)
            .lineSpacing(4)
            .padding(10)
            .frame(minHeight: 60, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.04)))
            .padding(.horizontal, 14).padding(.top, 12)
            .disabled(isReadOnly)
    }

    // MARK: - Bottom

    private var bottom: some View {
        HStack {
            if isEdit {
                Button(role: .destructive, action: onDelete) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash").font(.system(size: 11))
                        Text("Видалити").font(.emUI(12.5))
                    }
                    .foregroundStyle(Color.black.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if !isReadOnly {
                Button(action: save) {
                    Text("Зберегти").font(.emUI(12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(EmbarColors.ink))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)
    }

    // MARK: - Logic

    private func loadState() {
        switch mode {
        case .new(let s, let e, let c):
            startHour = s; endHour = e
            colorIndex = c // рандомний колір спроби (той самий, що в ghost)
        case .edit(let ev), .view(let ev):
            label = ev.label
            notes = ev.notes
            let hours = HomeService.eventHours(ev)
            startHour = hours.start
            endHour = hours.end
            colorIndex = ev.colorIndex % palette.sticky.count
        }
        // Фокус у назву одразу після появи модала
        if !isReadOnly {
            Task { titleFocus = true }
        }
    }

    private func save() {
        guard endHour > startHour else { showError = true; return } // текст — миттєво (§7.2-A)
        onSave(label, notes, startHour, endHour, colorIndex)
    }

    /// Підпис часу за системним форматом (24h «14:30», 12h «2:30 PM») —
    /// раніше було прибито 24-годинне «%d:%02d». Кінець доби лишаємо
    /// «24:00» у 24-годинному (як на осі таймлайну); у 12-годинному він
    /// природно стає «12:00 AM»
    private func timeLabel(_ h: Double) -> String {
        let hh = Int(h), mm = Int((h - Double(hh)) * 60 + 0.5)
        if hh == 24, !ReaderDateFormat.uses12HourClock() { return "24:00" }
        let cal = Calendar.current
        let date = cal.date(byAdding: .minute, value: hh * 60 + mm,
                            to: cal.startOfDay(for: .now)) ?? .now
        return ReaderDateFormat.time(date)
    }
}
