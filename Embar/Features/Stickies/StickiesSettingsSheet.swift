//
//  StickiesSettingsSheet.swift
//  Embar
//
//  Вміст bottom-sheet налаштувань стіків (SPEC §2.6). Контекст: конкретна
//  стіна або «Загальні» — набір секцій трохи відрізняється (як у прототипі).
//  Chrome (скрим, slide-up, handle) дає BottomSheet; презентується на рівні
//  панелі (ContentView) через StickiesSettingsSheetContainer.
//

import SwiftUI
import SwiftData

/// Обгортка з доступом до бази — резолвить стіну й дії, рендерить лист.
struct StickiesSettingsSheetContainer: View {
    @ObservedObject var model: StickiesModel
    let palette: Palette

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var toasts: ToastCenter
    @Query(sort: \Wall.sortOrder) private var allWalls: [Wall]

    private var walls: [Wall] { allWalls.filter { $0.deletedAt == nil } }
    private var selectedWall: Wall? { walls.first { $0.id == model.selectedWallID } }

    var body: some View {
        StickiesSettingsSheet(
            wall: selectedWall,
            filterKind: $model.filterKind,
            emojiFilter: $model.emojiFilter,
            palette: palette,
            walls: walls,
            onDeleteWall: deleteWall,
            isWallNameTaken: { name in walls.contains { $0.name == name } },
            onComingSoon: { toasts.showMini($0) },
            // «Архів →»: доступ до заархівованих переїхав із чіпів у рядок
            // (фідбек 2026-07-19)
            onOpenArchive: {
                model.emojiFilter = nil
                model.filterKind = .archive
                model.showingSettings = false
            }
        )
    }

    private func deleteWall(_ wall: Wall) {
        // Закриваємо шторку і показуємо віконце-питання на поверхні стіни
        // (лише стіну чи разом зі стіками) — фідбек 2026-07-07
        model.showingSettings = false
        model.wallPendingDelete = wall
    }
}

struct StickiesSettingsSheet: View {
    let wall: Wall?
    @Binding var filterKind: StickyFilterKind
    @Binding var emojiFilter: String?
    let palette: Palette
    var walls: [Wall] = []
    var onDeleteWall: (Wall) -> Void = { _ in }
    var isWallNameTaken: (String) -> Bool = { _ in false }
    var onComingSoon: (LocalizedStringResource) -> Void = { _ in }
    var onOpenArchive: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let wall {
                WallSettingsContent(wall: wall, filterKind: $filterKind,
                                    emojiFilter: $emojiFilter, palette: palette,
                                    onDelete: onDeleteWall, isNameTaken: isWallNameTaken,
                                    onComingSoon: onComingSoon,
                                    onOpenArchive: onOpenArchive)
            } else {
                GeneralSettingsContent(filterKind: $filterKind,
                                       emojiFilter: $emojiFilter, palette: palette,
                                       walls: walls, onComingSoon: onComingSoon,
                                       onOpenArchive: onOpenArchive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Спільні дрібниці

struct SettingsSectionTitle: View {
    let text: LocalizedStringKey
    var body: some View {
        // .textCase, а не .uppercased(): регістр застосовується вже до
        // перекладеного тексту (i18n 2026-08-03)
        Text(text)
            .textCase(.uppercase)
            .font(.emUI(10, weight: .medium))
            .tracking(0.14 * 10)
            .foregroundStyle(EmbarColors.ink3)
    }
}

/// Заголовок листа: назва + підзаголовок
private struct SheetTitle: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.emUI(16, weight: .medium)).foregroundStyle(EmbarColors.ink)
            Text(subtitle).font(.emUI(12)).foregroundStyle(EmbarColors.ink3)
        }
    }
}

/// Рядок чіпів фільтра «Показувати»
private struct FilterChips: View {
    @Binding var filterKind: StickyFilterKind
    @Binding var emojiFilter: String?
    /// Стіна, чиї емоджі показуємо (nil = «Всі» — з усіх стін)
    var wall: Wall? = nil

