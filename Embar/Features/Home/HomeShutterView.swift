//
//  HomeShutterView.swift
//  Embar
//
//  Home-шторка (SPEC §5.2): hero + sheet. Слайд знизу дає ContentView
//  (transition .move). Наповнення sheet (тиждень/таймлайн/списки) —
//  кроки 4–8; тут — hero + порожній sheet-каркас.
//

import SwiftUI
import SwiftData

struct HomeShutterView: View {
    @ObservedObject var home: HomeModel
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.modelContext) private var context

    @Query private var allTodos: [Todo]
    @Query private var allHabits: [Habit]

    @State private var eventEditor: HomeEventModal.Mode?
    @State private var tab: HomeTab = .todo
    /// Напрям гортання вкладок: 1 = вперед (todo→done), -1 = назад
    @State private var tabDirection = 1
    /// Фліп вкладок вмикається ПІСЛЯ відкриття шторки: інакше transition
    /// спрацьовує і при вставленні самої шторки — вкладки «жили окремо»
    @State private var shutterReady = false
    @Namespace private var tabUnderlineNS

    var body: some View {
        VStack(spacing: 0) {
            hero
            sheet
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EmbarColors.surface)
        .onAppear {
            // Шторка відкривається як ОДНА сторінка; фліп вкладок — лише потім
            shutterReady = false
            DispatchQueue.main.async { shutterReady = true }
        }
        .overlay {
            if let mode = eventEditor {
                HomeEventModal(
                    mode: mode, palette: theme.current,
                    onSave: { label, notes, s, e, ci in
                        saveEvent(mode: mode, label: label, notes: notes, start: s, end: e, colorIndex: ci)
                    },
                    onDelete: { deleteEvent(mode: mode) },
                    onClose: { eventEditor = nil } // анімацію дає .animation(value:) нижче
                )
                // ❗ Identity за режимом: перехід .edit(A)→.edit(B) під час
                // 0.2с exit-анімації НЕ перезапускав onAppear/loadState —
                // модал показував і зберігав поля A у подію B (відтворено
                // харнесом: BODY payload=B state=A, без другого ONAPPEAR)
                .id(modeKey(mode))
            }
        }
        .animation(.easeOut(duration: 0.2), value: eventEditor != nil)
    }

    // MARK: - Sheet: фіксовані тиждень/таймлайн/таби + скрол списків

    private var sheetContent: some View {
        VStack(spacing: 0) {
            HomeWeekRow(home: home, accent: theme.current.accent)
            HomeTimelineView(
                home: home, palette: theme.current,
                onAddEvent: {
                    eventEditor = .new(start: defaultStart, end: min(defaultStart + 1, 24),
                                       color: Int.random(in: 0..<5))
                },
                onEventTap: { ev in eventEditor = home.isReadOnlyDay ? .view(ev) : .edit(ev) },
                onCreateDrag: { s, e, c in eventEditor = .new(start: s, end: e, color: c) }
            )
            tabBar
            // ❗ Swap через .id — ЗЗОВНІ ScrollView: усередині нього transition
            // не спрацьовує. Уся сторінка (тудушки+звички) — одна «картка»
            ZStack {
                ScrollView {
                    // ❗ VStack обовʼязковий: два вигляди прямо в ScrollView
                    // SwiftUI накладає один на одного (як ZStack), а не стосом
                    VStack(spacing: 0) {
                        HomeListsView(home: home, palette: theme.current, tab: $tab)
                        HomeHabitsView(home: home, palette: theme.current, tab: $tab)
                    }
                    .padding(.top, 12) // відступ від таб-бару
                    // Морфи від перемикання вкладки — вимкнені, scoped до tab.
                    // ❗ Бланкетний transaction тут виключав увесь вміст із
                    // move-transition шторки: списки «зʼявлялися нізвідки»
                    // раніше, ніж доїжджала сама шторка
                    .animation(nil, value: tab)
                }
                .id(tab)
                .transition(shutterReady ? tabFlip : .identity)
            }
            .clipped()
            .scrollIndicators(.hidden)
        }
    }

    /// Стабільний ключ identity модала: різні події/режими → різний ключ →
    /// свіжі @State і loadState
    private func modeKey(_ mode: HomeEventModal.Mode) -> String {
        switch mode {
        case .new(let s, let e, let c): return "new-\(s)-\(e)-\(c)"
        case .edit(let ev): return "edit-\(ev.id.uuidString)"
        case .view(let ev): return "view-\(ev.id.uuidString)"
        }
    }

    /// Фліп сторінки вкладок: направлений слайд «карткою» з вшитою анімацією
    private var tabFlip: AnyTransition {
        let anim = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.32)
        return .asymmetric(
            insertion: AnyTransition.move(edge: tabDirection >= 0 ? .trailing : .leading)
                .combined(with: .opacity).animation(anim),
            removal: AnyTransition.move(edge: tabDirection >= 0 ? .leading : .trailing)
                .combined(with: .opacity).animation(anim)
        )
    }

    // MARK: - Таб-бар «До зробити / Виконано»

    private var tabBar: some View {
        HStack(spacing: 18) {
            tabButton("До зробити", count: todoCount, value: .todo)
            tabButton("Виконано", count: doneCount, value: .done)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EmbarColors.line).frame(height: 1)
        }
    }

    private func tabButton(_ label: LocalizedStringKey, count: Int, value: HomeTab) -> some View {
        let active = tab == value
        return Button {
            guard value != tab else { return }
            tabDirection = (value == .done) ? 1 : -1
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                tab = value
            }
        } label: {
            HStack(spacing: 6) {
                Text(label).font(.emUI(13, weight: active ? .medium : .regular))
                Text("\(count)").font(.emUI(11).monospacedDigit()).foregroundStyle(EmbarColors.ink3)
            }
            .foregroundStyle(active ? EmbarColors.ink : EmbarColors.ink3)
            // Тексти — миттєво, scoped до tab (бланкетний transaction
            // «висмикував» лейбли з move-transition шторки при відкритті)
            .animation(nil, value: tab)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) {
                // Риска ковзає між вкладками (як таби панелі)
                if active {
                    Rectangle().fill(EmbarColors.ink).frame(height: 1.5)
                        .matchedGeometryEffect(id: "homeTabUnderline", in: tabUnderlineNS)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var todoCount: Int {
        allTodos.filter { $0.deletedAt == nil && !$0.done }.count
            + allHabits.filter { $0.deletedAt == nil && !HomeService.isDone($0, on: home.todayAnchor) }.count
    }

    private var doneCount: Int {
        allTodos.filter { $0.deletedAt == nil && $0.done }.count
            + allHabits.filter { $0.deletedAt == nil && HomeService.isDone($0, on: home.todayAnchor) }.count
    }

    /// Дефолтний початок нової події: наступні пів години (сьогодні) / 9:00
    private var defaultStart: Double {
        guard home.isToday else { return 9 }
        return min((HomeService.hourOfDay(.now) * 2).rounded() / 2, 23)
    }

    // MARK: - Save / Delete

    private func saveEvent(mode: HomeEventModal.Mode, label: String, notes: String,
                           start: Double, end: Double, colorIndex: Int) {
        switch mode {
        case .new:
            if let ev = HomeService.addEvent(label: label, day: home.selectedDate,
                                             startHour: start, endHour: end,
                                             colorIndex: colorIndex, in: context) {
                ev.notes = notes
            }
        case .edit(let ev):
            let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
            ev.label = name.isEmpty ? String(localized: "Подія", comment: "Назва події за замовчуванням у таймлайні Home") : name
            ev.notes = notes
            ev.startDate = HomeService.date(day: home.selectedDate, hour: start)
            ev.endDate = HomeService.date(day: home.selectedDate, hour: end)
            ev.colorIndex = colorIndex
            ev.updatedAt = .now
        case .view:
            // Read-only минулих днів: сюди не має долітати (Save/Enter
            // сховані-загарджені в модалі) — інваріант явний, без запису
            assertionFailure("saveEvent у view-режимі")
        }
        eventEditor = nil
    }

    private func deleteEvent(mode: HomeEventModal.Mode) {
        eventEditor = nil
        guard case .edit(let ev) = mode else { return }
        HomeService.softDelete(ev)
        toasts.showUndo(message: "Подію видалено") { HomeService.undoDelete(ev) }
    }

    // MARK: - Hero (180pt)

    /// Фото-плейсхолдер hero (те саме, що в прототипі). Вибір власного
    /// фото користувачем — M6 #3.4
    private static let heroImage: NSImage? = Bundle.main
        .url(forResource: "HomeHeroPlaceholder", withExtension: "jpeg")
        .flatMap { NSImage(contentsOf: $0) }

    private var hero: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let img = Self.heroImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Фолбек: градієнт з палітри
                    LinearGradient(
                        colors: [theme.current.sticky[3].opacity(0.7),
                                 theme.current.sticky[2].opacity(0.45),
                                 EmbarColors.surface],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            }
            .frame(height: 180)
            .clipped()

            // Фейд фото до surface знизу (прототип .home-hero::before)
            LinearGradient(
                stops: [
                    .init(color: EmbarColors.surface.opacity(0), location: 0),
                    .init(color: EmbarColors.surface.opacity(0.10), location: 0.35),
                    .init(color: EmbarColors.surface.opacity(0.85), location: 0.70),
                    .init(color: EmbarColors.surface, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack {
                heroBar
                Spacer()
                heroDate
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
        .frame(height: 180)
        .clipped()
    }

    private var heroBar: some View {
        HStack {
            glassButton("chevron.left") { home.close() }
            Spacer()
            HStack(spacing: 8) {
                glassButton("slider.horizontal.3") { /* Settings — M6 */ }
                avatar
            }
        }
    }

    private func glassButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white) // на фото — білі (прототип #fff)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.28), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var avatar: some View {
        Text("S")
            .font(.emUI(13, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.28), in: Circle())
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1.5))
    }

    private var heroDate: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(monthText)
                .font(.emDisplay(40, italic: true))
                .tracking(-1)
            Spacer()
            Text(Weekday.dayNumber(home.selectedDate))
                .font(.emDisplay(40, italic: true).monospacedDigit())
        }
        .foregroundStyle(EmbarColors.ink)
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    // MARK: - Sheet (наповнення — кроки 4–8)

    private var sheet: some View {
        sheetContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                EmbarColors.surface
                    .clipShape(.rect(topLeadingRadius: 24, topTrailingRadius: 24))
            )
            .padding(.top, -8) // sheet перекриває hero на 8pt (прототип)
    }

    // MARK: - Дата

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        // Мова системи, а не прибитий uk_UA (i18n 2026-08-03)
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("LLLL") // standalone: «липень» / «July»
        return f
    }()

    private var monthText: String {
        let m = Self.monthFormatter.string(from: home.selectedDate)
        return m.prefix(1).uppercased() + m.dropFirst()
    }
}
