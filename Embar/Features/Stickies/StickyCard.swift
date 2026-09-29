//
//  StickyCard.swift
//  Embar
//
//  Картка стіка на стіні (SPEC §2.2). Текст на стіку — завжди чорна альфа
//  (ніколи білий): контраст вирішує сама палітра (прототип, applyStickyContrast).
//

import SwiftUI

struct StickyCard: View {
    let sticker: Sticker
    let palette: Palette

    var onOpen: () -> Void = {}
    var onToggleDone: () -> Void = {}
    var onTogglePin: () -> Void = {}
    var onDelete: () -> Void = {}
    /// Архів — вітрина (рішення 2026-07-23): стік лише відображається,
    /// без відкриття, hover-дій і підйому — з ним уже нічого не зробиш
    var readOnly = false
    /// Режим кольору стіни — ПАРАМЕТРАМИ, не @AppStorage: два спостерігачі
    /// на кожну з тисяч карток означали десятки тисяч KVO-реєстрацій, і
    /// саме їхнє зняття було найгарячішим місцем профілю при пере-вибірці
    /// стіни (перф-фікс 2026-08-16; значення тримає StickiesView)
    var colorMode = "random"
    var noWallSlot = 0
    /// Викресленням і розчиненням «виконано» керує СТІНА, не @State
    /// картки (F3, 2026-08-28): LazyVStack кешує стан рядка за id навіть
    /// після зникнення рядка з даних і воскрешає його, коли той самий id
    /// повертається в ту саму колонку — «виконати → повернути» лишало
    /// картку з прозорістю 0 назавжди (SPEC §15.65,
    /// LazyStateResurrectionTests). Джерело правди — StickiesView
    var completing = false
    var dissolving = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hovering = false
    /// Драг-відкріплення на стіл (SPEC §2.7): віджет уже створено і їде
    /// за курсором / ліміт показано (щоб тост не сипався щокадру)
    @State private var desktopDragSpawned = false
    @State private var desktopDragDenied = false

    // Контрастні токени — спільне джерело StickyInk, добір під колір
    // САМЕ ЦЬОГО стіка (адаптивне чорнило, SPEC §15.57)
    private var inks: StickyInk.Tokens { StickyInk.on(color) }
    private var ink: Color { inks.ink }
    private var ink2: Color { inks.ink2 }
    private var ink3: Color { inks.ink3 }
    private let deadlineRed = StickyInk.deadlineRed

