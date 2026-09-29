//
//  ContentView.swift
//  Embar
//
//  Каркас панелі: хедер · таби · поверхні · футер. SPEC.md §1–§7.
//  У M1 це скелет без функціоналу — поверхні наповнюються в M2–M5.
//

import SwiftUI
import SwiftData

/// Три поверхні панелі (SPEC §1: nav з 3 табів)
enum PanelTab: String, CaseIterable, Identifiable {
    // rawValue — технічний ідентифікатор, не текст на екрані: назву не
    // можна перекладати через rawValue, бо це водночас `id` (i18n)
    case stickies, notes, reader
    var id: String { rawValue }

    /// Підпис таба
    var title: LocalizedStringKey {
        switch self {
        case .stickies: "Стіки"
        case .notes: "Нотатки"
        case .reader: "Рідер"
        }
    }

    /// Іконка таба (SF Symbols — найближче до SVG прототипу)
    var icon: String {
        switch self {
        case .stickies: "square.grid.2x2"
        case .notes: "folder"
        case .reader: "book"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var theme = ThemeStore()
    @StateObject private var toasts = ToastCenter()
    @StateObject private var stickies = StickiesModel()
    @StateObject private var notes = NotesModel()
    @StateObject private var reader = ReaderModel()
    @StateObject private var home = HomeModel()
    // ⚠️ Debug-стенд (GlassLab): `-GlassShotTab notes|reader` відкриває
    // потрібну вкладку одразу для self-скріншота; без аргумента — стіки
    @State private var selectedTab: PanelTab = {
        switch EmbarDefaults.store.string(forKey: "GlassShotTab") {
        case "notes": .notes
        case "reader": .reader
        default: .stickies
        }
    }()
    // `-GlassShotTab settings` — одразу відкриті налаштування (self-
    // скріншот картки Embar Pro, 2026-09-17)
    @State private var showingAppSettings =
        EmbarDefaults.store.string(forKey: "GlassShotTab") == "settings"
    @AppStorage("panelLocked") private var panelLocked = false
    /// Чи людина вже відкривала загальні налаштування. Поки ні -
    /// шестерня тихо світиться (SPEC §6): без цього її просто не
    /// помічали, а за нею вся кастомізація
    @AppStorage(SettingsGlow.storageKey) private var appSettingsOpened = false
    @Namespace private var tabUnderlineNS
    /// Reduce Transparency примусово опакне матеріальність (§15.17)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Токени матеріальності — рахуються раз і їдуть Environment-ом
    private var materialTokens: MaterialTokens {
        MaterialTokens.resolve(theme: theme.materialTheme,
                               glassOpacity: theme.glassOpacity,
                               reduceTransparency: reduceTransparency)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            surface
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .embarPanelBacking()
        // Лист налаштувань стіків — на рівні ВСІЄЇ панелі, щоб скрим накривав
        // хедер/таби/футер і згасав рівномірно (фідбек 2026-07-03)
        .embarBottomSheet(isPresented: $stickies.showingSettings) {
            StickiesSettingsSheetContainer(model: stickies, palette: theme.current)
        }
        // Home-шторка — поверх усієї панелі, слайд знизу 0.34s (SPEC §5.2)
        .overlay {
            if home.isOpen {
                HomeShutterView(home: home)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.34), value: home.isOpen)
        // Блокнот рідера — повноекранний оверлей, слайд справа 0.28s (SPEC §4.2).
        // НИЖЧЕ редактора нотаток: quoteToNote відкриває нотатку ПОВЕРХ блокнота
        .overlay { readerNotebookOverlay }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.28), value: reader.openBook?.id)
        // Редактор нотатки — повноекранний оверлей, слайд справа 0.28s (SPEC §3.2).
        // .id(note) → свіжий NoteEditorModel і документ на кожну нотатку
        .overlay { noteEditorOverlay }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.28), value: notes.editingNote?.id)
        // App Settings — поверх усього, слайд справа 0.32s (прототип
        // .settings-panel transition)
        .overlay {
            if showingAppSettings {
                SettingsPanel { showingAppSettings = false }
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.32), value: showingAppSettings)
        // ❗ Тости — НАД шторкою: інакше undo-тости видалень усередині Home
        // малювались під непрозорою шторкою і 5с-вікно спливало невидимим
        .toastLayer(toasts)
        // Заокруглення всіх кутів панелі — 16pt (Embar.md §9.4; фідбек M1)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // Крайовий піксель кліпу змішується з темним столом + обідок
        // системної тіні → читався як «темний бордер». Перекриваємо його
        // обводкою в КОЛІР ФОНУ панелі (фідбек 2026-07-19; лише opaque —
        // у склі/левітації непрозоре кільце було б артефактом)
        .overlay {
            if materialTokens.theme == .opaque {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(EmbarColors.surface, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        // Скло/контролі рендеряться за controlActiveState, який стрибав
        // inactive→key при кліку (панель ставала справжнім key-вікном) —
        // тінь/тон поля «дихали». Панель завжди виглядає активною
        // (фідбек 2026-07-20; пара до isKeyWindow-override в EmbarPanel)
        .environment(\.controlActiveState, .key)
        // ❗ environmentObject НАЙЗОВНІШНІ: щоб bottomSheet, toastLayer і шторка
        // (додані вище в ланцюжку) усі отримали theme/toasts/home
        .environment(\.embarMaterial, materialTokens)
        .environmentObject(theme)
        .environmentObject(toasts)
        .environmentObject(home)
        .environmentObject(notes)
        .onChange(of: selectedTab) { _, _ in stickies.showingSettings = false }
        // Зонд пісочниці (-SandboxPerfProbe): доступ до моделей/навігації
        // для автоматичного сценарію замірів
        .onAppear(perform: registerPerfProbe)
        // Клік по сповіщенню про дедлайн → показати цей стік. Клік, що
        // прийшов до появи панелі, чекає в AppDelegate — забираємо його
        .onAppear(perform: drainPendingNotificationSticker)
        .onReceive(NotificationCenter.default.publisher(for: .embarOpenSticker)) { note in
            if let id = note.userInfo?["id"] as? UUID { goToSticker(id) }
        }
        // Cmd+F — контекстний пошук рідера (SPEC §9): блокнот відкритий →
        // пошук у записах, інакше — полиця. Невидима кнопка тримає шорткат
        .background {
            Button(action: contextualFind) { EmptyView() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// Реєстрація зонда пісочниці — окремою функцією: інлайн у body
    /// перевантажував тайпчекер
    private func registerPerfProbe() {
        #if DEBUG
        guard PerfProbe.isActive else { return }
        PerfProbe.register(
            stickies: stickies,
            switchTab: { name in
                switch name {
                case "notes": selectedTab = .notes
                case "reader": selectedTab = .reader
                default: selectedTab = .stickies
                }
            },
            openStressBook: {
                var descriptor = FetchDescriptor<ReaderBook>(
                    predicate: #Predicate {
                        $0.title == "Стрес-блокнот" && $0.deletedAt == nil
                    })
                descriptor.fetchLimit = 1
                guard let book = try? modelContext.fetch(descriptor).first
                else { return false }
                reader.open(book)
                return true
            },
            sampleSticker: {
                // Найсвіжіший живий активний стік - верхівка стіни, те,
                // на чому людина реально тисне
                var d = FetchDescriptor<Sticker>(
                    predicate: #Predicate { $0.deletedAt == nil && !$0.done },
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
                d.fetchLimit = 1
                return try? modelContext.fetch(d).first
            })
        #endif
    }

    // Винесено з body: інлайн-оверлеї перевантажували тайпчекер
    @ViewBuilder private var readerNotebookOverlay: some View {
        if let book = reader.openBook {
            ReaderNotebookView(book: book, reader: reader,
                               onQuoteToNote: openQuotedNote)
                .id(book.id)
                .transition(.move(edge: .trailing))
        }
    }

    @ViewBuilder private var noteEditorOverlay: some View {
        if let note = notes.editingNote {
            NoteEditorView(note: note, notes: notes, context: modelContext,
                           onReaderSource: goToReaderEntry,
                           onStickerSource: { goToSourceSticker(of: note) })
                .id(note.id)
                .transition(.move(edge: .trailing))
        }
    }

    /// Клік по «зі стікера» в редакторі → таб Стіки, доскрол і відскок
    /// стіка-джерела (SPEC §12.1 зворотний бік). Битий лінк не мовчить
    private func goToSourceSticker(of note: Note) {
        guard let sticker = note.sourceSticker, sticker.deletedAt == nil else {
            toasts.showMini("Стік видалено")
            return
        }
        notes.close()
        reveal(sticker)
    }

    /// Показати стік із натиснутого сповіщення (той самий шлях, що «зі
    /// стікера»): закрити чужі оверлеї, перейти на Стіки, доскролити
    private func goToSticker(_ id: UUID) {
        // Гасимо відкладений перехід: інакше він спрацював би ще раз при
        // наступній появі панелі
        _ = AppDelegate.current?.takePendingOpenSticker()
        var descriptor = FetchDescriptor<Sticker>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let sticker = try? modelContext.fetch(descriptor).first,
              sticker.deletedAt == nil else {
            toasts.showMini("Стік видалено")
            return
        }
        notes.close()
        reader.close()
        home.close()
        // App Settings — теж оверлей поверх усього: відкриті налаштування
        // ховали і перехід, і підсвітку (знахідка 2026-08-20)
        showingAppSettings = false
        reveal(sticker)
    }

    private func drainPendingNotificationSticker() {
        guard let id = AppDelegate.current?.takePendingOpenSticker()
        else { return }
        goToSticker(id)
    }

    /// Доскрол і відскок стіка: «Всі» + правильний фільтр, щоб він точно
    /// був у вибірці
    private func reveal(_ sticker: Sticker) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            selectedTab = .stickies
        }
        // Лист налаштувань накрив би підсвітку, і клік по сповіщенню
        // виглядав би як «нічого не сталось» (ревʼю 2026-08-19).
        // Розгорнутий стік закриває сама стіна — він її приватний стан
        stickies.showingSettings = false
        stickies.selectedWallID = nil
        stickies.filterKind = sticker.archived ? .archive : .all
        stickies.emojiFilter = nil
        stickies.pendingFlashStickerID = sticker.id
    }

    // MARK: - Рідер ↔ Нотатки (SPEC §12.3, M5 крок 16)

    /// Цитата поїхала в нотатку: закрити блокнот, перейти на Нотатки,
    /// відкрити редактор (паттерн matureSticky)
    private func openQuotedNote(_ note: Note) {
        reader.close()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            selectedTab = .notes
        }
        notes.open(note)
    }

    /// Клік по підпису цитати в нотатці → назад до запису в Рідері.
    /// Биті лінки не мовчать: тост і жодної навігації (SPEC §12.5)
    private func goToReaderEntry(bookID: UUID, entryID: UUID) {
        var descriptor = FetchDescriptor<ReaderBook>(
            predicate: #Predicate { $0.id == bookID })
        descriptor.fetchLimit = 1
        guard let book = try? modelContext.fetch(descriptor).first,
              book.deletedAt == nil else {
            toasts.showMini("Цей блокнот уже видалено")
            return
        }
        guard let entry = (book.entries ?? [])
            .first(where: { $0.id == entryID }), entry.deletedAt == nil else {
            toasts.showMini("Цей запис уже видалено")
            return
        }
        notes.close()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            selectedTab = .reader
        }
        reader.pendingFlashEntryID = entry.id
        reader.open(book)
    }

    private func contextualFind() {
        // Лише на поверхні рідера; не перехоплюємо в редакторі нотаток/шторці
        guard selectedTab == .reader, notes.editingNote == nil, !home.isOpen
        else { return }
        reader.toggleContextualSearch()
    }

    // MARK: - Хедер: лого · lock · settings (SPEC §1)

    private var header: some View {
        HStack(spacing: 0) {
            // Лого: знак + UPPERCASE-слово, приглушені (прототип .panel-logo).
            // Знак — template-асет: бере колір хедера, тож переживе dark mode
            // (M6) без окремої версії
            HStack(spacing: 6) {
                Image("logo-mark")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                    // Брендовий червоний = РІВНО той, що в оригіналі лого
                    // (ревізія 2026-08-17: тут стояла примірка #FF5453,
                    // яка розійшлася з асетом). Прибрати цей рядок →
                    // знак знову приглушений ink3
                    .foregroundStyle(EmbarColors.brandRed)
                Text("Embar".uppercased())
                    .font(.emUI(12, weight: .medium))
                    .tracking(0.06 * 12)
            }
            .foregroundStyle(EmbarColors.ink3)
            Spacer()
            HStack(spacing: 2) {
                headerIcon(panelLocked ? "lock" : "lock.open", size: 14, opacity: 0.45) {
                    panelLocked.toggle()
                }
                .help(panelLocked ? "Панель закріплена" : "Закріпити панель")
                // Поки налаштування не відкривали, гліф блимає
                // сірий ↔ брендовий червоний (SettingsGlow.swift)
                Button {
                    appSettingsOpened = true
                    showingAppSettings = true
                } label: {
                    SettingsBlinkIcon(blinking: !appSettingsOpened)
                        .frame(width: 28, height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Налаштування")
            }
        }
        // Три ряди (SPEC §15.78є): системні кнопки у смужці заголовка
        // (стандартне місце, центри на 16; смужка перехоплює кліки у
        // верхніх 28pt - туди нічого клікабельного), під нею цей рядок
        // лого · lock · gear (28…56, лого 33…51), далі таби на 60 - рівно
        // там, де були до білда 4 (18+28+14 = 28+28+4)
        .padding(.horizontal, 18)
        .padding(.top, WindowChrome.titlebarHeight)
        .padding(.bottom, 4)
    }

    private func headerIcon(_ name: String, size: CGFloat, opacity: Double,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size))
                .foregroundStyle(EmbarColors.ink)
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .opacity(opacity)
    }

    // MARK: - Таб-бар: іконка + текст, підкреслення активного (прототип .nav)

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PanelTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon).font(.system(size: 13))
                            Text(tab.title)
                                .font(.emUI(12, weight: selectedTab == tab ? .medium : .regular))
                        }
                        .foregroundStyle(selectedTab == tab ? EmbarColors.ink : EmbarColors.ink3)
                        // Колір/жирність лейбла — миттєво (§7.2-A), scoped до
                        // selectedTab: не глушить чужі анімації (рух панелі)
                        .animation(nil, value: selectedTab)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 11)
                        // Підкреслення ковзає між табами (matchedGeometry, як
                        // scaleX-перехід у прототипі, але приємніше — слайд)
                        ZStack {
                            Color.clear.frame(height: 1.5)
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(EmbarColors.ink)
                                    .frame(height: 1.5)
                                    .matchedGeometryEffect(id: "tabUnderline", in: tabUnderlineNS)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    // Клік ловить УВЕСЬ контейнер таба (іконка + текст +
                    // паддінги), а не лише текст (фідбек 2026-07-19)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // Сіру hairline під табами прибрано (фідбек 2026-07-19) —
        // межу тепер м'яко дає верхній fade стіни
        .padding(.horizontal, 18)
        // 0: білого відступу під табами немає ВЗАГАЛІ — контент
        // починається одразу під ними (фідбек 2026-07-19 ×2)
        .padding(.bottom, 0)
    }

    // MARK: - Поверхня активного таба

    @ViewBuilder private var surface: some View {
        Group {
            switch selectedTab {
            case .stickies:
                StickiesView(model: stickies) { note in
                    // Стік → Нотатка: перемкнути таб і відкрити редактор (SPEC §12.1)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selectedTab = .notes
                    }
                    notes.open(note)
                }
            case .notes:
                NotesView(model: notes)
            case .reader:
                ReaderView(model: reader)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Вміст таба перемикається миттєво (§7.2-A) — але ТІЛЬКИ для змін,
        // спричинених selectedTab. ❗ Бланкетний .transaction{animation=nil}
        // тут глушив УСІ анімації всередині (каскад стіни, морф чіпів,
        // появу/видалення стіків) — корінь багу «каскад не запускається»
        .animation(nil, value: selectedTab)
    }

    // MARK: - Футер: тижнева смужка (SPEC §5.1)
    // Прототип: смужка займає весь футер, FAB прибрано (.new-btn display:none)

    /// Показувати тижневу смужку (App Settings, H2): вимкнена — футера
    /// нема взагалі, місце віддається контенту
    @AppStorage("showWeekStrip") private var showWeekStrip = true

    @ViewBuilder private var footer: some View {
        if showWeekStrip {
            // Home сховано з v1 (HomeFeature): без onOpen смужка пасивна —
            // тиждень видно, але тап не відкриває шторку
            HomeWeekStripClosed(todayAnchor: home.todayAnchor,
                                onOpen: HomeFeature.enabled ? { home.open() } : nil)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Sticker.self, inMemory: true)
        .environmentObject(ThemeStore())
        .environmentObject(ToastCenter())
        .frame(width: 360, height: 700)
}
