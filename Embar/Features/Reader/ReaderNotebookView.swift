//
//  ReaderNotebookView.swift
//  Embar
//
//  Блокнот рідера — повноекранний оверлей (SPEC §4.2; прототип
//  .reader-notebook). Крок 3: шапка (обкладинка + назва + link-bar)
//  і футер; композер та записи — крок 4.
//

import SwiftUI
import SwiftData

struct ReaderNotebookView: View {
    let book: ReaderBook
    @ObservedObject var reader: ReaderModel
    /// Цитата поїхала в нотатку → ContentView перемикає таб і відкриває
    /// редактор (паттерн matureSticky, SPEC §12.3)
    var onQuoteToNote: (Note) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var toasts: ToastCenter
    /// 5 останніх нотаток для попапа «У нотатку». ОБМЕЖЕНИЙ запит:
    /// @Query без ліміту тягнув при відкритті блокнота всю таблицю
    /// нотаток заради пʼяти (перф-фікс 2026-08-16)
    @Query(recentNotesDescriptor) private var recentNotes: [Note]

    private static var recentNotesDescriptor: FetchDescriptor<Note> {
        var descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 5
        return descriptor
    }

    /// Спалах запису після goToReaderEntry
    @State private var flashEntryID: UUID?
    /// Виміряна висота левітуючого compose — верхній відступ стрічки
    @State private var composeHeight: CGFloat = 96
    /// Тригер перерендеру surface-градієнтів при зміні «фону панелі»
    /// (блокнот не спостерігає ThemeStore; фідбек 2026-07-19)
    @AppStorage("panelSurface") private var panelSurfaceRaw = PanelSurface.warm.rawValue

    @State private var title: String
    @State private var linkText: String
    /// Ховер кнопки камери (×-бейдж) і віконце «видалити чи замінити»
    @State private var coverHovering = false
    @State private var coverDialogOpen = false

    /// Активний кроп фото (превʼю композера або фото запису):
    /// картинка + замикання, куди віддати обрізане
    struct CropJob: Identifiable {
        let id = UUID()
        let image: NSImage
        let apply: (NSImage) -> Void
    }
    @State private var cropJob: CropJob?
    /// ❗ Кеш декодованої обкладинки: NSImage(data:) на кожен рендер
    /// створює новий обʼєкт → фото мигає при кожному вводі назви
    @State private var cover: NSImage?
    @FocusState private var titleFocused: Bool
    /// Щойно створений блокнот чекає першого блюру назви: якщо людина
    /// пішла з поля, нічого не набравши, плейсхолдер «Новий блокнот»
    /// стає справжньою назвою (фідбек 2026-09-04). Старих блокнотів із
    /// навмисно стертою назвою це не чіпає - прапорець живе лише в
    /// сесії створення
    @State private var awaitingFirstTitleBlur = false
    @FocusState private var linkFocused: Bool

    // Фільтри стрічки (SPEC §4.3; скидаються при відкритті іншого
    // блокнота — стан свіжий завдяки .id(book.id) оверлея)
    /// nil = Всі; "fav" — обране; інакше rawValue типу
    @State private var typeFilter: String?
    @State private var tagFilter: Set<String> = []
    @State private var tagDropdownOpen = false
    @Namespace private var typeChipNS

    // Папка блокнота (футер, крок 7)
    @State private var folderDropdownOpen = false
    // Фокус поля пошуку записів (стан пошуку — в ReaderModel для Cmd+F)
    @FocusState private var nbSearchFocus: Bool

    // Теми (2026-07-22, інлайн-розділювачі): чернетка назви у стрічці
    // і згорнуті русла — свіжі на кожен блокнот (.id оверлея)
    @State private var creatingTheme = false
    @State private var themeDraftName = ""
    @FocusState private var themeDraftFocused: Bool
    @State private var collapsedThemes: Set<UUID> = []

    // Пен-режим хайлайтів (SPEC §4.2, крок 9): свіжий на кожен блокнот
    @State private var penActive = false
    @State private var penMode = "highlight"
    @State private var penColor = "yellow"

    // Один плеєр голосових на блокнот (крок 13)
    @StateObject private var voicePlayer = VoicePlayer()

    // Налаштування рідера (SPEC §4.4, крок 15)
    @State private var showingSettings = false
    @AppStorage("readerHashtags") private var hashtagsEnabled = true
    @AppStorage("readerExtraTypes") private var extraTypesEnabled = false
    @AppStorage("readerFont") private var fontRaw = ReaderBodyFont.inter.rawValue
    /// Показ рядка джерела під шапкою (тумблер у налаштуваннях, 2026-07-21)
    @AppStorage("readerShowSourceLink") private var showSourceLink = true

    /// Обраний шрифт рідера — застосовується і до шапки (фідбек)
    private var nbFont: ReaderBodyFont { ReaderBodyFont(rawValue: fontRaw) ?? .inter }

    // Undo-стек блокнота (SPEC §4.5, крок 10): НЕ снапшоти, а зворотні
    // дії — із soft-delete інверсія тривіальна і не воює з ідентичністю
    // обʼєктів SwiftData. Свіжий на кожен блокнот (.id оверлея), ліміт 30
    @State private var undoStack: [(label: ReaderUndoLabel, revert: () -> Void)] = []
    @State private var keyMonitor: Any?
    private static let undoLimit = 30

    init(book: ReaderBook, reader: ReaderModel,
         onQuoteToNote: @escaping (Note) -> Void = { _ in }) {
        self.book = book
        self.reader = reader
        self.onQuoteToNote = onQuoteToNote
        _title = State(initialValue: book.title)
        _linkText = State(initialValue: book.activeSource?.url ?? "")
        _cover = State(initialValue: DecodedImageCache.image(id: book.id,
                                                             data: book.photoData))
    }

