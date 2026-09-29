//
//  NoteEditorView.swift
//  Embar
//
//  Повноекранний редактор нотатки (SPEC §3.2) — оверлей над списком, в'їзд
//  справа. Крок 4: eyebrow (дата · акцент · пін), заголовок, мета-рядок
//  (оновлено · джерело · папка), тіло (NoteBodyView), нижній бар (назад,
//  видалити з undo). Тулбар/backlinks/налаштування — кроки 5/8/11.
//

import SwiftUI
import SwiftData

struct NoteEditorView: View {
    let note: Note
    @ObservedObject var notes: NotesModel
    /// Клік по підпису цитати з Рідера → навігація до запису (M5 §12.3)
    var onReaderSource: (UUID, UUID) -> Void
    /// Клік по «зі стікера» в мета-рядку → назад до стіка-джерела
    /// (SPEC §12.1, фідбек 2026-07-19)
    var onStickerSource: () -> Void
    @StateObject private var editor: NoteEditorModel

    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var toasts: ToastCenter

    @FocusState private var titleFocused: Bool
    @State private var accentPickerOpen = false
    @State private var folderPickerOpen = false
    /// Зміряна висота попапа `[[` — щоб класти його щільно під рядок або
    /// над рядок, а не за фіксованою оцінкою (фідбек 2026-09-03)
    @State private var mentionPopupHeight: CGFloat = 0
    @State private var backlinksOpen = false
    @State private var settingsOpen = false

    // Глобальні тумблери редагування (SPEC §3.3)
    @AppStorage("noteFocusMode") private var focusMode = false
    @AppStorage("noteMetaLine") private var showMetaRow = true
    @AppStorage("noteSpellcheck") private var spellcheck = true

    @Environment(\.modelContext) private var context
    @Query(sort: \NoteFolder.createdAt) private var allFolders: [NoteFolder]
    private var folders: [NoteFolder] { allFolders.filter { $0.deletedAt == nil } }

    init(note: Note, notes: NotesModel, context: ModelContext,
         onReaderSource: @escaping (UUID, UUID) -> Void = { _, _ in },
         onStickerSource: @escaping () -> Void = {}) {
        self.note = note
        self.notes = notes
        self.onReaderSource = onReaderSource
        self.onStickerSource = onStickerSource
        _editor = StateObject(wrappedValue: NoteEditorModel(note: note, context: context))
    }

    var body: some View {
        VStack(spacing: 0) {
            eyebrow
            titleField
            metaRow
            Divider().overlay(EmbarColors.line).padding(.horizontal, 18)
            NoteBodyView(model: editor, onEscape: close, onMentionClick: openMention,
                         onReaderSourceClick: onReaderSource,
                         spellcheck: spellcheck,
                         // Зона тулбара (~48) + 1 рядок тексту: курсор при
                         // наборі внизу завжди над пігулкою (2026-07-28,
                         // уточнено: 3 рядки було забагато); у фокус-режимі
                         // тулбара немає — лише повітря
                         bottomInset: focusMode ? 24 : 70)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Плаваюча пігулка-тулбар (фокус-режим ховає — SPEC §3.3)
                .overlay(alignment: .bottom) {
                    if !focusMode {
                        NoteToolbar(model: editor).padding(.bottom, 10)
                    }
                }
                // Попап `[[`-згадок біля курсора (in-panel острівець)
                .overlay(alignment: .topLeading) { mentionOverlay }
                // Пігулка дій фото при наведенні (обітнути/замінити/видалити)
                .overlay(alignment: .topLeading) { photoHoverOverlay }
            bottomBar
        }
        .embarOverlaySurface()
        // Шит налаштувань — на рівні всього редактора (скрим накриває все)
        .embarBottomSheet(isPresented: $settingsOpen) {
            NoteSettingsSheet(editor: editor)
        }
        // Кроп фото (фідбек 2026-07-05)
        .embarBottomSheet(item: $editor.cropRequest) { request in
            if let image = NoteImageStore.resolve(request.imageID, in: context) {
                NotePhotoCropSheet(
                    image: image,
                    onCancel: { editor.cropRequest = nil },
                    onSave: { cropped in editor.applyCrop(cropped, for: request) }
                )
            }
        }
        .onAppear {
            // Порожня назва → фокус у заголовок; уже названа (напр. створена з
            // композера) → одразу в тіло (як прототип openNote)
            if editor.title.isEmpty {
                titleFocused = true
            } else {
                focusBody()
            }
        }
        // Показ панелі: каретка повертається в тіло — PanelController при
        // хованні стирає first responder, і без цього редактор єдиний
        // лишався без клавіатури до кліку (code review M5 #5)
        .onReceive(NotificationCenter.default.publisher(
            for: .embarPanelDidShow)) { _ in
            if !settingsOpen && !accentPickerOpen && !folderPickerOpen {
                focusBody()
            }
        }
        .onDisappear { editor.saveNow() }
    }

