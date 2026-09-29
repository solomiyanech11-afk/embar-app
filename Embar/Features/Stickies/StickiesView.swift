//
//  StickiesView.swift
//  Embar
//
//  Поверхня «Стіки»: quick input + стіна у дві колонки + walls bar (SPEC §2).
//  Expanded-редактор — крок 5; налаштування-sheet — крок 6.
//

import SwiftUI
import SwiftData

struct StickiesView: View {
    @ObservedObject var model: StickiesModel
    /// Стік дозрів у нотатку (SPEC §12.1) — перемкнути таб і відкрити редактор
    var onMatureToNote: (Note) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var home: HomeModel

    @Query(sort: \Sticker.createdAt, order: .reverse) private var allStickers: [Sticker]
    @Query(sort: \Wall.sortOrder) private var allWalls: [Wall]
    @AppStorage("hideDoneStickies") private var hideDoneStickies = false
    // Режим кольору — ТУТ, а не в кожній StickyCard: два спостерігачі
    // UserDefaults на панель замість двох на кожну з тисяч карток
    // (перф-фікс 2026-08-16, найгарячіше місце профілю)
    @AppStorage("wallColorMode") private var wallColorMode = "random"
    @AppStorage("noWallColorSlot") private var noWallColorSlot = 0

    /// Кеш оцінок висот карток для розкладання по колонках (референс-тип:
    /// мутація кеша не інвалідовує вьюху)
    @State private var heightEstimator = StickyHeightEstimator()
    /// Каскад грає лише коротке вікно після пере-вибірки стіни: у лінивій
    /// стіні onAppear приходить і при скролі — без цього прапорця хвиля
    /// програвалась би щоразу, коли картки повертаються у вʼюпорт
    @State private var cascadeArmed = true
    @State private var cascadeGeneration = 0
    /// Хто в цій вибірці каскад уже відіграв: перескік картки між
    /// колонками (pin/done) перестворює її структурно, і без реєстру
    /// хвиля грала б удруге — сусіди блимали (ревʼю 2026-08-18, знахідка 5)
    @State private var cascadeLedger = CascadeLedger()

    @State private var addingWall = false
    @State private var newWallName = ""
    @State private var expandedSticker: Sticker?
    /// Стан тулбара розгорнутого стіка живе тут: клік по тлу панелі має
    /// знати, чи є що згортати, перш ніж закривати сам стік
    @State private var toolbarMode: StickyToolbarMode = .bar
    /// Стік, що «відскакує» після переходу з нотатки (паттерн flashEntryID
    /// рідера; SPEC §12.1)
    @State private var flashStickerID: UUID?
    /// «Виконано» на картці: викреслені і розчинювані стіки + живі
    /// відліки до переїзду. Живе ТУТ, а не в @State картки (F3,
    /// 2026-08-28): LazyVStack-колонка масонрі кешує стан рядка за id
    /// навіть після зникнення рядка з даних і воскрешає його, коли той
    /// самий стік повертається з «Виконаних», — картка лишалась із
    /// прозорістю 0 назавжди (SPEC §15.65, LazyStateResurrectionTests)
    @State private var completingIDs: Set<UUID> = []
    @State private var dissolvingIDs: Set<UUID> = []
    @State private var completeTasks: [UUID: Task<Void, Never>] = [:]
    /// Стік, що прибуває на нове місце після піна (фідбек 2026-08-22):
    /// анімований переїзд перетасовував колонки — стіна читалась як
    /// перезавантаження. Тепер перескладка миттєва, а сам стік
    /// проявляється на новій позиції (ArrivalReveal)
    @State private var pinArrivalID: UUID?
    /// Відкрите питання «прибрати навчальні стіки?»
    @State private var tutorialPromptOpen = false
    @State private var sweepHovering = false
    /// Пропозиція прибрати навчальні стіки визріла і БІЛЬШЕ НЕ ХОВАЄТЬСЯ
    /// (до ✓ або ×). ❗ Не @State (P2.6): перемикання таба перестворює
    /// вьюху, і кнопка зникала при поверненні на стіну — визрілість
    /// живе в налаштуваннях, як і tutorialSweepDismissed
    @AppStorage("tutorialSweepReady") private var sweepReady = false
    /// Відлік уже стартував — тобто панель показали хоча б раз. Далі
    /// відкриття й закриття кнопки не чіпають
    @State private var sweepRipening = false
    /// × на кнопці: людина лишає навчальні стіки і більше не хоче
    /// бачити пропозицію
    @AppStorage("tutorialSweepDismissed") private var tutorialSweepDismissed = false
    @Namespace private var wallChipNS