    @Query(sort: \Sticker.createdAt, order: .reverse)
    private var allStickers: [Sticker]

    /// Емоджі, реально використані на стіках поточної стіни (динамічно),
    /// у порядку свіжості, без дублів
    private var usedEmojis: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for sticker in allStickers
        where sticker.deletedAt == nil && !sticker.archived
            && (wall == nil || sticker.wall?.id == wall?.id) {
            if let emoji = sticker.emojiTag, seen.insert(emoji).inserted {
                out.append(emoji)
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionTitle(text: "Показувати")
            FlowRow(spacing: 6) {
                // .archive прибраний із чіпів (рядок «Архів →» унизу листа)
                ForEach(StickyFilterKind.allCases.filter { $0 != .archive }) { kind in
                    Chip(label: kind.label,
                         isActive: filterKind == kind && emojiFilter == nil) {
                        filterKind = kind
                        emojiFilter = nil
                    }
                }
                // Емоджі-чіпи (фідбек 2026-07-19): вибір емоджі = фільтр
                // «всі стіки з цим тегом»
                ForEach(usedEmojis, id: \.self) { emoji in
                    Chip(label: emoji, isActive: emojiFilter == emoji) {
                        emojiFilter = emoji
                        filterKind = .all
                    }
                }
            }
        }
    }
}