    // MARK: - Eyebrow (дата · акцент · пін)

    private var eyebrow: some View {
        HStack(spacing: 8) {
            Text(NoteDateFormat.relative(note.createdAt).uppercased())
                .font(.emUI(10, weight: .medium)).tracking(1.4)
                .foregroundStyle(EmbarColors.ink3)
            Spacer()
            accentButton
            pinButton
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var accentButton: some View {
        Button { accentPickerOpen = true } label: {
            Circle()
                .fill(currentAccent ?? EmbarColors.ink4)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 1))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $accentPickerOpen, arrowEdge: .bottom) { accentPicker }
    }

    private var currentAccent: Color? {
        guard let i = note.accentColorIndex, i >= 0, i < theme.current.sticky.count else { return nil }
        return theme.current.sticky[i]
    }

    private var accentPicker: some View {
        HStack(spacing: 8) {
            ForEach(Array(theme.current.sticky.enumerated()), id: \.offset) { pair in
                Button {
                    editor.setAccent(pair.offset)
                    accentPickerOpen = false
                } label: {
                    Circle().fill(pair.element).frame(width: 24, height: 24)
                        .overlay(Circle().stroke(EmbarColors.ink,
                                                 lineWidth: note.accentColorIndex == pair.offset ? 2 : 0))
                }
                .buttonStyle(.plain)
            }
            Button {
                editor.setAccent(nil)
                accentPickerOpen = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(EmbarColors.ink3)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var pinButton: some View {
        Button { editor.togglePin() } label: {
            // 📌 як у прототипі (#noteEditorPinBtn): сірий/приглушений поки
            // не закріплено, кольоровий — коли закріплено
            Text("📌")
                .font(.system(size: 13))
                .grayscale(note.pinned ? 0 : 1)
                .opacity(note.pinned ? 1 : 0.4)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Заголовок (Inter 28/500)

    private var titleField: some View {
        TextField("Назва...", text: $editor.title)
            .textFieldStyle(.plain)
            .font(.emUI(28, weight: .medium))
            .foregroundStyle(EmbarColors.ink)
            .focused($titleFocused)
            .padding(.horizontal, 18)
            .padding(.bottom, 4)
            .onSubmit { focusBody() }
            .onChange(of: editor.title) { _, _ in editor.scheduleSave() }
    }

    /// Фокус у тіло (перший респондер — NSTextView). Через async, бо при
    /// відкритті редактора text view ще може бути не змонтований, і фокус
    /// лишався б у композері списку.
    private func focusBody() {
        titleFocused = false
        DispatchQueue.main.async {
            guard let tv = editor.textView else { return }
            tv.window?.makeFirstResponder(tv)
        }
    }

    // MARK: - Мета-рядок (оновлено · джерело · папка)

    @ViewBuilder private var metaRow: some View {
        if showMetaRow {
            HStack(spacing: 6) {
                Text(metaText)
                    .font(.emUI(10.5))
                    .foregroundStyle(EmbarColors.ink4)
                // «зі стікера» — кнопка назад до стіка-джерела
                // (SPEC §12.1; фідбек 2026-07-19)
                if note.bornType == "sticky" {
                    // Крапка-роздільник ПОЗА кнопкою (P2.17): підкреслення
                    // починається з першої літери, а не з «· »
                    Text(verbatim: "·")
                        .font(.emUI(10.5))
                        .foregroundStyle(EmbarColors.ink3)
                    Button(action: onStickerSource) {
                        Text("зі стікера")
                            .font(.emUI(10.5))
                            .foregroundStyle(EmbarColors.ink3)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .onContinuousHover { phase in
                        if case .active = phase { NSCursor.pointingHand.set() }
                        else { NSCursor.arrow.set() }
                    }
                }
                Spacer()
                folderSelector
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        } else {
            Spacer().frame(height: 8)
        }
    }

    private var metaText: String {
        var s = String(localized: "Оновлено · \(NoteDateFormat.relative(note.updatedAt))",
                       comment: "Мета-рядок нотатки: коли востаннє змінено")
        // «зі стікера» рендериться окремою кнопкою поряд; інші джерела —
        // текстом як раніше
        if note.bornType != "sticky",
           let prov = NoteDateFormat.provenance(note.bornType) {
            s += " · \(prov)"
        }
        return s
    }

    private var folderSelector: some View {
        Button { folderPickerOpen = true } label: {
            HStack(spacing: 4) {
                // Трикрапка, не перенос (R4): єдине місце, де назва папки
                // малювалась без обрізання
                Text((note.folder?.name ?? String(localized: "Без папки", comment: "Опція «без папки» у виборі папки")).truncatedChip())
                    .font(.emUI(11)).foregroundStyle(EmbarColors.ink3)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(EmbarColors.ink3)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.04)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $folderPickerOpen, arrowEdge: .bottom) { folderPicker }
    }

    /// Спільний вигляд із рідером (FolderPickerList) + «Нова папка...»
    private var folderPicker: some View {
        FolderPickerList(
            options: [FolderPickerList.Option(
                id: "none", label: String(localized: "Без папки", comment: "Опція «без папки» у виборі папки"),
                isSelected: note.folder == nil,
                select: { pickFolder(nil) })]
            + folders.map { folder in
                FolderPickerList.Option(
                    id: folder.id.uuidString, label: folder.name,
                    isSelected: note.folder?.id == folder.id,
                    select: { pickFolder(folder) })
            },
            onCreate: { name in
                guard ProGate.allowCreate() else { return } // режим читання
                if let folder = NoteService.createFolder(name, existing: folders,
                                                         in: context) {
                    pickFolder(folder)
                }
            })
    }

    private func pickFolder(_ folder: NoteFolder?) {
        editor.setFolder(folder)
        folderPickerOpen = false
    }

    // MARK: - Попап згадок

    @ViewBuilder private var mentionOverlay: some View {
        GeometryReader { geo in
            if let q = editor.mention {
                let w: CGFloat = 224
                let x = min(max(q.anchor.minX, 8), max(geo.size.width - w - 8, 8))
                MentionPopupView(
                    query: q.query,
                    candidates: editor.mentionCandidates,
                    selection: editor.mentionSelection,
                    onPick: { index in
                        editor.mentionSelection = index
                        editor.commitMention()
                    },
                    onClose: { editor.dismissMention() } // P2.23
                )
                // Висоту МІРЯЄМО (фідбек 2026-09-03): фіксована оцінка 190pt
                // відкидала короткий попап на півекрана вгору, і той висів
                // далеко від «[[». Поки не зміряли — не показуємо (один кадр),
                // інакше видно стрибок із чернеткової позиції
                .background { mentionHeightReader }
                .opacity(mentionPopupHeight > 0 ? 1 : 0)
                .offset(x: x, y: mentionY(for: q.anchor, in: geo.size.height))
            }
        }
        .allowsHitTesting(editor.mention != nil)
    }

    private var mentionHeightReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { mentionPopupHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, h in mentionPopupHeight = h }
        }
    }

    /// Попап стоїть ЩІЛЬНО під рядком із «[[», а якщо там не влазить —
    /// щільно над ним. Третій випадок (не влазить ні там, ні там) лишає
    /// його внизу, притиснутим до краю
    private func mentionY(for anchor: CGRect, in available: CGFloat) -> CGFloat {
        let gap: CGFloat = 6
        let h = mentionPopupHeight
        let below = anchor.maxY + gap
        if below + h <= available - 8 { return below }
        let above = anchor.minY - h - gap
        if above >= 8 { return above }
        return min(below, max(available - h - 8, 8))
    }

    // MARK: - Пігулка дій фото (hover на слоті)

    @ViewBuilder private var photoHoverOverlay: some View {
        if let hover = editor.photoHover {
            HStack(spacing: 2) {
                photoAction("crop", help: "Обітнути") { editor.cropPhotoSlot(hover) }
                photoAction("arrow.triangle.2.circlepath", help: "Замінити") { editor.replacePhotoSlot(hover) }
                photoAction("trash", help: "Видалити") { editor.deletePhotoSlot(hover) }
            }
            .padding(3)
            .background(
                Capsule().fill(EmbarColors.surface.opacity(0.95))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            )
            // Мишка на пігулці → тримаємо hover (text view шле exit)
            .onHover { editor.photoHoverHold = $0 }
            .onContinuousHover { phase in
                if case .active = phase { NSCursor.arrow.set() }
            }
            .offset(x: max(hover.rectInBody.maxX - 96, hover.rectInBody.minX + 4),
                    y: hover.rectInBody.minY + 6)
        }
    }

    private func photoAction(_ icon: String, help: LocalizedStringKey,
                             action: @escaping () -> Void) -> some View {
        barIcon(icon, size: 11, width: 26, height: 24, action: action)
            .help(help)
    }

    // MARK: - Нижній бар (SPEC §3.2: назад · backlinks · налаштування · видалити)

    private var bottomBar: some View {
        HStack {
            Button(action: close) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11))
                    Text(backLabel).font(.emUI(13)).lineLimit(1)
                }
                .foregroundStyle(EmbarColors.ink3)
            }
            .buttonStyle(.plain)
            Spacer()
            // Іконки як у прототипі: лінк (backlinks) · слайдери (налашт.) · смітник
            HStack(spacing: 6) {
                barIcon("link") { backlinksOpen = true }
                    .help("Тут згадується")
                    .popover(isPresented: $backlinksOpen, arrowEdge: .top) {
                        BacklinksPopover(note: note) { source in
                            backlinksOpen = false
                            editor.saveNow()
                            notes.push(source)
                        }
                    }
                barIcon("slider.vertical.3") { settingsOpen = true }
                    .help("Налаштування нотатки")
                barIcon("trash", action: deleteNote)
                    .help("Видалити нотатку")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    /// Єдиний білдер іконок-кнопок редактора (нижній бар + пігулка дій фото)
    private func barIcon(_ name: String, size: CGFloat = 13,
                         width: CGFloat = 30, height: CGFloat = 28,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: size < 13 ? .medium : .regular))
                .foregroundStyle(size < 13 ? EmbarColors.ink2 : EmbarColors.ink3)
                .frame(width: width, height: height)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    /// «‹ Нотатки» на кореневому рівні; глибше — титул попередньої в стеку
    private var backLabel: String {
        let stack = notes.editorStack
        guard stack.count > 1 else { return String(localized: "Нотатки", comment: "Хлібна крихта — корінь, список нотаток") }
        let parent = stack[stack.count - 2]
        return (parent.title.isEmpty ? "Без назви" : parent.title).truncatedChip(16)
    }

    // MARK: - Дії

    /// Назад: крок по стеку (згадка → джерело), на корені — закрити
    private func close() {
        editor.clearPhotoHover() // латка hold не отримує onHover(false) при знятті в'ю
        editor.saveNow()
        notes.back()
    }

    /// Клік по чіпу-згадці: жива → відкрити (стек, «назад» повертає);
    /// видалена → тост (SPEC §12.5)
    private func openMention(_ uuid: UUID) {
        guard let target = NoteService.find(uuid, in: context) else { return }
        if target.deletedAt == nil {
            editor.saveNow()
            notes.push(target)
        } else {
            toasts.showMini("Нотатку вже видалено")
        }
    }

    private func deleteNote() {
        editor.saveNow()
        notes.back() // видалення дитини стека повертає до джерела, не в список
        NoteService.softDelete(note)
        toasts.showUndo(message: "Нотатку видалено") {
            NoteService.undoDelete(note)
        }
    }
}