    var body: some View {
        VStack(spacing: 0) {
            photoTitleArea
            content
            footer
        }
        // Під віконцем-питанням - світлий блюр як при розгорнутому стіку.
        // САМЕ тут, до .embarOverlaySurface: фон поверхні лишається
        // суцільним, інакше крізь блокнот просвічувала б полиця
        .dialogDimmed(coverDialogOpen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .embarOverlaySurface()
        .environmentObject(voicePlayer)
        // Sheet налаштувань — скрим на весь блокнот (= вся панель)
        .embarBottomSheet(isPresented: $showingSettings) {
            ReaderSettingsSheet()
        }
        // «Прибрати фото обкладинки?» — × на камері (фідбек 2026-07-22);
        // той самий компонент, що питання видалення папки
        .overlay {
            if coverDialogOpen {
                ConfirmDeleteDialog(
                    title: "Прибрати фото обкладинки?",
                    keepLabel: "Замінити на нове",
                    purgeLabel: "Видалити фото",
                    onKeep: { coverDialogOpen = false; pickCover() },
                    onPurge: { coverDialogOpen = false; removeCover() },
                    onCancel: { coverDialogOpen = false })
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2),
                   value: coverDialogOpen)
        // Кроп фото (2026-07-22) — той самий шит, що фото нотаток;
        // пропорція бокса = пропорція самого фото (обрізаємо краї),
        // з кепом проти екстремально витягнутих скріншотів
        .embarBottomSheet(item: $cropJob) { job in
            NotePhotoCropSheet(
                image: job.image,
                aspect: min(max(job.image.size.height
                                    / max(job.image.size.width, 1), 0.45), 1.4),
                // P2.27: кеп пропорції ховав краї витягнутих фото - тепер
                // старт із цілого фото, зум обирає область
                allowsWholePhoto: true,
                onCancel: { cropJob = nil },
                onSave: { cropped in
                    job.apply(cropped)
                    cropJob = nil // фокус поверне хук anyOverlayOpen
                })
        }
        // «Теги ▾» — чекбокс-дропдаун над баром фільтрів (SPEC §4.3);
        // прозорий ловець кліків закриває його по кліку повз
        .overlay {
            if tagDropdownOpen {
                ZStack(alignment: .bottomTrailing) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { tagDropdownOpen = false }
                    tagDropdown
                        .padding(.trailing, 14)
                        .padding(.bottom, 88)
                }
            }
        }
        .onAppear {
            if reader.focusTitleOnOpen {
                // Щойно створений блокнот: назва порожня, «Новий
                // блокнот» - плейсхолдер, каретка одразу мигає в назві -
                // людина продовжує писати (фідбек 2026-09-04). Фокус -
                // НАСТУПНИМ тіком: в onAppear поле ще не у вікні, і
                // @FocusState промахувався («фокус у нікуди») - той
                // самий трюк, що в чернетці назви теми
                reader.focusTitleOnOpen = false
                awaitingFirstTitleBlur = true
                DispatchQueue.main.async { titleFocused = true }
            } else {
                // Відкритий блокнот одразу готовий до запису: клавіатура
                // в compose (SPEC §15.72в; запобіжник shouldAutoFocus у
                // compose-барі не віддає її, поки відкритий пошук)
                focusCompose()
            }
            installUndoKeyMonitor()
            prefetchEntries()
        }
        .onDisappear {
            materializePlaceholderIfUnnamed() // закрили, не назвавши
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            voicePlayer.stop() // закритий блокнот не грає
        }
        // Кореневий фікс (2026-07-07): PanelController при хованні стирає
        // first responder вікна; тут синхронізуємо SwiftUI-стан полів.
        // Назва отримує фокус по кліку і в єдиному програмному шляху -
        // щойно створений блокнот (P2.24 + фідбек 2026-09-04)
        .onReceive(NotificationCenter.default.publisher(
            for: .embarPanelDidHide)) { _ in
            titleFocused = false
            linkFocused = false
        }
        // Після закриття попапів/шитів AppKit віддає фокус першому
        // текстовому полю вікна — назві блокнота, і виділяє її всю
        // (фідбек 2026-07-22, вкотре). Правило: після будь-якої дії
        // акцент клавіатури — у полі вводу compose. ОДИН хук на похідний
        // Bool, не по копії на кожен оверлей (code review 2026-07-23:
        // саме розсипані копії й плодили фокусні баги)
        .onChange(of: anyOverlayOpen) { _, open in
            if !open { focusCompose() }
        }
    }

    /// Будь-який відкритий оверлей блокнота (нові оверлеї — додавати сюди)
    private var anyOverlayOpen: Bool {
        folderDropdownOpen || showingSettings || tagDropdownOpen
            || coverDialogOpen || cropJob != nil
    }