/// Рядок «Архів →» унизу листа — доступ до заархівованих (чіп прибрано)
private struct ArchiveLinkRow: View {
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack {
                Text("Архів")
                    .font(.emUI(13, weight: .medium))
                    .foregroundStyle(EmbarColors.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(EmbarColors.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Сегмент режиму кольорів (Різнокольорові / Свій колір у стіни)
private struct ColorModeSegment: View {
    @AppStorage("wallColorMode") private var mode = "random"
    var body: some View {
        HStack(spacing: 0) {
            segButton("Різнокольорові", value: "random")
            segButton("Свій колір у стіни", value: "byWall")
        }
        .padding(4)
        .background(Capsule().fill(EmbarColors.tint))
    }

    private func segButton(_ label: LocalizedStringKey, value: String) -> some View {
        Button { mode = value } label: {
            Text(label)
                .font(.emUI(12, weight: mode == value ? .medium : .regular))
                .foregroundStyle(mode == value ? EmbarColors.ink : EmbarColors.ink3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(mode == value ? Color.white : Color.clear)
                        .shadow(color: mode == value ? .black.opacity(0.08) : .clear, radius: 3, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// 5 кольорових крапок палітри з вибором
private struct ColorDots: View {
    let palette: Palette
    let selected: Int
    let onSelect: (Int) -> Void
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<palette.sticky.count, id: \.self) { i in
                Button { onSelect(i) } label: {
                    Circle()
                        .fill(palette.sticky[i])
                        .frame(width: 22, height: 22)
                        // Тонкий обвід із невеликим зазором (прототип: 1.5px ring)
                        .overlay(
                            Circle().stroke(selected == i ? Color.black.opacity(0.5) : .clear, lineWidth: 1.5)
                                .padding(-3)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Підказка (spec §8.1 tone) — жирне «Підказка:» + приглушений текст
private struct HintNote: View {
    var body: some View {
        (Text("Підказка: ").font(.emUI(11.5, weight: .semibold)).foregroundColor(EmbarColors.ink2)
         + Text("будь-який стікер можна перетворити на нотатку - відкрий його і натисни іконку документа у верхньому куті картки.")
            .font(.emUI(11.5)).foregroundColor(EmbarColors.ink3))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Рядок «label + опис» ліворуч, контрол праворуч (по центру вертикально)
private struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringKey
    let desc: LocalizedStringKey
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.emUI(13, weight: .medium)).foregroundStyle(EmbarColors.ink)
                Text(desc).font(.emUI(11)).foregroundStyle(EmbarColors.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

/// Острівець перетягування порядку стін (нативний List.onMove у popover —
/// узгоджено з Liquid Glass спадних меню)
private struct WallReorderList: View {
    let walls: [Wall]
    private let rowHeight: CGFloat = 30

    var body: some View {
        List {
            ForEach(walls) { wall in
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11)).foregroundStyle(EmbarColors.ink3)
                    Text(wall.name).font(.emUI(13)).foregroundStyle(EmbarColors.ink)
                }
                .frame(height: rowHeight)
                .listRowSeparator(.hidden)
            }
            .onMove(perform: move)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, rowHeight)
        // Висота залежить від кількості папок (до 8 видимих, далі — скрол)
        .frame(width: 200,
               height: CGFloat(min(walls.count, 8)) * (rowHeight + 4) + 12)
        .padding(.vertical, 4)
    }

    private func move(from source: IndexSet, to dest: Int) {
        var arr = walls
        arr.move(fromOffsets: source, toOffset: dest)
        for (i, wall) in arr.enumerated() { wall.sortOrder = i }
    }
}

// MARK: - Загальні

private struct GeneralSettingsContent: View {
    @Binding var filterKind: StickyFilterKind
    @Binding var emojiFilter: String?
    let palette: Palette
    let walls: [Wall]
    var onComingSoon: (LocalizedStringResource) -> Void
    var onOpenArchive: () -> Void = {}

    @AppStorage("wallColorMode") private var colorMode = "random"
    @AppStorage("hideDoneStickies") private var hideDone = false
    @AppStorage(StickyAutoArchive.storageKey)
    private var autoArchiveDays = StickyAutoArchive.defaultDays
    @AppStorage("noWallColorSlot") private var noWallSlot = 0
    @State private var showReorder = false

    var body: some View {
        SheetTitle(title: "Загальні", subtitle: "Фільтри, кольори і поведінка стікерів")

        FilterChips(filterKind: $filterKind, emojiFilter: $emojiFilter)

        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionTitle(text: "Кольори стікерів")
            ColorModeSegment()
            if colorMode == "byWall" {
                ColorDots(palette: palette, selected: noWallSlot) { noWallSlot = $0 }
                Text("Колір стікерів, що не належать жодній стіні")
                    .font(.emUI(11)).italic().foregroundStyle(EmbarColors.ink3)
            }
        }

        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionTitle(text: "Загальні налаштування")

            SettingsRow(title: "Автоархів",
                        desc: "Виконані стікери їдуть в архів через вказаний час.") {
                ValueMenu(label: autoArchiveLabel) {
                    Button("1 тиждень") { setAutoArchiveDays(7) }
                    Button("Місяць") { setAutoArchiveDays(30) }
                    Button("3 місяці") { setAutoArchiveDays(90) }
                }
            }

            Divider().overlay(EmbarColors.line)

            // Стиль і превʼю сповіщень — не наші налаштування, а системні:
            // без превʼю банер показує лише «Embar» (знахідка 2026-08-20),
            // а без стилю «Нагадування» зникає за кілька секунд
            SettingsRow(title: "Нагадування",
                        desc: "Щоб бачити текст нагадування прямо в банері, увімкни попередній перегляд і стиль «Нагадування» в системних параметрах.") {
                Button(action: ReminderScheduler.openSystemNotificationSettings) {
                    HStack(spacing: 3) {
                        Text("Відкрити").font(.emUI(12, weight: .medium))
                        Image(systemName: "chevron.right").font(.system(size: 10))
                    }
                    .foregroundStyle(EmbarColors.ink2)
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(EmbarColors.line)

            HStack {
                Text("Показувати виконані на стіні").font(.emUI(13, weight: .medium))
                    .foregroundStyle(EmbarColors.ink)
                Spacer()
                Toggle("", isOn: Binding(get: { !hideDone }, set: { hideDone = !$0 }))
                    .toggleStyle(EmbarToggleStyle.sheet)
            }

            if walls.count > 1 {
                Divider().overlay(EmbarColors.line)
                SettingsRow(title: "Порядок стін", desc: "Потягни стіну на нове місце") {
                    Button { showReorder = true } label: {
                        HStack(spacing: 3) {
                            Text("Змінити").font(.emUI(12, weight: .medium))
                            Image(systemName: "chevron.right").font(.system(size: 10))
                        }
                        .foregroundStyle(EmbarColors.ink2)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showReorder, arrowEdge: .trailing) {
                        WallReorderList(walls: walls)
                    }
                }
            }
        }

        // Перемикач матеріальності (Glass-тест) переїхав у App Settings
        // (2026-07-19)

        ArchiveLinkRow(onOpen: onOpenArchive)

        HintNote()
    }

    /// Новий строк + позначка, що правила змінились саме зараз: інакше
    /// «3 місяці → 1 тиждень» змело б в архів усе давно виконане тим самим
    /// запуском (ревʼю 2026-08-20). Після зміни кожен стік отримує повний
    /// новий строк на стіні
    private func setAutoArchiveDays(_ days: Int) {
        guard days != autoArchiveDays else { return }
        autoArchiveDays = days
        StickyAutoArchive.noteTermChange()
    }

    private var autoArchiveLabel: String {
        switch autoArchiveDays {
        case 7: String(localized: "1 тиждень", comment: "Строк автоархіву стіка")
        case 90: String(localized: "3 місяці", comment: "Строк автоархіву стіка")
        // Вимкненого стану більше немає (2026-08-19) — усе поза набором
        // читається як дефолтний місяць, як і в StickyAutoArchive.days
        default: String(localized: "Місяць", comment: "Строк автоархіву стіка")
        }
    }
}

// MARK: - Стіна

private struct WallSettingsContent: View {
    @Bindable var wall: Wall
    @Binding var filterKind: StickyFilterKind
    @Binding var emojiFilter: String?
    let palette: Palette
    var onDelete: (Wall) -> Void
    var isNameTaken: (String) -> Bool
    var onComingSoon: (LocalizedStringResource) -> Void
    var onOpenArchive: () -> Void = {}

    @AppStorage("wallColorMode") private var colorMode = "random"
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("Назва стіни", text: $draftName)
                .textFieldStyle(.plain)
                .font(.emUI(16, weight: .medium))
                .foregroundStyle(EmbarColors.ink)
                .onSubmit(commitName)
                .onAppear { draftName = wall.name }
            Text("Налаштування цієї стіни").font(.emUI(12)).foregroundStyle(EmbarColors.ink3)
        }

        FilterChips(filterKind: $filterKind, emojiFilter: $emojiFilter, wall: wall)

        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionTitle(text: "Кольори стікерів")
            ColorModeSegment()
            if colorMode == "byWall" {
                ColorDots(palette: palette, selected: wall.effectiveColorSlot) { wall.colorSlot = $0 }
            }
        }

        // СПІЛЬНА СТІНА — placeholder (реальний шеринг у v2, SPEC §14)
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionTitle(text: "Спільна стіна")
            Text("Запроси близьких чи команду - додавайте, редагуйте і закривайте стікери разом, на одній стіні.")
                .font(.emUI(12)).foregroundStyle(EmbarColors.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button { onComingSoon("Спільні стіни - скоро") } label: {
                Text("Поділитися стіною «\(wall.name.truncatedChip())»")
                    .font(.emUI(13, weight: .medium))
                    .foregroundStyle(EmbarColors.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).stroke(EmbarColors.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }

        ArchiveLinkRow(onOpen: onOpenArchive)

        HintNote()

        Button(role: .destructive) { onDelete(wall) } label: {
            Text("Видалити стіну «\(wall.name.truncatedChip())»")
                .font(.emUI(11.5))
                .foregroundStyle(EmbarColors.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle()) // клікабельна вся ширина, не лише текст
        }
        .buttonStyle(.plain)
    }

    private func commitName() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Валідація SPEC §2.6: не порожнє і не дублікат — інакше відкат
        if name.isEmpty || (name != wall.name && isNameTaken(name)) {
            draftName = wall.name
        } else {
            wall.name = name
        }
    }
}