    private var color: Color {
        let idx = StickyColorMode.effectiveIndex(
            for: sticker, byWall: colorMode == "byWall", noWallSlot: noWallSlot)
        return palette.sticky[min(idx, palette.sticky.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sticker.text.isEmpty ? " " : sticker.text)
                .font(.emUI(14))
                .foregroundStyle(ink)
                .strikethrough(sticker.done || completing)
                .opacity(sticker.done ? 0.5 : 1)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if !sticker.bodyText.isEmpty {
                Text("…")
                    .font(.emUI(11))
                    .foregroundStyle(ink2)
                    .opacity(sticker.done ? 0.4 : 1)
                    .padding(.top, 3)
            }

            if let deadline = sticker.deadline {
                deadlineBadge(deadline)
                    .opacity(sticker.done ? 0.4 : 1)
                    .padding(.top, 4)
            }

            Text(timeLabel)
                .font(.emUI(10))
                .foregroundStyle(ink3)
                .opacity(sticker.done ? 0.4 : 1)
                .padding(.top, 8)
        }
        // Паддинг ПЕРЕД frame: min-height 80 включає паддинг (як border-box у
        // прототипі). Інакше короткі картки роздуваються й висота не варіює.
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .embarIsland(color, cornerRadius: 12) // стік = острів (пастель@0.4 у склі)
        .overlay(alignment: .bottomTrailing) { cornerContent }
        .overlay(alignment: .topLeading) {
            if sticker.pinned {
                pinDecoration
                    // Кулька — мікро-масштабом ПІСЛЯ того, як картка сіла
                    // (затримка ≈ проявлення ArrivalReveal). Працює лише
                    // коли вьюха жива при зміні pinned; перескік між
                    // колонками пересотворює її, і кулька просто вже на
                    // місці — прийнятна деградація
                    .transition(reduceMotion ? .identity : .asymmetric(
                        insertion: .scale(scale: 0.2).combined(with: .opacity)
                            .animation(.easeOut(duration: 0.18).delay(0.4)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))))
            }
        }
        // Емоджі-тег — правий верхній кут (низ зайнятий діями)
        .overlay(alignment: .topTrailing) {
            if let emoji = sticker.emojiTag {
                Text(emoji)
                    .font(.system(size: 12))
                    .opacity(sticker.done ? 0.4 : 1)
                    .padding(7)
            }
        }
        // Запобіжник !done: вьюха, що зникає з активної секції, заморожена
        // зі своїм dissolving=true, а її наступниця у «Виконаних» мусить
        // народитись видимою, навіть якщо стіна ще не встигла прибрати id
        // зі свого списку розчинюваних
        .opacity(dissolving && !sticker.done ? 0 : 1)
        .offset(y: hovering ? -2 : 0)
        .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: hovering ? 20 : 0, y: hovering ? 6 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { if !readOnly { onOpen() } }
        .gesture(dragToDesktop)
        // Ховер — теж памʼять рядка, яку лінива колонка воскрешає (та сама
        // пастка, що F3): ✓/🗑 клікаються ПІД курсором, тож у момент
        // зникнення hovering=true — повернений стік показував би фантомний
        // підйом і кнопки без курсора. Свіжий появі — чистий стан
        .onAppear { hovering = false }
        .onHover { hovering = readOnly ? false : $0 }
    }

    // MARK: - Drag на робочий стіл (SPEC §2.7, задум користувача):
    // зажати картку (~0.2с) і потягнути за межі панелі — віджет
    // зʼявляється під курсором і їде за ним; відпустити над панеллю =
    // скасувати. Кнопку «на стіл» замінено цим жестом (§15.51).
    // Довге натискання першим — щоб не воювати зі скролом стіни.

    private var dragToDesktop: some Gesture {
        LongPressGesture(minimumDuration: 0.18)
            .sequenced(before: DragGesture(minimumDistance: 0,
                                           coordinateSpace: .global))
            .onChanged { value in
                guard !readOnly, case .second(true, _) = value else { return }
                let location = NSEvent.mouseLocation
                if desktopDragSpawned {
                    DesktopStickyManager.shared
                        .updateDragDetach(sticker, at: location)
                } else if !desktopDragDenied,
                          !DesktopStickyManager.shared.isOverPanel(location) {
                    if DesktopStickyManager.shared
                        .beginDragDetach(sticker, at: location) {
                        desktopDragSpawned = true
                    } else {
                        desktopDragDenied = true
                        NotificationCenter.default.post(
                            name: .embarMiniToast, object: nil,
                            // Число — з константи, а не в тексті: інакше
                            // ліміт довелось би правити у двох місцях, і
                            // множина не має за чим узгоджуватись (i18n)
                            userInfo: ["text": LocalizedStringResource(
                                "Максимум \(DesktopStickyManager.maxWidgets) стіків на столі")])
                    }
                }
            }
            .onEnded { _ in
                if desktopDragSpawned {
                    DesktopStickyManager.shared
                        .endDragDetach(sticker, at: NSEvent.mouseLocation)
                }
                desktopDragSpawned = false
                desktopDragDenied = false
            }
    }

    // MARK: - Нижній правий кут: дії під курсором

    @ViewBuilder private var cornerContent: some View {
        if hovering {
            HStack(spacing: 4) {
                // Хореографію «викреслення → пауза → розчинення → переїзд»
                // веде стіна (completeTapped у StickiesView) — див. F3 вище
                actionButton("checkmark", action: onToggleDone)
                // Виконаний стік не редагується (P2.4): пін прибрано,
                // лишаються повернення в активні (✓) і смітник
                if !sticker.done {
                    actionButton(sticker.pinned ? "pin.fill" : "pin", action: onTogglePin)
                }
                actionButton("trash", action: onDelete)
            }
            .padding(8)
        }
        // Дзвіночка більше нема (2026-08-19): нагадування злилося з
        // дедлайном, і єдиний знак часу на картці — бейдж дедлайну
    }

    private func actionButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        // Голі іконки без сірих плашок (фідбек 2026-08-18: квадратики
        // муляли око); мʼякий круглий hover лишає адресність кліку
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverDarken(Circle())
    }

    private func deadlineBadge(_ date: Date) -> some View {
        // Минулий строк уже не підганяє (P2.7): просто сірий,
        // а не вічно червоний (без викреслення — фідбек 2026-09-01)
        let past = date < .now
        return HStack(spacing: 3) {
            // Дзвіночок = сповіщення прийде; календар = просто строк без
            // нагадування (те саме правило, що в чіпі розгорнутого стіка)
            Image(systemName: sticker.notifyOffsetMinutes != nil
                  ? "bell" : "calendar")
                .font(.system(size: 9))
            Text(shortDate(date))
        }
        .font(.emUI(10, weight: .medium))
        .foregroundStyle(past ? ink3 : deadlineRed)
    }

    // MARK: - Пін-декорація (3D-кулька + голка)

    private var pinDecoration: some View {
        ZStack(alignment: .topLeading) {
            // Голка позаду
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: "#bbbbbb"), Color(hex: "#999999")],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 2, height: 10)
                .rotationEffect(.degrees(5))
                .offset(x: 19, y: -2)
            // Кулька
            Circle()
                .fill(ballFill)
                .frame(width: 12, height: 12)
                .overlay(
                    // Легкий відблиск для 3D
                    Circle().fill(Color.white.opacity(0.4))
                        .frame(width: 4, height: 4)
                        .offset(x: -1.5, y: -1.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
                .offset(x: 14, y: -11)
        }
    }

    private var ballFill: AnyShapeStyle {
        // Cream — оригінальна червоно-рожева кулька; решта — акцент палітри.
        // ❗ Свідомо ЛІТЕРАЛИ, а не токени: це бренд-декор із власним
        // градієнтом (CLAUDE.md §дизайн: «Cream keeps its original
        // red-pink pin»). Те, що темний кінець градієнта числом дорівнює
        // EmbarColors.danger, — випадковість; не зводити їх в один токен,
        // бо роль інша (пін ≠ небезпека)
        if palette.slug == "cream" {
            return AnyShapeStyle(RadialGradient(
                colors: [Color(hex: "#ff7b7b"), Color(hex: "#c0392b")],
                center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: 10))
        }
        return AnyShapeStyle(palette.accent)
    }

    // MARK: - Дати (українською — StickyDateFormat; .formatted давав
    // системну локаль «Jul 16» / «7:09 PM», фідбек 2026-07-19)

    private var timeLabel: String {
        StickyDateFormat.relative(sticker.createdAt)
    }

    private func shortDate(_ date: Date) -> String {
        StickyDateFormat.shortDate(date)
    }
}

/// Дати стіків: «19:09» (сьогодні) / «вчора» / «4 дні тому» / «13 лип».
/// Назву й порядок місяця дає ReaderDateFormat (одне джерело).
///
/// i18n 2026-08-03: ручний daysWord (день/дні/днів) прибрано — форму слова
/// тепер обирає каталог за правилами множини кожної мови.
enum StickyDateFormat {
    static func relative(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) {
            return ReaderDateFormat.time(date) // 24h, як скрізь (SPEC: M3)
        }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
           cal.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "вчора",
                          comment: "Дата на картці стіка")
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        if days < 7 {
            return String(localized: "\(days) днів тому",
                          comment: "Дата на картці стіка: скільки днів тому створено")
        }
        return shortDate(date)
    }

    /// «13 лип» / «Jul 13»
    static func shortDate(_ date: Date) -> String {
        ReaderDateFormat.dayMonth(date)
    }

    /// «13 лип · 14:05» (дедлайн/автоархів в expanded-редакторі)
    static func shortDateTime(_ date: Date) -> String {
        "\(shortDate(date)) · \(ReaderDateFormat.time(date))"
    }
}