    /// Пішла з назви щойно створеного блокнота, нічого не набравши -
    /// плейсхолдер стає справжньою назвою (фідбек 2026-09-04). Один
    /// раз: далі порожня назва - свідомий вибір
    private func materializePlaceholderIfUnnamed() {
        guard awaitingFirstTitleBlur else { return }
        awaitingFirstTitleBlur = false
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return }
        title = String(localized: "Новий блокнот",
                       comment: "Назва-заповнювач щойно створеного блокнота рідера")
        ReaderService.setTitle(title, for: book)
    }

    /// Фокус — у поле думки/цитати (наступним тіком, коли попап/панель
    /// уже віддали key-статус)
    private func focusCompose() {
        titleFocused = false
        linkFocused = false
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .embarReaderFocusCompose,
                                            object: nil)
        }
    }

    // MARK: - Шапка: обкладинка + назва
    // Без фото — звичайний заголовок зліва; з фото — область min 190px,
    // фото фоном, назва по центру білим, знизу «туман» у колір поверхні

    @ViewBuilder private var photoTitleArea: some View {
        if let image = cover {
            titleField(onPhoto: true)
                .padding(EdgeInsets(top: 32, leading: 18, bottom: 32, trailing: 18))
                .frame(maxWidth: .infinity, minHeight: 190)
                .background(
                    Image(nsImage: image).resizable().scaledToFill()
                )
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, EmbarColors.surface],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 80)
                        .allowsHitTesting(false)
                }
        } else {
            titleField(onPhoto: false)
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
        }
        // Рядок джерела — під шапкою, на суцільному фоні (фідбек
        // 2026-07-21: на фото текст воює з картинкою в обох кольорах).
        // Тумблер у налаштуваннях рідера дозволяє його прибрати
        if showSourceLink { linkBar }
    }

    // MARK: - Link-bar джерела (фінал 2026-07-21: як у оригіналі — під
    // шапкою на суцільному фоні; на фото текст читався погано)

    private var linkBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 12))
                .foregroundStyle(EmbarColors.ink4)
            TextField("Додати посилання на джерело...", text: $linkText)
                .textFieldStyle(.plain)
                .font(nbFont.font(12))
                .foregroundStyle(EmbarColors.ink3)
                .focused($linkFocused)
                .onSubmit { linkFocused = false }
            coverButton
        }
        .padding(EdgeInsets(top: 7, leading: 16, bottom: 9, trailing: 16))
        .overlay(alignment: .bottom) {
            Rectangle().fill(.black.opacity(0.06)).frame(height: 1)
        }
        // Зберігаємо на втраті фокуса (прототип onblur; Enter → blur)
        .onChange(of: linkFocused) { _, focused in
            if !focused { saveLink() }
        }
    }

    private var coverButton: some View {
        NbActionButton(icon: "camera", size: 12.5, action: pickCover)
            // ×-бейдж на ховері (той самий, що на чіпах папок) — шлях
            // ПРИБРАТИ обкладинку: раніше фото можна було лише замінити
            // (фідбек 2026-07-22)
            .overlay(alignment: .topTrailing) {
                if coverHovering, cover != nil {
                    Button {
                        coverDialogOpen = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(EmbarColors.danger))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 3, y: -3)
                }
            }
            .onHover { coverHovering = $0 }
    }

    /// Той самий сендбокс-механізм, що фото нотаток (M4):
    /// user-selected read-only, стиснена копія живе в базі
    private func pickCover() {
        NoteImageStore.pickImages(count: 1) { urls in
            focusCompose() // NSOpenPanel теж краде first responder
            guard let url = urls.first,
                  let image = NSImage(contentsOf: url),
                  let data = NoteImageStore.downscaledJPEG(image) else { return }
            ReaderService.setCover(data, for: book)
            cover = DecodedImageCache.image(id: book.id, data: data)
        }
    }

    private func removeCover() {
        let old = book.photoData
        ReaderService.setCover(nil, for: book)
        cover = nil
        pushUndo(.deleteCover) {
            ReaderService.setCover(old, for: book)
            cover = DecodedImageCache.image(id: book.id, data: old)
        }
    }

    private func titleField(onPhoto: Bool) -> some View {
        // Плейсхолдер на фото — напівпрозорий білий (фідбек), без фото — блідий
        TextField("", text: $title,
                  // Плейсхолдер = майбутня назва за замовчуванням: якщо
                  // людина піде, не назвавши, саме це стане назвою
                  prompt: Text("Новий блокнот")
                      .foregroundStyle(onPhoto ? .white.opacity(0.6)
                                               : EmbarColors.ink4),
                  axis: .vertical)
            .textFieldStyle(.plain)
            .font(nbFont.font(28, weight: .light))
            .tracking(-0.5)
            .lineLimit(1...3)
            .multilineTextAlignment(onPhoto ? .center : .leading)
            .foregroundStyle(onPhoto ? .white : EmbarColors.ink)
            .shadow(color: onPhoto ? .black.opacity(0.45) : .clear, radius: 5, y: 1)
            .focused($titleFocused)
            // Enter фіксує назву: знімаємо фокус (інакше macOS лишає поле
            // активним і виділяє весь текст - фідбек після кроку 3) і
            // повертаємо клавіатуру в compose - правило «після будь-якої
            // дії акцент у полі вводу»
            .onSubmit {
                titleFocused = false
                focusCompose()
            }
            .onChange(of: titleFocused) { _, focused in
                if !focused { materializePlaceholderIfUnnamed() }
            }
            .onChange(of: title) { _, newValue in
                // Прототип зберігає oninput; бамп updatedAt тут ок —
                // полиця за оверлеєм, перерисовка непомітна
                ReaderService.setTitle(newValue, for: book)
            }
    }

    private func saveLink() {
        ReaderService.setSource(linkText, for: book, in: context)
        // Показуємо нормалізований URL (видно, що https:// додався)
        linkText = book.activeSource?.url ?? ""
    }

    // MARK: - Стрічка записів (SPEC §4.3): нові зверху, дата-роздільники

    /// Масовий префетч записів блокнота РАЗОМ із хайлайтами й темами
    /// (перф-фікс 2026-08-16): без нього на «холодній» базі кожен рядок,
    /// що вʼїжджає у вʼюпорт, фолтив свій запис і його relationships
    /// окремими SQL-запитами — скрол стрічки на тисячах записів заїдав
    /// у рази сильніше, ніж одразу після сідінгу. Один запит гріє все.
    private func prefetchEntries() {
        let bookID = book.id
        var descriptor = FetchDescriptor<ReaderEntry>(
            predicate: #Predicate { $0.book?.id == bookID && $0.deletedAt == nil })
        descriptor.relationshipKeyPathsForPrefetching = [\.highlights, \.theme]
        _ = try? context.fetch(descriptor)
    }

    private var liveEntries: [ReaderEntry] {
        (book.entries ?? []).filter { $0.deletedAt == nil }
    }

    /// Фільтр типу/обраного + OR-фільтр тегів + пошук (текст/автор/
    /// сторінка або дата-запит #6) — прототип renderReaderEntries
    private var filteredEntries: [ReaderEntry] {
        var result = liveEntries
        if typeFilter == "fav" {
            result = result.filter(\.favorite)
        } else if let type = typeFilter {
            result = result.filter { $0.type == type }
        }
        if !tagFilter.isEmpty {
            result = result.filter { entry in
                !tagFilter.isDisjoint(with: ReaderTags.matches(in: entry.text).map(\.name))
            }
        }
        let query = reader.notebookSearchText
            .trimmingCharacters(in: .whitespaces).lowercased()
        if reader.notebookSearchOpen, !query.isEmpty {
            if let day = ReaderDateQuery.dayInterval(from: query) {
                // Запит-дата: «вчора», «05.07», «5 лип» → записи того дня
                result = result.filter { day.contains($0.createdAt) }
            } else {
                // range(of:.caseInsensitive) замість lowercased().contains:
                // без алокації копії всього тексту на кожен запис
                result = result.filter { entry in
                    entry.text.range(of: query, options: .caseInsensitive) != nil
                        || (entry.author ?? "").range(of: query, options: .caseInsensitive) != nil
                }
            }
        }
        return result
    }

    // MARK: - Плоска стрічка (фідбек 2026-07-22): теми — не окрема секція,
    // а інлайн-розділювачі «> назва ———» прямо в хронологічному потоці.
    // Розділювач стоїть перед НАЙНОВІШИМ записом свого русла, тож коли
    // тема завершена і зверху зʼявляються новіші записи — він природно
    // «спускається» вниз. Чипів теми на записах більше немає.

    private enum FeedItem: Identifiable {
        case day(Date, String)
        /// Розділювач теми — рівно ОДИН на тему (русло консолідоване)
        case theme(ReaderTheme)
        /// Ввід назви нової теми («> |» з курсором)
        case draft
        case entry(ReaderEntry)
        /// Кінець русла теми: маленька центрована риска під найстаршим
        /// записом — видно, де тема закінчилась (фідбек 2026-07-22)
        case themeEnd(UUID)

        var id: AnyHashable {
            switch self {
            case .day(let day, _): day
            case .theme(let theme): "theme-\(theme.id)"
            case .draft: "theme-draft"
            case .entry(let entry): entry.id
            case .themeEnd(let id): "theme-end-\(id)"
            }
        }
    }

    /// Стрічка з темами-розділами (фідбек 2026-07-28): тема — ОДНЕ
    /// консолідоване русло, заякорене своїм найстаршим видимим записом.
    /// Продовжена тема приймає нові записи ПІД свій розділювач (нові
    /// зверху всередині русла) і НЕ вистрибує нагору — новіший загальний
    /// текст лишається над нею. Дата-рядки йдуть від якорів блоків
    /// (❗ ідентичність — ДАТА, не label: «5 лип» різних років колізували
    /// б, code review M5 #1); згорнута тема ховає записи, розділювач
    /// лишається.
    /// (фільтровані записи приходять параметром: content рахує їх ОДИН
    /// раз за рендер і для стрічки, і для onChange-перевірки порожнечі —
    /// перф 2026-08-16)
    private func feedItems(_ filteredEntries: [ReaderEntry]) -> [FeedItem] {
        #if DEBUG
        // Зонд пісочниці: поза -SandboxPerfProbe це один Bool-чек
        let probeStart = PerfProbe.isActive ? CFAbsoluteTimeGetCurrent() : 0
        defer {
            if PerfProbe.isActive {
                PerfProbe.shared.record("reader.feedItems(\(filteredEntries.count) записів)",
                                        seconds: CFAbsoluteTimeGetCurrent() - probeStart)
            }
        }
        #endif
        let calendar = Calendar.current
        struct Run { let theme: ReaderTheme; var entries: [ReaderEntry] }
        var runIndex: [UUID: Int] = [:]
        var runs: [Run] = []
        var singles: [ReaderEntry] = []
        for entry in filteredEntries {
            if let theme = entry.theme, theme.deletedAt == nil {
                if let idx = runIndex[theme.id] {
                    runs[idx].entries.append(entry)
                } else {
                    runIndex[theme.id] = runs.count
                    runs.append(Run(theme: theme, entries: [entry]))
                }
            } else {
                singles.append(entry)
            }
        }

        // Блок = одиночний запис або ціле русло; сортування нові → старі
        // за якорем (у русла — найстарший запис: там воно «народилося»,
        // і саме там лишається, коли зверху пишеться новіший текст)
        var blocks: [(anchor: Date, single: ReaderEntry?, run: Run?)] =
            singles.map { ($0.createdAt, $0, nil) }
        for var run in runs {
            run.entries.sort { $0.createdAt > $1.createdAt }
            blocks.append((run.entries.last?.createdAt ?? .distantPast,
                           nil, run))
        }
        blocks.sort { $0.anchor > $1.anchor }

        var items: [FeedItem] = []
        var currentDay: Date?
        func dayHeader(_ date: Date) {
            let day = calendar.startOfDay(for: date)
            guard day != currentDay else { return }
            items.append(.day(day, ReaderDateFormat.dayLabel(date)))
            currentDay = day
        }

        // Чернетка назви або активна тема без видимих записів — під
        // «сьогодні», ще до першого запису. ❗ НЕ при фільтрі/пошуку
        // (code review 2026-07-23: синтетика прикидалася результатами)
        let active = book.activeTheme
        let activeHasVisible = active.map { runIndex[$0.id] != nil } ?? false
        if creatingTheme {
            dayHeader(.now)
            items.append(.draft)
        } else if let active, !activeHasVisible, !feedFiltering {
            dayHeader(.now)
            items.append(.theme(active))
            if !blocks.isEmpty {
                // Під порожнім розділювачем підуть ЧУЖІ записи — риска
                // одразу показує, що тема поки без записів
                items.append(.themeEnd(active.id))
            }
        }

        for block in blocks {
            if let entry = block.single {
                dayHeader(entry.createdAt)
                items.append(.entry(entry))
            } else if let run = block.run {
                dayHeader(block.anchor)
                items.append(.theme(run.theme))
                if !collapsedThemes.contains(run.theme.id) {
                    for entry in run.entries { items.append(.entry(entry)) }
                    items.append(.themeEnd(run.theme.id))
                }
            }
        }
        return items
    }

    /// Стрічку зараз звужує фільтр типу/тегів або непорожній пошук
    private var feedFiltering: Bool {
        if typeFilter != nil || !tagFilter.isEmpty { return true }
        let query = reader.notebookSearchText.trimmingCharacters(in: .whitespaces)
        return reader.notebookSearchOpen && !query.isEmpty
    }

    /// Один рядок запису — спільний для секції теми і датних груп
    private func entryRow(_ entry: ReaderEntry) -> some View {
        ReaderEntryRow(
            entry: entry,
            onEdit: { editEntry(entry, newText: $0) },
            onDelete: { deleteEntry(entry) },
            onToggleFav: { toggleFavorite(entry) },
            recentNotes: recentNotes,
            onQuote: { performQuote(entry, into: $0) },
            penActive: penActive,
            onHighlight: { addHighlight($0, to: entry) },
            onCropPhoto: entry.photoData == nil ? nil : {
                guard let image = DecodedImageCache.image(
                    id: entry.id, data: entry.photoData) else { return }
                cropJob = CropJob(image: image) { cropped in
                    applyEntryCrop(entry, cropped: cropped)
                }
            },
            // Налаштування — вниз параметрами, щоб рядки не тримали
            // власних спостерігачів UserDefaults (перф 2026-08-16)
            hashtagsEnabled: hashtagsEnabled,
            fontRaw: fontRaw
        )
        .id(entry.id)
        // Спалах після goToReaderEntry (qnLift)
        .offset(y: flashEntryID == entry.id ? -5 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.5),
                   value: flashEntryID == entry.id)
    }

    /// Один елемент плоскої стрічки. Розділювач одразу під дата-рядком
    /// притискається (tight) — подвійного повітря там не треба
    @ViewBuilder private func feedRow(_ item: FeedItem, index: Int,
                                      items: [FeedItem]) -> some View {
        switch item {
        case .day(_, let label):
            ReaderDayDivider(label: label, isFirst: index == 0)
        case .theme(let theme):
            ReaderThemeDivider(
                name: theme.name,
                collapsed: collapsedThemes.contains(theme.id),
                tight: afterDayHeader(index, in: items),
                font: themeDividerFont,
                onToggle: { toggleCollapse(theme) },
                onToggleAll: { toggleCollapseAll(from: theme) },
                onRename: { ReaderService.renameTheme(theme, to: $0) },
                onActivate: { toggleThemeActive(theme) })
        case .draft:
            themeDraftRow
                .padding(.top, afterDayHeader(index, in: items) ? 2 : 14)
        case .entry(let entry):
            entryRow(entry)
        case .themeEnd:
            // Коротка центрована риска — межа «це ще тема / це вже ні»
            // (тон — як лінії розділювача)
            HStack {
                Spacer(minLength: 0)
                Rectangle().fill(ReaderThemeDivider.lineTint)
                    .frame(width: 56, height: 1)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    private func afterDayHeader(_ index: Int, in items: [FeedItem]) -> Bool {
        guard index > 0 else { return true }
        if case .day = items[index - 1] { return true }
        return false
    }

    // MARK: - Теми: чернетка назви + згортання (фідбек 2026-07-22)

    /// Шрифт розділювачів тем слідує шрифту блокнота (фідбек 2026-07-22):
    /// Inter лишає Fraunces italic (характерний момент рідера), серифи —
    /// курсивом власним шрифтом, mono — прямий mono
    private var themeDividerFont: Font {
        switch nbFont {
        case .inter, .serif: return .emDisplay(15, italic: true)
        case .charter: return nbFont.font(15).italic()
        case .mono: return nbFont.font(15)
        }
    }

    /// Курсор мигає одразу — назва набирається по центру між лініями,
    /// як виглядатиме готовий розділювач; Enter створює тему (і повертає
    /// клавіатуру в compose), Esc скасовує, клік повз (blur) — зберегти
    private var themeDraftRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 7))
                .foregroundStyle(EmbarColors.ink3)
                .frame(width: 16, height: 16)
            Rectangle().fill(ReaderThemeDivider.lineTint).frame(height: 1)
            ThemeNameField(text: $themeDraftName, font: themeDividerFont,
                           focus: $themeDraftFocused,
                           onCommit: { commitThemeDraft(thenFocusCompose: true) },
                           onCancel: cancelThemeDraft)
                .onAppear { themeDraftFocused = true }
                .onChange(of: themeDraftFocused) { _, focused in
                    // Через тік: клік по кнопці «Тема» спершу blur-ить
                    // поле — даємо кнопці шанс скасувати чернетку, інакше
                    // blur створював би тему, яку кнопка тут же завершує
                    // (code review 2026-07-23)
                    if !focused, creatingTheme {
                        DispatchQueue.main.async {
                            if creatingTheme { commitThemeDraft() }
                        }
                    }
                }
            Rectangle().fill(ReaderThemeDivider.lineTint).frame(height: 1)
        }
        .padding(.bottom, 12)
    }

    /// Кнопка «Тема» в compose — тогл (фідбек 2026-07-22): нема активної →
    /// ввід назви у стрічці; є активна → завершити (розділювач лишається
    /// і «спускається» під новішими записами); чернетка відкрита → скасувати
    private func handleThemeToggle() {
        if creatingTheme {
            // Скасування — ПЕРШИМ: клік по кнопці спершу blur-ить поле
            // назви, і без цього порядку blur встигав би створити тему
            // (code review 2026-07-23)
            cancelThemeDraft()
            focusCompose() // P2.24: клавіатура повертається в compose
        } else if let active = book.activeTheme {
            let hasEntries = (active.entries ?? [])
                .contains { $0.deletedAt == nil }
            if hasEntries {
                ReaderService.finishActiveTheme(in: book)
            } else {
                // Завершення порожньої теми = скасування: візуально
                // однаково (без записів русло не рендериться), а в базі
                // не лишається сміття — і гонка blur→click безпечна
                ReaderService.discardTheme(active)
            }
            // P2.24: ця гілка не перехоплювала фокус узагалі - клік
            // сиротив first responder, і AppKit віддавав його назві
            // блокнота (як усюди, страховкою; джерело лікують guard
            // назви і EmbarFieldEditor)
            focusCompose()
        } else {
            creatingTheme = true
            // ❗ Клік по кнопці знімає first responder з compose, і AppKit
            // віддає його ПЕРШОМУ текстовому полю вікна — назві блокнота
            // (виділяє її всю; фідбек 2026-07-22). Перехоплюємо фокус на
            // наступному тіку, коли поле назви теми вже існує
            titleFocused = false
            linkFocused = false
            DispatchQueue.main.async { themeDraftFocused = true }
        }
    }

    /// thenFocusCompose — лише для Enter: клавіатура одразу повертається
    /// в поле думки (фідбек 2026-07-22); blur лишає фокус там, куди
    /// користувач клікнув
    /// Клік по назві теми в розділювачі (фідбек 2026-07-28): продовжити
    /// завершену тему — вона знову активна (чип «Тема» показує назву) і
    /// нові записи йдуть у неї; повторний клік (або чип) зупиняє.
    /// Працює з будь-якою темою, не лише останньою — інваріант «одна
    /// активна» тримає ReaderService.activate
    private func toggleThemeActive(_ theme: ReaderTheme) {
        if theme.isActive {
            ReaderService.finishActiveTheme(in: book)
        } else {
            ReaderService.activate(theme, in: book)
        }
        focusCompose() // клік по тексту віддав би фокус назві блокнота
    }

    private func commitThemeDraft(thenFocusCompose: Bool = false) {
        guard creatingTheme else { return }
        let name = themeDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Режим читання: чернетка назви лишається в полі
        if !name.isEmpty, !ProGate.allowCreate() { return }
        creatingTheme = false
        themeDraftName = ""
        if !name.isEmpty {
            // Тема стає активною одразу; зміна стрічки миттєва (§7.2-A)
            ReaderService.createTheme(name: name, in: book, context: context)
        }
        if thenFocusCompose { focusCompose() }
    }

    private func cancelThemeDraft() {
        creatingTheme = false
        themeDraftName = ""
    }

    /// Згортання — рух поверхні (як шторка/шит), анімується — виняток
    /// §7.2-A; різке зникнення записів читалось як глюк (фідбек 2026-07-22)
    private static let collapseAnim =
        Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.28)

    /// Клік по трикутнику — згорнути/розгорнути одну тему (записи
    /// ховаються, розділювач лишається)
    private func toggleCollapse(_ theme: ReaderTheme) {
        withAnimation(Self.collapseAnim) {
            if collapsedThemes.contains(theme.id) {
                collapsedThemes.remove(theme.id)
            } else {
                collapsedThemes.insert(theme.id)
            }
        }
    }

    /// Подвійний клік — усі теми блокнота разом: клікнута була згорнута →
    /// розгорнути всі, інакше згорнути всі (фідбек 2026-07-22)
    private func toggleCollapseAll(from theme: ReaderTheme) {
        withAnimation(Self.collapseAnim) {
            if collapsedThemes.contains(theme.id) {
                collapsedThemes.removeAll()
            } else {
                let live = (book.themes ?? []).filter { $0.deletedAt == nil }
                collapsedThemes = Set(live.map(\.id))
            }
        }
    }

    private var content: some View {
        let filtered = filteredEntries
        let items = feedItems(filtered)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Відступ під compose — елемент стрічки (не padding!):
                    // scrollTo("top") вирівнює ЙОГО по верху вʼюпорта, тож
                    // перший рядок завжди рівно під склом — і при відкритті,
                    // і після кожного нового запису (фідбек 2026-07-21:
                    // записи підскакували ЗА поле вводу)
                    // +25 — та сама відстань, що між полем і стіками
                    // (72 − 61 + 14 внутрішніх стіни; фідбек 2026-07-21)
                    Color.clear.frame(height: composeHeight + 25).id("top")
                    if items.isEmpty {
                        if liveEntries.isEmpty {
                            EmptyStateText(line1: "Нотуй, поки читаєш.",
                                           line2: "Все залишиться тут.")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 100)
                        } else if reader.notebookSearchOpen,
                                  !reader.notebookSearchText.isEmpty {
                            // Порожній результат пошуку (прототип)
                            Text("Нічого не знайдено.")
                                .font(.emUI(13))
                                .foregroundStyle(EmbarColors.ink3)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else {
                            // Перетин фільтрів порожній (тип+тег, кожен
                            // окремо непорожній — sanitize його не скидає):
                            // нейтральний рядок, не голе полотно
                            // (code review M5 #3)
                            Text("Тут нічого немає.")
                                .font(.emUI(13))
                                .foregroundStyle(EmbarColors.ink3)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                            feedRow(pair.element, index: pair.offset, items: items)
                        }
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 48,
                                    trailing: 16))
            }
            .scrollIndicators(.hidden)
            // Закріплений compose (2026-07-21, «як у стіках»): записи
            // скролять під скло і розчиняються; над compose — чисто,
            // суцільний колір панелі до його верхнього краю, далі fade
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(EmbarColors.surface).frame(height: 8)
                    LinearGradient(colors: [EmbarColors.surface,
                                            EmbarColors.surface.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                composeBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ComposeHeightKey.self,
                                               value: g.size.height)
                    })
            }
            .onPreferenceChange(ComposeHeightKey.self) {
                #if DEBUG
                if EmbarDefaults.store.bool(forKey: "GlassShotOpenBook") {
                    NSLog("GlassLab composeHeight: %.1f", $0)
                }
                #endif
                // 0 — ще не виміряно (перший прохід): лишаємо оцінку
                if $0 > 0 { composeHeight = $0 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: (book.entries ?? []).count) { _, _ in
                // Свіже — зверху (прототип); але запис у продовжену тему
                // падає ПІД її розділювач десь у стрічці (фідбек
                // 2026-07-28) — скролимо до розділювача, 0.16 висоти
                // вʼюпорта ≈ одразу під левітуючим compose
                if let active = book.activeTheme {
                    proxy.scrollTo("theme-\(active.id)",
                                   anchor: UnitPoint(x: 0.5, y: 0.16))
                } else {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
            .onChange(of: creatingTheme) { _, drafting in
                // Чернетка назви живе під «сьогодні» — показати її
                if drafting { proxy.scrollTo("top", anchor: .top) }
            }
            // goToReaderEntry: доскролити до запису і підсвітити спалахом
            .onAppear {
                guard let target = reader.pendingFlashEntryID else { return }
                reader.pendingFlashEntryID = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation { proxy.scrollTo(target, anchor: .center) }
                    flashEntryID = target
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        flashEntryID = nil
                    }
                }
            }
            // Фільтри перемикаються миттєво: withAnimation морфа чіпів
            // не має рухати стрічку (§7.2-A)
            .animation(nil, value: typeFilter)
            .animation(nil, value: tagFilter)
            // Спорожнілий фільтр скидаємо (замість порожніх текстів)
            .onChange(of: filtered.isEmpty) { _, isEmpty in
                if isEmpty { sanitizeFilters() }
            }
            // Вимкнули хештеги/типи в налаштуваннях — активні фільтри
            // по них втрачають сенс
            .onChange(of: hashtagsEnabled) { _, enabled in
                if !enabled {
                    tagFilter.removeAll()
                    tagDropdownOpen = false
                }
            }
            .onChange(of: extraTypesEnabled) { _, enabled in
                if !enabled,
                   typeFilter == ReaderEntryKind.question.rawValue
                    || typeFilter == ReaderEntryKind.insight.rawValue {
                    typeFilter = nil
                }
            }
            // Плаваючий бар фільтрів над футером (прототип .reader-folder-bar
            // у блокноті: прозорий контейнер, чіпи — окремі пігулки)
            .overlay(alignment: .bottom) {
                // Бар видно і при відкритому пошуку в порожньому блокноті:
                // інакше Cmd+F вмикав невидиме поле без способу закрити
                // (code review M5 #4)
                if !liveEntries.isEmpty || reader.notebookSearchOpen { filterBar }
            }
        }
    }

    // MARK: - Фільтри: Всі / Думки / Цитати / Обрані + «Теги ▾» (SPEC §4.3)

    /// Типи з лічильниками по ВСІХ живих записах (прототип countFor);
    /// чіп показується лише коли count > 0 (крім «Всі»)
    private var typeMeta: [(type: String?, label: String)] {
        var meta: [(type: String?, label: String)] = [
            (nil, String(localized: "Всі", comment: "Чіп фільтра типів записів рідера")),
            (ReaderEntryKind.thought.rawValue, String(localized: "Думки", comment: "Чіп фільтра типів записів рідера")),
            (ReaderEntryKind.quote.rawValue, String(localized: "Цитати", comment: "Чіп фільтра типів записів рідера")),
        ]
        if extraTypesEnabled {
            // Власний ключ: як ФІЛЬТР це множина («Questions»), а та сама
            // «Питання» як ТИП запису в композері — однина («Question»)
            meta.append((ReaderEntryKind.question.rawValue,
                         String(localized: "filter.reader.questions",
                                defaultValue: "Питання",
                                comment: "Чіп фільтра типів записів рідера (множина)")))
            meta.append((ReaderEntryKind.insight.rawValue, String(localized: "Інсайти", comment: "Чіп фільтра типів записів рідера")))
        }
        meta.append(("fav", String(localized: "Обрані", comment: "Чіп фільтра записів рідера — обране")))
        return meta
    }

    private func countFor(_ type: String?) -> Int {
        guard let type else { return liveEntries.count }
        if type == "fav" { return liveEntries.filter(\.favorite).count }
        return liveEntries.filter { $0.type == type }.count
    }

    /// Теги видно лише з увімкненими хештегами (SPEC §4.4)
    private var bookTags: [String] {
        guard hashtagsEnabled else { return [] }
        return ReaderTags.uniqueTags(in: liveEntries.map(\.text))
    }

    private var filterBar: some View {
        // Анатомія бара — як NotesFolderBar/ReaderFolderBar (консистентність):
        // лупа перша (прототип renderReaderTypeChips), поле замість чіпів
        HStack(alignment: .bottom, spacing: 5) {
            nbSearchToggle
            if reader.notebookSearchOpen {
                nbSearchField
            } else {
                chipRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            LinearGradient(
                colors: [EmbarColors.surface.opacity(0), EmbarColors.surface.opacity(0.92)],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
        .onChange(of: reader.notebookSearchOpen) { _, open in
            if open { focusSearchField() }
        }
    }

    /// Фокус у поле пошуку — явно і наступним тіком (фідбек 2026-07-23):
    /// клік по лупі знімає first responder з compose, AppKit тут же
    /// віддає його назві блокнота і виділяє її; ставити фокус у ту саму
    /// мить, коли поле лише зʼявляється, — ненадійно
    private func focusSearchField() {
        titleFocused = false
        linkFocused = false
        DispatchQueue.main.async { nbSearchFocus = true }
    }

    private var nbSearchToggle: some View {
        Button {
            reader.notebookSearchOpen.toggle()
            if reader.notebookSearchOpen { focusSearchField() }
            else { reader.notebookSearchText = "" }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(reader.notebookSearchOpen ? .white : EmbarColors.ink2)
                .frame(width: 28, height: 26)
                .background(Capsule().fill(reader.notebookSearchOpen
                                           ? EmbarColors.ink
                                           : EmbarColors.surface.opacity(0.96)))
        }
        .buttonStyle(.plain)
    }

    private var nbSearchField: some View {
        TextField("", text: $reader.notebookSearchText,
                  prompt: Text("Знайти в записах... або дата (18.07)")
                      .foregroundStyle(EmbarColors.ink4))
            .textFieldStyle(.plain)
            .font(.emUI(12))
            .foregroundStyle(EmbarColors.ink)
            .focused($nbSearchFocus)
            .padding(.horizontal, 14).padding(.vertical, 5)
            .searchPillBackground()
            .onExitCommand {
                reader.notebookSearchOpen = false
                reader.notebookSearchText = ""
            }
    }

    private var chipRow: some View {
        // ScrollView БЕЗ анімації на контейнері — морф їде через
        // withAnimation у onSelect (matchedGeometry в ScrollView заїдає)
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(typeMeta, id: \.label) { meta in
                    let count = countFor(meta.type)
                    if meta.type == nil || count > 0 {
                        FolderChip(label: meta.label, count: count,
                                   isActive: typeFilter == meta.type,
                                   morphNS: typeChipNS) {
                            selectTypeFilter(meta.type)
                        }
                    }
                }
                if !bookTags.isEmpty {
                    FolderChip(label: tagFilter.isEmpty
                               ? String(localized: "Теги ▾",
                                        comment: "Чіп-дропдаун фільтра за тегами")
                               : String(localized: "Теги · \(tagFilter.count) ▾",
                                        comment: "Чіп фільтра за тегами зі скільки обрано"),
                               isActive: !tagFilter.isEmpty) {
                        tagDropdownOpen.toggle()
                    }
                }
            }
            // Лише верхній відступ: нижній зсував чіпи вище за лупу
            // при bottom-вирівнюванні бара (фідбек 2026-07-07)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func selectTypeFilter(_ type: String?) {
        guard type != typeFilter else { return }
        // Морф активного чіпа — виняток §7.2-A (як switchFolder у нотатках);
        // стрічка лишається миттєвою через .animation(nil) на списку
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            typeFilter = type
        }
    }

    /// Фільтр без результату не показує порожніх текстів — він просто
    /// неможливий: чіп без записів зникає, а активний фільтр, що
    /// спорожнів, скидається на «Всі» (фідбек 2026-07-07)
    private func sanitizeFilters() {
        tagFilter.formIntersection(bookTags)
        if let type = typeFilter, countFor(type) == 0 { typeFilter = nil }
    }

    /// Дропдаун тегів (прототип .reader-tag-dropdown): білий, 200pt,
    /// чекбокси-OR, футер «Обрано: N / очистити». Висота — за кількістю
    /// тегів (фідбек), скрол лише коли тегів справді багато
    private var tagDropdown: some View {
        let tags = bookTags
        let list = VStack(alignment: .leading, spacing: 0) {
            ForEach(tags, id: \.self) { tag in
                tagOption(tag)
            }
        }
        return VStack(alignment: .leading, spacing: 0) {
            if tags.count > 8 {
                ScrollView { list }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: 240)
            } else {
                list
            }
            if !tagFilter.isEmpty {
                Rectangle().fill(.black.opacity(0.06)).frame(height: 1)
                HStack {
                    Text("Обрано: \(tagFilter.count)")
                        .font(.emUI(11))
                        .foregroundStyle(EmbarColors.ink3)
                    Spacer()
                    Button("очистити") { tagFilter.removeAll() }
                        .buttonStyle(.plain)
                        .font(.emUI(11, weight: .medium))
                        .foregroundStyle(EmbarColors.ink2)
                }
                .padding(EdgeInsets(top: 7, leading: 12, bottom: 8, trailing: 12))
            }
        }
        .padding(.vertical, 6)
        .frame(width: 200)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }

    private func tagOption(_ tag: String) -> some View {
        let selected = tagFilter.contains(tag)
        return Button {
            // OR-перемикання — миттєво, дропдаун лишається відкритим
            if selected { tagFilter.remove(tag) } else { tagFilter.insert(tag) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(EmbarColors.ink)
                    .opacity(selected ? 1 : 0)
                HashtagChip(name: tag)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Композер (докований знизу — SPEC §4.2)

    private var composeBar: some View {
        ReaderComposeBar(
            onSubmit: { kind, text, author, photoData in
                // Поява запису — рух поверхні, анімується (§7.2-A)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    let entry = ReaderService.addEntry(kind: kind, text: text,
                                                       author: author,
                                                       photoData: photoData,
                                                       to: book, in: context)
                    pushUndo(.addEntry) {
                        ReaderService.softDeleteEntry(entry)
                    }
                }
            },
            penActive: $penActive,
            penMode: $penMode,
            penColor: $penColor,
            shouldAutoFocus: { !showingSettings && !reader.notebookSearchOpen
                && !tagDropdownOpen && !folderDropdownOpen && !creatingTheme },
            activeThemeName: book.activeTheme?.name,
            themeDrafting: creatingTheme,
            onThemeToggle: handleThemeToggle,
            onCropPhoto: { image, apply in
                cropJob = CropJob(image: image, apply: apply)
            },
            // P2.26: кроп превʼю - єдиний кроп-шлях без ⌘Z; композер
            // реєструє відкат у спільному стеку блокнота
            onRegisterUndo: { label, revert in pushUndo(label, revert: revert) },
            onVoice: { data, duration in
                // Голосовий запис (крок 12): текст порожній — валідно
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    let entry = ReaderService.addEntry(
                        kind: .voice, text: "",
                        audioData: data, audioDuration: duration,
                        to: book, in: context)
                    pushUndo(.voiceEntry) {
                        ReaderService.softDeleteEntry(entry)
                    }
                }
            })
        // Bottom-відступ прибрано (2026-07-21): compose тепер левітує
        // overlay-ем, повітря до стрічки дає top-padding скролу
    }

    /// Висота левітуючого compose → верхній відступ стрічки.
    /// ❗ max-агрегація з дефолтом 0: піддерева без preference дають
    /// default, і «останній виграє» затирав реальний вимір (баг
    /// 2026-07-21 — стрічка висіла на 120 замість ~97)
    private struct ComposeHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    /// Виділення в пен-режимі → новий хайлайт (миттєво, §7.2-A).
    /// Якщо виділене ВЖЕ повністю покрите тим самим інструментом
    /// (режим + колір) — це стирання: повторний прохід прибирає
    /// покриття (фідбек 2026-07-22, інакше хайлайт не забрати)
    private func addHighlight(_ range: NSRange, to entry: ReaderEntry) {
        let span = HighlightSpan(start: range.location,
                                 end: range.location + range.length,
                                 colorName: penColor, mode: penMode)
        guard ReaderHighlightRender.isValid(
            span, length: (entry.text as NSString).length) else { return }
        let matching = (entry.highlights ?? []).filter {
            $0.deletedAt == nil && $0.mode == penMode && $0.colorName == penColor
        }
        if fullyCovered(span, by: matching) {
            let erased = ReaderService.eraseHighlights(
                start: span.start, end: span.end,
                colorName: penColor, mode: penMode, from: entry, in: context)
            pushUndo(penMode == "underline" ? .removeUnderline : .removeHighlight) {
                for h in erased.removed { ReaderService.undoDeleteHighlight(h) }
                for h in erased.added { ReaderService.softDeleteHighlight(h) }
            }
            return
        }
        // Режим читання: НОВЕ виділення заборонене; стирання (гілка вище,
        // разом із її механічними split-вставками) лишається дозволеним
        guard ProGate.allowCreate() else { return }
        let highlight = ReaderService.addHighlight(
            start: span.start, end: span.end,
            colorName: penColor, mode: penMode, to: entry, in: context)
        pushUndo(penMode == "underline" ? .underline : .highlight) {
            ReaderService.softDeleteHighlight(highlight)
        }
    }

    /// Чи покривають діапазони (одного інструмента) виділення без дірок
    private func fullyCovered(_ span: HighlightSpan,
                              by highlights: [Highlight]) -> Bool {
        var pos = span.start
        for h in highlights.sorted(by: { $0.start < $1.start }) {
            if h.start > pos { break } // дірка перед наступним шматком
            pos = max(pos, h.end)
            if pos >= span.end { return true }
        }
        return pos >= span.end
    }

    /// Обрізане фото запису: перезапис + undo зі старими даними
    private func applyEntryCrop(_ entry: ReaderEntry, cropped: NSImage) {
        guard let data = NoteImageStore.downscaledJPEG(cropped) else { return }
        let old = entry.photoData
        ReaderService.setPhoto(data, for: entry)
        pushUndo(.cropPhoto) { ReaderService.setPhoto(old, for: entry) }
    }

    // MARK: - Цитата → нотатка (SPEC §12.3, крок 16)

    private func performQuote(_ entry: ReaderEntry, into target: Note?) {
        let isNew = target == nil
        // Режим читання: цитата в НОВУ нотатку - створення; допис у
        // наявну - редагування наявного, дозволено
        if isNew, !ProGate.allowCreate() { return }
        let note = ReaderService.quoteToNote(entry: entry, book: book,
                                             into: target, in: context)
        let title = note.title.isEmpty ? "Без назви" : note.title
        toasts.showMini(isNew ? "Створено нотатку з цитатою"
                              : "Додано в «\(title.truncatedChip())»")
        onQuoteToNote(note)
    }

    private func editEntry(_ entry: ReaderEntry, newText: String) {
        let oldText = entry.text
        // Знімок хайлайтів: adjustHighlights обрізає/ховає діапазони, і
        // відкат самим editText(oldText) їх не повертав би
        // (code review 2026-07-23)
        let snapshot = ReaderService.highlightSnapshot(of: entry)
        ReaderService.editText(newText, of: entry)
        pushUndo(.editEntry) {
            ReaderService.restoreTextEdit(oldText, snapshot: snapshot, of: entry)
        }
    }

    private func toggleFavorite(_ entry: ReaderEntry) {
        ReaderService.toggleFavorite(entry)
        pushUndo(entry.favorite ? .addFavorite : .removeFavorite) {
            ReaderService.toggleFavorite(entry)
        }
    }

    // MARK: - Футер: назад · налаштування · видалити

    private var footer: some View {
        HStack {
            BackButton { reader.close() }
            Spacer()
            HStack(spacing: 6) {
                folderButton
                NbActionButton(icon: "slider.vertical.3", size: 14) {
                    showingSettings = true
                }
                NbActionButton(icon: "trash", size: 14, action: deleteBook)
            }
        }
        // БЕЗ розділювальної лінії (2026-08-09): сірі горизонтальні
        // проділи прибрані по всьому застосунку, а тут вона ще й зайва —
        // записи й так розчиняються у фейді під баром фільтрів.
        // У прототипі цієї рамки немає: там ця смуга взагалі вгорі
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 14, trailing: 14))
    }

    // MARK: - Папка блокнота — 1:1 як у редакторі нотаток (консистентність,
    // фідбек 2026-07-07): та сама кнопка і нативний popover з FolderPickerList

    private var folderButton: some View {
        Button { folderDropdownOpen = true } label: {
            HStack(spacing: 4) {
                Text((book.folderName ?? String(localized: "Без папки", comment: "Опція «без папки» у виборі папки")).truncatedChip(16))
                    .font(.emUI(11)).foregroundStyle(EmbarColors.ink3)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8)).foregroundStyle(EmbarColors.ink3)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.04)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $folderDropdownOpen, arrowEdge: .bottom) { folderPicker }
    }

    private var folderPicker: some View {
        FolderPickerList(
            options: [FolderPickerList.Option(
                id: "none", label: String(localized: "Без папки", comment: "Опція «без папки» у виборі папки"),
                isSelected: book.folderName == nil,
                select: { pickFolder(nil) })]
            + ReaderService.folders(including: [book]).map { name in
                FolderPickerList.Option(
                    id: name, label: name,
                    isSelected: book.folderName == name,
                    select: { pickFolder(name) })
            },
            onCreate: { name in
                guard ProGate.allowCreate() else { return } // режим читання
                if let clean = ReaderService.addFolder(name) { pickFolder(clean) }
            })
    }

    private func pickFolder(_ name: String?) {
        ReaderService.setFolder(name, for: book)
        folderDropdownOpen = false
    }

    // MARK: - Undo-стек Cmd+Z (SPEC §4.5)

    /// Локальний монітор клавіш: Cmd+Z поза полями вводу → наш стек;
    /// у полі вводу подія йде далі — нативний undo тексту (SPEC §4.5)
    private func installUndoKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags
                .intersection([.command, .shift, .option, .control]) == .command,
                event.charactersIgnoringModifiers?.lowercased() == "z"
            else { return event }
            // Подію віддаємо полю лише якщо активний елемент СПРАВДІ
            // редагований і непорожній — там нативний undo тексту.
            // Це закриває обидві пастки попередніх спроб: композер, що
            // навмисно тримає фокус із порожнім полем (спроба 1), і
            // нередаговані текст-вью записів у пен-режимі, які теж
            // ставали first responder (спроба 2)
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
               editor.isEditable, !editor.string.isEmpty {
                return event
            }
            performReaderUndo()
            return nil // подію спожито
        }
    }

    private func pushUndo(_ label: ReaderUndoLabel, revert: @escaping () -> Void) {
        undoStack.append((label, revert))
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
    }

    private func performReaderUndo() {
        guard let last = undoStack.popLast() else {
            toasts.showMini("Нічого скасовувати")
            return
        }
        withAnimation { last.revert() }
        // Ярлик резолвимо в рядок ДО підстановки: у шаблон «Скасовано: %@»
        // кожна мова кладе свою форму слова
        toasts.showMini("Скасовано: \(String(localized: last.label.text))")
    }

    private func deleteEntry(_ entry: ReaderEntry) {
        // Видалення того, що грає — зупинити плеєр
        if voicePlayer.currentID == entry.id { voicePlayer.stop() }
        // Зникнення запису — рух поверхні, анімується (§7.2-A)
        withAnimation { ReaderService.softDeleteEntry(entry) }
        pushUndo(.deleteEntry) { ReaderService.undoDeleteEntry(entry) }
        toasts.showUndo(message: "Запис видалено") {
            withAnimation { ReaderService.undoDeleteEntry(entry) }
        }
    }

    private func deleteBook() {
        let book = self.book
        reader.close()
        withAnimation { ReaderService.softDeleteBook(book) }
        toasts.showUndo(message: "Блокнот видалено") {
            withAnimation { ReaderService.undoDeleteBook(book) }
        }
    }
}

// MARK: - Кнопки футера (прототип .note-action-btn і .reader-back-btn)

private struct NbActionButton: View {
    let icon: String
    var size: CGFloat = 15
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(EmbarColors.ink)
                .opacity(hovering ? 1 : 0.4)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(hovering ? 0.07 : 0)))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct BackButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 11))
                Text("Назад").font(.emUI(12))
            }
            .foregroundStyle(hovering ? EmbarColors.ink : EmbarColors.ink3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