    private var walls: [Wall] { allWalls.filter { $0.deletedAt == nil } }
    private var selectedWall: Wall? { walls.first { $0.id == model.selectedWallID } }

    /// Зріз стіни живе в кеші StickiesModel (F5, 2026-08-28): повний
    /// O(n)-перерахунок — лише при зміні вибірки чи масовій мутації,
    /// одиночні дії правлять кеш точково (StickyWallSlice.swift).
    /// Раніше цей фільтр+сортування ганявся тут на КОЖЕН body — на 5000
    /// стіків ~308 мс по холодних обʼєктах на кожен тап
    private func makeSections() -> WallSlice {
        model.slice(all: allStickers, wall: selectedWall)
    }

    private func showDoneSection(_ sections: WallSlice) -> Bool {
        !sections.done.isEmpty && (!hideDoneStickies || model.filterKind == .done)
    }

    var body: some View {
        // Зріз стіни рахуємо ОДИН раз на рендер і роздаємо вниз параметром
        let sections = makeSections()
        ZStack {
            mainContent(sections)
                .blur(radius: expandedSticker != nil ? 2 : 0)
                .opacity(expandedSticker != nil ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.2), value: expandedSticker?.id)

            if let sticker = expandedSticker {
                // Прозорий шар для закриття кліком поза карткою. Розкритий
                // тулбар клік повз спершу згортає — і лише другий клік
                // закриває сам стік
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if toolbarMode == .bar {
                            closeExpanded()
                        } else {
                            toolbarMode = .bar
                        }
                    }
                StickyExpandedView(
                    sticker: sticker,
                    palette: theme.current,
                    walls: walls,
                    toolbarMode: $toolbarMode,
                    onClose: closeExpanded,
                    onMature: { matureAction(sticker) },
                    onDelete: { closeExpanded(); deleteWithUndo(sticker) },
                    onCreateWall: { createWall($0) }
                )
                .padding(.horizontal, 12)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: expandedSticker?.id)
        // Під віконцями-питаннями - той самий світлий блюр, що при
        // розгорнутому стіку (фідбек 2026-08-12)
        .dialogDimmed(model.wallPendingDelete != nil || tutorialPromptOpen)
        // Віконце-питання видалення стіни: лише стіну чи разом зі стіками
        // (фідбек 2026-07-07; відкривається з листа налаштувань)
        .overlay {
            // ❗ .allowsHitTesting саме тут, на ВМІСТІ оверлея: SwiftUI
            // під час transition тримає вьюху в дереві ще якийсь час, і
            // її скрим далі ловив кліки. Прапорець гасить їх одразу
            Group {
            if let wall = model.wallPendingDelete {
                ConfirmDeleteDialog(
                    title: "Видалити стіну «\(wall.name.truncatedChip())»?",
                    keepLabel: "Лише стіну - стіки залишаться",
                    purgeLabel: "Разом зі стіками",
                    onKeep: { removeWall(wall, purgeStickers: false) },
                    onPurge: { removeWall(wall, purgeStickers: true) },
                    onCancel: { model.wallPendingDelete = nil })
            }
            }
            .allowsHitTesting(model.wallPendingDelete != nil)
        }
        .overlay {
            Group {
            if tutorialPromptOpen {
                EmbarDialog(
                    title: "Уже прочитано?",
                    note: "У навчальних стіках зібрано найкорисніше про Embar. Якщо знадобиться - усе це є в Налаштуваннях, у Hidden Gems.",
                    dismissLabel: "Залишити їх поки що",
                    onCancel: { tutorialPromptOpen = false }
                ) {
                    ConfirmChoicePill(label: "Прочитано - прибрати",
                                      fill: EmbarColors.ink, text: .white,
                                      action: sweepTutorialStickers)
                }
            }
            }
            // Той самий запобіжник: після «залишити» скрим не сміє
            // з`їдати натискання по стіні (баг 2026-08-11 - стіна
            // ставала мертвою, поки не перемкнути таб і назад)
            .allowsHitTesting(tutorialPromptOpen)
        }
        // ОДИН scope анімації на обидва віконця: два .animation(value:)
        // один над одним вкладаються, і зовнішній перестає діставати
        // до вьюх, що лежать під внутрішнім - саме там transition і
        // зависав
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2), value: dialogKey)
        // Пропозиція прибрати навчальні стіки визріває через 5с спокою —
        // з порога вона муляла (фідбек 2026-08-20). ❗ Відлік лише ОДИН
        // раз, на першому показі панелі: раніше кожне закриття ховало
        // кнопку і змушувало чекати ті самі 5 секунд наново (фідбек
        // 2026-08-21). Визріла — і висить, поки не натиснуть ✓ або ×
        .onReceive(NotificationCenter.default.publisher(
            for: .embarPanelDidShow)) { _ in sweepRipening = true }
        // Повернення з іншого таба (P2.6): вьюха перестворена, панель
        // уже видима — сповіщення про показ не буде, стартуємо відлік
        // самі. Поки панель схована, відлік як і раніше чекає показу
        .onAppear { if PanelRevealState.shared.revealed { sweepRipening = true } }
        .task(id: sweepRipening) { await ripenSweepOffer() }
    }

    /// Відлік до показу. Стартує лише коли панель уперше показали, і
    /// відпрацьовує один раз: `sweepRipening` більше не міняється, тож
    /// `.task(id:)` вдруге не запуститься
    private func ripenSweepOffer() async {
        guard sweepRipening, !sweepReady else { return }
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { return }
        // Проявлення — рух самої поверхні, тож анімоване (§7.2-A)
        withAnimation(.easeOut(duration: 0.45)) { sweepReady = true }
    }

    /// Ключ обох віконець-питань - один рядок замість двох окремих
    /// .animation(value:)
    private var dialogKey: String {
        "\(model.wallPendingDelete?.id.uuidString ?? "-")|\(tutorialPromptOpen)"
    }


    private func removeWall(_ wall: Wall, purgeStickers: Bool) {
        model.wallPendingDelete = nil
        if model.selectedWallID == wall.id { model.selectedWallID = nil }
        let affected = allStickers.filter { $0.deletedAt == nil && $0.wall?.id == wall.id }
        settle {
            wall.deletedAt = .now
            if purgeStickers {
                for sticker in affected { StickerService.softDelete(sticker) }
            }
            // Страховка поверх точкових патчів softDelete: міняється і
            // сама стіна — план F5 класифікує це як повну інвалідацію
            StickerMutation.bulkChanged()
        }
        toasts.showUndo(message: purgeStickers ? "Стіну і стіки видалено"
                                               : "Стіну видалено") {
            settle {
                wall.deletedAt = nil
                if purgeStickers {
                    for sticker in affected { StickerService.undoDelete(sticker) }
                }
                StickerMutation.bulkChanged() // страховка, як у прямого шляху
            }
            // Серед стіків могли бути віджети на столі — undo повертає
            // і їхні вікна (інваріант SPEC §2.7; ревʼю 2026-07-30, Б1)
            if purgeStickers {
                for sticker in affected {
                    DesktopStickyManager.shared.reconcile(sticker)
                }
            }
        }
    }

    private func mainContent(_ sections: WallSlice) -> some View {
        // Поле вводу — левітуюча frost-поверхня НАД стіною (фідбек
        // 2026-07-19): стіки скролять під неї і розчиняються у fade-зоні,
        // жодних суцільних білих смуг чи різкого зрізу (правило проєкту)
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if model.filterKind == .archive {
                        // Шапка з поясненням + вихід до активних (фідбек
                        // 2026-07-21) — видно і над порожнім архівом
                        VStack(spacing: 0) {
                            archiveHeader
                            if sections.filtered.isEmpty {
                                filterEmptyState
                            } else {
                                wallGrid(sections.filtered)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                            }
                        }
                    } else if sections.filtered.isEmpty {
                        if isTrulyEmpty(sections) {
                            emptyState
                        } else {
                            filterEmptyState
                        }
                    } else {
                        wall(sections)
                    }
                }
                // На всю ширину: вертикальний ScrollView обіймає ширину вмісту,
                // і вузький empty state звужував його разом із walls bar
                .frame(maxWidth: .infinity)
                .padding(.top, 72)    // під скляним полем + повітря до стіків
                .padding(.bottom, 40) // місце під плаваючою walls bar
                // Зміна теки/фільтра → повна пере-вставка карток: кожна має
                // власну каскадну insertion-анімацію (див. cascadeCard)
                .id(selectionKey)
            }
            .scrollIndicators(.hidden)
            // Клік повз поле «Нова стіна» = передумав. ❗ Ловець чіпляємо
            // ПЕРШИМ, щоб він лежав ПІД склом композера і баром стін:
            // раніше він був вище і з'їдав перший клік у композер
            // (ревʼю 2026-08-18, знахідка 4)
            .dismissOnTapOutside(addingWall) {
                addingWall = false
                newWallName = ""
            }
            // Нотатка → стік: доскролити і підсвітити відскоком (§12.1).
            // onAppear — прихід з іншого таба; onChange — якщо вже тут
            .onAppear(perform: { flashPendingSticker(proxy) })
            .onChange(of: model.pendingFlashStickerID) { _, _ in
                flashPendingSticker(proxy)
            }
        }
        // Верхня зона (уточнення 2026-07-20): ВИЩЕ верхнього краю поля
        // жодних фрагментів карток — від табів до краю поля суцільний
        // колір панелі (15pt = top-паддінг поля); далі розчинення йде
        // вже ПІД склом, тож крізь саме скло картки просвічують як досі
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(EmbarColors.surface).frame(height: 15)
                LinearGradient(colors: [EmbarColors.surface,
                                        EmbarColors.surface.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .top) { quickInput }
        // Walls bar плаває над стіною (прозорий флоут), картки скролять під нею
        .overlay(alignment: .bottom) { wallsBar(sections) }
        .onAppear(perform: armCascade)
        .onChange(of: selectionKey) { _, _ in armCascade() }
    }

    /// Увімкнути каскад на ~0.7 с після пере-вибірки стіни (див. cascadeArmed)
    private func armCascade() {
        cascadeLedger.reset()
        cascadeArmed = true
        cascadeGeneration += 1
        let generation = cascadeGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if cascadeGeneration == generation { cascadeArmed = false }
        }
    }

    /// Шапка архіву: як він працює + повернення до активних (2026-07-21)
    private var archiveHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Сюди переїжджають виконані стіки, коли минає їхній строк. Тут вони залишаються на 30 днів, а потім зникають.")
                .font(.emUI(12))
                .foregroundStyle(EmbarColors.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Button { model.filterKind = .all } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left").font(.system(size: 10))
                    Text("До активних стіків").font(.emUI(12, weight: .medium))
                }
                .foregroundStyle(EmbarColors.ink2)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    /// Доскрол + одноразовий відскок стіка-джерела (~0.5с, як у рідера)
    private func flashPendingSticker(_ proxy: ScrollViewProxy) {
        guard let target = model.pendingFlashStickerID else { return }
        model.pendingFlashStickerID = nil
        // Розгорнутий стік накрив би стіну, і доскрол лишився б за ним
        // (ревʼю 2026-08-19: клік по сповіщенню виглядав як «нічого»)
        if expandedSticker != nil { closeExpanded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation { proxy.scrollTo(target, anchor: .center) }
            flashStickerID = target
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                flashStickerID = nil
            }
        }
    }

    /// Ключ вибірки: стіна + фільтр (+емоджі) — зміна будь-чого запускає каскад
    private var selectionKey: String {
        "\(model.selectedWallID?.uuidString ?? "all")|\(model.filterKind.rawValue)|\(model.emojiFilter ?? "")"
    }

    /// Перемкнути стіну: морф активного чіпа (spring) + каскад карток
    /// (embedded-анімації переходів, не залежать від цього withAnimation)
    private func switchWall(to id: UUID?) {
        guard id != model.selectedWallID else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            model.selectedWallID = id
        }
    }

    /// Стіків немає ВЗАГАЛІ (не через фільтр/стіну) — тоді бренд-повідомлення.
    /// Лічильник живих — з кеша зрізу: власний O(n)-прохід по властивостях
    /// платив би той самий faulting, який кеш прибрав (F5)
    private func isTrulyEmpty(_ sections: WallSlice) -> Bool {
        model.filterKind == .all && selectedWall == nil && sections.countAll == 0
    }

    // MARK: - Quick input

    private var quickInput: some View {
        // Чернетка живе ВСЕРЕДИНІ StickiesQuickInput: кожен символ раніше
        // мутував @State цієї вьюхи і пере-рендерив усю стіну — на тисячах
        // стіків друк заїкався (перф-фікс 2026-08-16)
        StickiesQuickInput(
            // Не красти фокус, коли зверху розгорнутий стік,
            // лист налаштувань чи шторка
            autoFocus: expandedSticker == nil && !model.showingSettings
                && model.wallPendingDelete == nil && !home.isOpen
        ) { text in
            // Новий стік приземляється (транзиція в cascadeCard), а не
            // виникає готовим
            settle { _ = StickerService.add(text: text, wall: selectedWall, in: context) }
        }
        // БЕЗ підкладки (дизайн-хендоф 2026-07-19): жодного сірого
        // блоку/шва — фон суцільний, «поверхню» дає лише саме скляне
        // поле, крізь яке стіки проступають розмито
    }

    // MARK: - Стіна

    private func wall(_ sections: WallSlice) -> some View {
        VStack(spacing: 0) {
            wallGrid(sections.active)

            if showDoneSection(sections) {
                // Розділювач має сенс лише між активними і виконаними
                if !sections.active.isEmpty {
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(height: 1)
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                }
                wallGrid(sections.done)
            }
            // Показуємо лише коли навчальні стіки справді видно в цьому
            // зрізі: під фільтром чи чужою стіною кнопка пропонувала б
            // прибрати те, чого на екрані немає. І не одразу — див.
            // sweepReady (фідбек 2026-08-20: не муляти очі з порога)
            if sweepReady, !tutorialSweepDismissed,
               sections.filtered.contains(where: { tutorialIDs.contains($0.id) }) {
                tutorialSweepButton
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    // MARK: - Навчальні стіки: кнопка «прибрати всі»
    //
    // Живе під стіною, поки на ній лежить хоч один туторіальний стік.
    // Свідомий виняток із правила «без confirm» (SPEC §8.2): це гуртове
    // видалення шести карток, і кожна з них щось пояснює - тому питаємо
    // один раз, а не даємо шість тостів-undo

    private var tutorialIDs: Set<UUID> { OnboardingSeeder.seededStickerIDs }

    /// Усі живі навчальні стіки - прибираємо їх ГУРТОМ, навіть якщо
    /// частина зараз під іншим фільтром: кнопка обіцяє саме це
    private var liveTutorialStickers: [Sticker] {
        let ids = tutorialIDs
        guard !ids.isEmpty else { return [] }
        return allStickers.filter { $0.deletedAt == nil && ids.contains($0.id) }
    }

    /// Редизайн 2026-08-20 (фідбек, друга ітерація: пульс теж муляв):
    /// блідо-сірий текст-питання без фону і без анімації, ✓ і ✕ видно
    /// одразу; під курсором вони насичуються. ✓ — те саме
    /// віконце-питання, ✕ — пропозиція зникає назавжди
    private var tutorialSweepButton: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Text("Прибрати навчальні стіки?")
                .font(.emUI(11.5, weight: .medium))
                .foregroundStyle(EmbarColors.ink3)
            HStack(spacing: 5) {
                sweepChoice("checkmark", help: "Так, прибрати") {
                    tutorialPromptOpen = true
                }
                sweepChoice("xmark", help: "Ні, лишити і більше не питати") {
                    tutorialSweepDismissed = true
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { sweepHovering = $0 }
        .padding(.top, 18)
    }

    private func sweepChoice(_ icon: String, help: LocalizedStringKey,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                // Насичується, коли курсор над рядом (плюс hoverDarken
                // підсвічує кружечок під самим курсором)
                .foregroundStyle(sweepHovering ? EmbarColors.ink : EmbarColors.ink3)
                .frame(width: 18, height: 18)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverDarken(Circle())
        .help(help)
    }

    private func sweepTutorialStickers() {
        tutorialPromptOpen = false
        let affected = liveTutorialStickers
        guard !affected.isEmpty else { return }
        settle {
            for sticker in affected { StickerService.softDelete(sticker) }
        }
        // Серед них міг бути віджет на столі - інваріант SPEC §2.7
        for sticker in affected { DesktopStickyManager.shared.reconcile(sticker) }
        toasts.showUndo(message: "Навчальні стіки прибрано") {
            settle {
                for sticker in affected { StickerService.undoDelete(sticker) }
            }
            for sticker in affected { DesktopStickyManager.shared.reconcile(sticker) }
        }
    }

    /// ЛІНИВА масонрі (перф-фікс 2026-08-16): SwiftUI створює лише видимі
    /// картки — попередній Layout-підхід інстанціював і міряв усі тисячі
    /// на кожну пере-вибірку (секунди блокування головного потоку).
    /// Розкладання по колонках — за кешованою оцінкою висот
    /// (StickyHeightEstimator міряє той самий текст тим самим шрифтом)
    private func wallGrid(_ items: [Sticker]) -> some View {
        LazyTwoColumnMasonry(
            items: items, spacing: 10,
            estimatedHeight: { heightEstimator.height(for: $0, colWidth: $1) }
        ) { sticker, order in
            cascadeCard(sticker, order: order)
        }
    }

    /// Картка з каскадною появою (виняток §7.2-A): CascadeReveal через
    /// onAppear — .transition при swap .id у ScrollView не спрацьовує.
    /// Каскад грає РІВНО ОДИН раз на картку за вибірку: перескік між
    /// колонками після pin/done перестворює вьюху, і без реєстру хвиля
    /// починалась наново (ревʼю 2026-08-18, знахідка 5)
    private func cascadeCard(_ sticker: Sticker, order: Int) -> some View {
        CascadeReveal(order: order,
                      animated: cascadeArmed
                          && !cascadeLedger.hasRevealed(sticker.id)) {
            ArrivalReveal(active: pinArrivalID == sticker.id) {
            StickyCard(
                sticker: sticker,
                palette: theme.current,
                onOpen: { toolbarMode = .bar; expandedSticker = sticker },
                // Переїзд картки — рух поверхні (§7.2-A, ревізія
                // 2026-08-21): прелюдія-танення і переїзд — у
                // completeTapped нижче. Пін — окремий шлях без
                // анімованої перескладки (див. pinWithArrival)
                onToggleDone: { completeTapped(sticker) },
                onTogglePin: { pinWithArrival(sticker) },
                // Видалення — звичайне для ВСІХ стіків (спрощення §15.50):
                // віджет закривається разом, undo повертає обох.
                // На стіл — драгом самої картки (жест у StickyCard, §15.51)
                onDelete: { deleteWithUndo(sticker) },
                // Архів — вітрина (рішення 2026-07-23): без дій
                readOnly: model.filterKind == .archive,
                colorMode: wallColorMode,
                noWallSlot: noWallColorSlot,
                completing: completingIDs.contains(sticker.id),
                dissolving: dissolvingIDs.contains(sticker.id)
            )
            // Спалах після переходу «зі стікера» (виняток §7.2-A, як qnLift)
            .offset(y: flashStickerID == sticker.id ? -6 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.5),
                       value: flashStickerID == sticker.id)
            }
        }
        // Поява = приземлення (підйом 8pt + фейд, мова каскаду), зникнення
        // = фейд; перескік між колонками читається як фейд-переліт. Грає
        // ЛИШЕ в анімованій транзакції (settle) — перемикання стіни/фільтра
        // міняє .id(selectionKey) вище, а транзиції при .id-swap у
        // ScrollView не запускаються (перевірено, див. CascadeReveal)
        .transition(.asymmetric(
            insertion: .offset(y: 8).combined(with: .opacity),
            removal: .opacity))
        .id(sticker.id)
        .onAppear { cascadeLedger.mark(sticker.id) }
    }

    /// Перестановка стіни — крива EmbarMotion.settle; з Reduce Motion
    /// миттєво (§7.2-A)
    private func settle(_ change: () -> Void) {
        EmbarMotion.reorder(reduceMotion: reduceMotion, change)
    }

    // MARK: - «Виконано» → викреслення → розчинення → переїзд (§7.2-A,
    // ревізія 2026-08-21, темп 2026-08-22): пауза 0.4с, щоб викреслення
    // встигло прочитатись, далі dissolve як у віджета по хрестику.
    // Хореографія жила в @State самої картки і воскресала з кеша лінивої
    // колонки — F3, тепер джерело правди тут (див. completingIDs)

    private func completeTapped(_ sticker: Sticker) {
        let id = sticker.id
        if let task = completeTasks[id] {
            // Встигли передумати — повертаємо як було
            task.cancel()
            completeTasks[id] = nil
            completingIDs.remove(id)
            withAnimation(.easeOut(duration: 0.15)) {
                _ = dissolvingIDs.remove(id)
            }
            return
        }
        // Зняття «зроблено» і Reduce Motion — одразу, без розчинення
        if sticker.done || reduceMotion {
            settle { StickerService.toggleDone(sticker) }
            return
        }
        completingIDs.insert(id) // викреслення — миттєве
        completeTasks[id] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                _ = dissolvingIDs.insert(id)
            }
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            completeTasks[id] = nil
            // Могли встигнути видалити, поки картка розчинялась
            if sticker.deletedAt == nil {
                settle { StickerService.toggleDone(sticker) }
            }
            // Прибирання БЕЗ анімації одразу після переїзду: вьюха, що
            // зникає з активної секції, вже заморожена зі своїм
            // dissolving=true, а картка у «Виконаних» і так видима
            // завдяки запобіжнику !done у StickyCard
            completingIDs.remove(id)
            dissolvingIDs.remove(id)
        }
    }

    /// Пін БЕЗ анімованої перескладки (фідбек 2026-08-22): withAnimation
    /// навколо togglePin запускав транзиції на всіх картках, які greedy-
    /// розкладка перекинула між колонками, — стік близько до верху міняв
    /// колонку половині стіни, і це читалось як перезавантаження з
    /// каскадом. Тепер стіна перескладається миттєво, а сам стік тихо
    /// проявляється на новому місці; пін-кулька — своїм мікро-масштабом
    private func pinWithArrival(_ sticker: Sticker) {
        guard !reduceMotion else { StickerService.togglePin(sticker); return }
        pinArrivalID = sticker.id
        StickerService.togglePin(sticker)
        // Мітку знімаємо, коли проявлення вже відіграло (свій показаний
        // стан ArrivalReveal тримає сам)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if pinArrivalID == sticker.id { pinArrivalID = nil }
        }
    }

    private func deleteWithUndo(_ sticker: Sticker) {
        settle { StickerService.softDelete(sticker) }
        toasts.showUndo(message: "Стік видалено") {
            // Undo повертає стік тим самим шляхом: сусіди розступаються,
            // картка проявляється на своєму місці
            settle { StickerService.undoDelete(sticker) }
            // Стік був на столі — undo повертає і віджет (SPEC §2.7)
            DesktopStickyManager.shared.reconcile(sticker)
        }
    }

    // MARK: - Дії expanded-редактора

    private func closeExpanded() {
        expandedSticker?.updatedAt = .now
        expandedSticker = nil
        toolbarMode = .bar
    }

    /// «У нотатку» (SPEC §12.1): і нова, і наявна нотатка — відкриваються в
    /// редакторі; таб перемикається на Нотатки. Стік лишається живим.
    private func matureAction(_ sticker: Sticker) {
        // Гейт лише на СТВОРЕННЯ: живий звʼязок means «відкрити наявну»,
        // а відкривати в режимі читання можна
        if !(sticker.note.map { $0.deletedAt == nil } ?? false) {
            guard ProGate.allowCreate() else { return }
        }
        let note: Note
        switch StickerService.matureSticky(sticker, in: context) {
        case .created(let n): note = n
        case .alreadyExists(let n): note = n
        }
        closeExpanded()
        onMatureToNote(note)
    }

    // MARK: - Walls bar (SPEC §2.5)

    private func wallsBar(_ sections: WallSlice) -> some View {
        // Лічильники всіх чіпів — з кеша зрізу (перф-фікси 2026-08-16 і F5):
        // жодного O(n)-проходу на рендер
        let counts = (all: sections.countAll, byWall: sections.countByWall)
        return HStack(spacing: 5) {
            Button { model.showingSettings = true } label: {
                // Різна іконка: «Всі» — горизонтальні слайдери, стіна —
                // вертикальні (прототип: підказка, що налаштування інші)
                Image(systemName: selectedWall == nil ? "slider.horizontal.3" : "slider.vertical.3")
                    .font(.system(size: 12))
                    .foregroundStyle(EmbarColors.ink2)
                    .frame(width: 28, height: 26)
                    .background(Capsule().fill(EmbarColors.surface.opacity(0.96)))
                    // Тінь = FolderChip (0.10/3/1, фідбек 2026-08-12)
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
            }
            .buttonStyle(.plain)

            ScrollViewReader { proxy in
            EdgeFadedHScroll {
                HStack(spacing: 5) {
                    FolderChip(label: String(localized: "Всі", comment: "Чіп стіни — усі стіки"), count: counts.all,
                               isActive: model.selectedWallID == nil, morphNS: wallChipNS) {
                        switchWall(to: nil)
                    }
                    ForEach(walls) { wall in
                        FolderChip(label: wall.name, count: counts.byWall[wall.id] ?? 0,
                                   isActive: model.selectedWallID == wall.id, morphNS: wallChipNS) {
                            switchWall(to: wall.id)
                        }
                    }
                    if addingWall {
                        // Спільне поле з автофокусом (дрейф-фікс: тут його не було)
                        NewChipField(placeholder: "Нова стіна", text: $newWallName,
                                     onSubmit: finishAddWall,
                                     onCancel: { settleBar { addingWall = false; newWallName = "" } },
                                     onLimitHit: { revealNewChip(proxy) })
                            .id(Self.newChipID)
                            .onAppear { revealNewChip(proxy) }
                    } else {
                        FolderChip(label: "＋") { settleBar { addingWall = true } }
                    }
                }
            }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        // Прозорий флоут із м'яким фейдом — спільний подіум нижніх барів
        // (BottomBarFade); чіпи — окремі непрозорі пігулки
        .bottomBarFade()
    }

    // Лічильники «Всі» + по стінах живуть у кеші зрізу (sections.countAll /
    // .countByWall): окремий O(n)-прохід тут платив би faulting за кожну
    // мутацію (F5)

    private static let newChipID = "new-chip"

    /// Мʼякі рухи поля «Нова стіна» (фідбек 2026-09-04), як у барах
    /// папок; Reduce Motion - миттєво
    private func settleBar(_ change: () -> Void) {
        EmbarMotion.reorder(reduceMotion: reduceMotion, change)
    }

    /// Прогорнути бар до поля нової стіни цілком (разом із пігулкою
    /// ліміту). Наступним тіком: у момент виклику вони ще без розміру
    private func revealNewChip(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            settleBar { proxy.scrollTo(Self.newChipID, anchor: .trailing) }
        }
    }

    private func finishAddWall() {
        // Режим читання: поле лишається відкритим із набраною назвою
        guard ProGate.allowCreate() else { return }
        settleBar { addingWall = false }
        let name = newWallName
        newWallName = ""
        if let wall = createWall(name) { model.selectedWallID = wall.id }
    }

    /// Створити стіну з валідацією (не порожня, не дублікат). Спільне для
    /// walls bar і сабпанелі стіни в редакторі.
    @discardableResult
    private func createWall(_ rawName: String) -> Wall? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !walls.contains(where: { $0.name == name }) else { return nil }
        let wall = Wall(name: name)
        wall.sortOrder = (walls.map(\.sortOrder).max() ?? -1) + 1
        context.insert(wall)
        return wall
    }

    // MARK: - Empty state (SPEC §8.1.1)

    private var emptyState: some View {
        EmptyStateText(line1: "Поки порожньо.",
                       line2: "Напиши першу думку, щоб не загубити.")
            .padding(.top, 120)
    }

    /// Порожній результат фільтра/стіни/архіву — нейтральний рядок,
    /// без бренд-тексту (фідбек 2026-07-03)
    private var filterEmptyState: some View {
        Text("Тут нічого немає.")
            .font(.emUI(12.5))
            .foregroundStyle(EmbarColors.ink3)
            .padding(.top, 120)
    }
}

/// Швидкий ввід стіка з ВЛАСНОЮ чернеткою (перф-фікс 2026-08-16): поки
/// чернетка була @State самої StickiesView, кожен символ пере-рендерив
/// стіну цілком — на тисячах стіків друк заїкався. Тепер набір тексту не
/// торкається батька взагалі; нагору йде лише готовий текст при сабміті
private struct StickiesQuickInput: View {
    var autoFocus: Bool
    var onCommit: (String) -> Void

    @State private var draft = ""

    var body: some View {
        QuickComposer(placeholder: "Швидка думка…", text: $draft,
                      autoFocus: autoFocus) {
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            // Режим читання: відмова ДО очищення - текст лишається в полі
            guard ProGate.allowCreate() else { return }
            onCommit(text)
            draft = ""
        }
    }
}
