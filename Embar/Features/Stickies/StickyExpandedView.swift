//
//  StickyExpandedView.swift
//  Embar
//
//  Розгорнутий редактор стіка (SPEC §2.4). Плаваюча картка всередині
//  панелі: заголовок, чіпи дедлайну і стіни, деталі. Дії живуть у тулбарі
//  під карткою (StickyExpandedToolbar) — попапів і острівців немає.
//

import SwiftUI
import SwiftData
import UserNotifications

struct StickyExpandedView: View {
    @Bindable var sticker: Sticker
    let palette: Palette
    let walls: [Wall]
    /// Стан тулбара тримає стіна (StickiesView): клік по тлу панелі має
    /// спершу згорнути тулбар, а вже потім закривати стік
    @Binding var toolbarMode: StickyToolbarMode

    var onClose: () -> Void = {}
    var onMature: () -> Void = {}
    // «В тудушки» прибрано зовсім (H3, 2026-08-31): кнопки в UI не було
    // з 2026-08-18, тепер і Home сховано (HomeFeature). Дані-шлях
    // StickerService.addToTodos лишився — повернеться разом із Home
    var onDelete: () -> Void = {}
    var onCreateWall: (String) -> Wall? = { _ in nil }

    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.embarMaterial) private var material

    @State private var newWallName = ""
    @State private var newWallFieldOpen = false
    @State private var hoveringDeadline = false
    @State private var hoveringWall = false
    @State private var hoveringClear = false
    @State private var cardHeight: CGFloat = 0
    @State private var toolbarHeight: CGFloat = 0
    /// Ширина хедера — щоб порахувати, 1 чи 2 рядки займає заголовок
    @State private var titleWidth: CGFloat = 0
    /// Дедлайн міняли, поки редактор розкритий — при згортанні показуємо
    /// пігулку «Нагадаю …» (фідбек 2026-08-18)
    @State private var deadlineDirty = false
    /// Сповіщення явно ВІДХИЛЕНІ (F6, 2026-08-31): нові нагадування не
    /// вмикаємо і нічого не обіцяємо, давні позначаємо рядком «не
    /// прийде». Дзеркало ReminderScheduler.cachedDenied у @State — сам
    /// кеш не спостережуваний, вьюха б не перемалювалась. «Ще не
    /// питали» сюди НЕ входить: лазі-запит при першому нагадуванні
    /// лишається як був (§12)
    @State private var remindersDenied = false
    /// Дедлайн уже згорнули, а система ще не відповіла на запит дозволу:
    /// тост ВИННИЙ, але сказати правду можна лише після відповіді
    /// (ревʼю 2026-08-31, пункт 3 — жодних двох тостів, що суперечать
    /// один одному)
    @State private var promiseDeferred = false
    /// Морф згортається як відмова — усе, що прилетить услід (див.
    /// `cancelMorph`), ігнорується
    @State private var discardingMorph = false

    // MARK: - Чернетки тексту (F5, пункт 3, 2026-08-28)
    //
    // ❗ TextEditor-и пишуть СЮДИ, а не в @Model. Кожен символ прямо в
    // модель — це мутація SwiftData, тобто інвалідація @Query і перерендер
    // усієї стіни на КОЖНУ літеру (виміряно зондом: ~390 мс на 5000 до
    // кеша зрізу, ~80 після — але за кожен натиск). Той самий прийом уже
    // працює в композері стіни (StickiesQuickInput) і в редакторі нотаток.
    //
    // У модель чернетка їде на паузі в друці (0.7 с), при закритті і
    // ОБОВʼЯЗКОВО в onDisappear: стік закривають і повз close() —
    // кліком по тлу панелі, Escape зі стіни, переходом із нотатки
    // (StickiesView.closeExpanded), — і без цієї страховки набране
    // посеред слова просто зникло б
    @State private var titleDraft = ""
    @State private var bodyDraft = ""
    /// Для якого стіка чернетки завантажені: перезавантажувати їх на
    /// кожен рендер означало б затирати недруковане
    @State private var draftStickerID: UUID?

    @AppStorage("wallColorMode") private var colorMode = "random"
    @AppStorage("noWallColorSlot") private var noWallSlot = 0

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
        // Картка тримає лише зміст стіка: заголовок, чіпи дедлайну і стіни,
        // деталі. Усі дії живуть у тулбарі — окремому острівці ПІД карткою
        // (редизайн 2026-08-19). Тулбар висить оверлеєм і не займає місця в
        // потоці: він росте вниз, а картка при цьому не рухається
        GeometryReader { geo in
            card
                .overlay(alignment: .bottom) {
                    toolbar
                        // Точка «низ» тулбара — на 12pt вище його ж верху;
                        // саме вона стає на нижній край картки, тож тулбар
                        // лягає під карткою з проміжком, нічого не зсуваючи
                        .alignmentGuide(.bottom) { $0[.top] - Self.toolbarGap }
                }
                // Верх картки прибитий: стік не центрується, і розкриття
                // морфа його НЕ рухає — тулбар просто росте вниз у вільне
                // місце (фідбек 2026-08-19)
                .padding(.top, topInset(in: geo.size.height))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // І лише коли навіть так не влазить донизу — піднімаємо
                // весь стік рівно на нестачу тією ж плавною анімацією
                .offset(y: -lift(in: geo.size.height))
                .animation(StickyToolbarMode.morph, value: toolbarMode)
                // Висота тулбара міняється не лише від морфа: календар
                // розкривається на місяць уже всередині нього — підйом має
                // їхати разом із ним, а не стрибати
                .animation(StickyToolbarMode.morph, value: toolbarHeight)
        }
        // Escape згортає те, що розкрито, і лише потім закриває
        // редактор зі збереженням (SPEC §9)
        .onExitCommand(perform: escape)
        // Чернетки (F5.3): підняти при появі стіка...
        .onAppear(perform: loadDrafts)
        .onChange(of: sticker.id) { _, _ in loadDrafts() }
        // Свіжий стан дозволу на кожне відкриття стіка...
        .task(id: sticker.id) { await refreshReminderPermission() }
        // ...і при поверненні застосунку наперед: людина сходила в
        // системні параметри кнопкою «Відкрити» і вернулась — рядок
        // «не прийде» має зникнути без перевідкриття стіка
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshReminderPermission() }
        }
        // ...записати на паузі в друці (0.7 с — набір пачкою не платить
        // жодної мутації, а вміст живе в базі задовго до закриття)...
        .task(id: titleDraft) { await flushAfterPause() }
        .task(id: bodyDraft) { await flushAfterPause() }
        // ...і ОБОВʼЯЗКОВО при зникненні: стік закривають і повз close()
        // (клік по тлу, Escape зі стіни, перехід із нотатки) — без цього
        // набране посеред слова зникло б
        .onDisappear(perform: flushDrafts)
        // Тост «Нагадаю …» — на будь-якому шляху згортання дедлайна,
        // зокрема кліком по тлу панелі (його робить сама стіна)
        .onChange(of: toolbarMode) { old, new in
            // Через такт: степер часу докомічує набране з onDisappear —
            // тост має показати ФІНАЛЬНИЙ час, не той, що до коміту
            if old == .deadline, new == .bar {
                DispatchQueue.main.async { announceDeadline() }
            }
        }
    }

    /// Проміжок між карткою і тулбаром
    private static let toolbarGap: CGFloat = 12
    /// Мінімальний відступ від краю панелі
    private static let edgeInset: CGFloat = 10
    /// Верх картки стоїть на чверті висоти поверхні. Це і є той запас, який
    /// можна віддати на підйом, коли розкритий морф не влазить донизу
    private static let topFraction: CGFloat = 0.25

    /// Висота одного рядка заголовка — рахуємо тим самим менеджером, що
    /// верстає текст при редагуванні, щоб два рядки були рівно два
    static let titleLineHeight: CGFloat = {
        let font = NSFont(name: "Inter-SemiBold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .semibold)
        return NSLayoutManager().defaultLineHeight(for: font)
    }()

    /// Деталі — рівно три рядки (між рядками ще й lineSpacing 4)
    static let bodyHeight: CGFloat = {
        let font = NSFont(name: "Inter-Regular", size: 13) ?? .systemFont(ofSize: 13)
        let line = NSLayoutManager().defaultLineHeight(for: font)
        return line * 3 + 4 * 2
    }()

    private func topInset(in available: CGFloat) -> CGFloat {
        max(Self.edgeInset, available * Self.topFraction)
    }

    private func lift(in available: CGFloat) -> CGFloat {
        guard toolbarMode != .bar, cardHeight > 0, toolbarHeight > 0,
              available > 0 else { return 0 }
        let top = topInset(in: available)
        let below = available - top - cardHeight
        let needed = Self.toolbarGap + toolbarHeight + Self.edgeInset
        // Вище за edgeInset від верху панелі не піднімаємось
        return max(0, min(needed - below, max(0, top - Self.edgeInset)))
    }

    private var card: some View {
        // Клік по картці, поки тулбар розкритий, спершу згортає його
        // (фідбек 2026-08-18): ловець висить над кожною секцією окремо
        VStack(alignment: .leading, spacing: 0) {
            header
            chipsRow
            bodyField
        }
        // Острівців усередині картки більше немає, тож ловець кліків —
        // один на всю картку (був по секції на кожен рядок)
        // Клік повз — відмова: нічого не створює (§15.55а)
        .dismissOnTapOutside(toolbarMode != .bar, action: cancelMorph)
        // Виконаний стік лише читається (P2.4): ловець над усією карткою
        // не пускає клік у текст і чіпи, а при спробі чесно пояснює.
        // Скрол довгого заголовка/деталей проходить крізь нього
        .overlay {
            if locked {
                Color.black.opacity(0.001)
                    .onTapGesture(perform: lockedToast)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(stickyFill)
        .background { heightReader($cardHeight) }
    }

    /// Висоти картки й тулбара потрібні, щоб знати, чи влазить розкритий
    /// тулбар донизу (той самий прийом, що в BottomSheet)
    private func heightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { binding.wrappedValue = geo.size.height }
                .onChange(of: geo.size.height) { _, height in
                    binding.wrappedValue = height
                }
        }
    }

    private var toolbar: some View {
        StickyExpandedToolbar(
            mode: $toolbarMode,
            inks: inks,
            pinned: sticker.pinned,
            emojiTag: sticker.emojiTag,
            locked: locked, // виконаний стік не редагується (P2.4)
            onMature: onMature,
            // Миттєво, БЕЗ withAnimation: анімована перескладка масонрі
            // тасує колонки (фідбек 2026-08-22, див. pinWithArrival);
            // стіна за блюром просто перескладається
            onTogglePin: { StickerService.togglePin(sticker) },
            onDelete: onDelete,
            onClose: close
        ) { mode in
            morphContent(mode)
        }
        .background(stickyFill)
        .background { heightReader($toolbarHeight) }
    }

    /// Спільна заливка картки й тулбара — один колір, одна тінь, одне
    /// заокруглення: тулбар має читатись як частина того самого стіка.
    /// Заливка йде фоном (без clipShape): острівки можуть виступати за межі
    /// картки й не обрізаються
    private var stickyFill: some View {
        ZStack {
            // Скло: .thinMaterial під пастеллю@0.4 (острів без clip)
            if material.theme != .opaque {
                RoundedRectangle(cornerRadius: 16).fill(.thinMaterial)
            }
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(material.islandAlpha))
        }
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
    }

    // MARK: - Хедер

    private var header: some View {
        // Заголовок — основний зміст стіка: до двох рядків на видноті,
        // решта прокручується двома пальцями. Це TextEditor, а не TextField:
        // поле віддавало верстку системному польовому редактору, і той
        // показував знизу смужку наступного рядка (фідбек 2026-08-19).
        // Висота — за ФАКТИЧНИМ текстом: один рядок не резервує порожній
        // другий (фідбек 2026-08-20); рівно titleLineHeight × рядки, тож
        // половинок не буває
        ZStack(alignment: .topLeading) {
            if titleDraft.isEmpty {
                Text("Думка…")
                    .font(.emUI(16, weight: .semibold))
                    .foregroundStyle(ink3)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $titleDraft)
                .font(.emUI(16, weight: .semibold))
                .foregroundStyle(ink)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden) // без сірої смуги справа
                .onKeyPress(phases: .down, action: handleReturn)
        }
        .frame(height: Self.titleLineHeight * CGFloat(titleLines))
        .padding(.horizontal, 9)
        .padding(.top, 13)
        .padding(.bottom, 7)
        .background { widthReader($titleWidth) }
    }

    /// Скільки рядків займає заголовок у поточній ширині: 1 або 2 (далі
    /// прокрутка всередині редактора). Міряємо тим самим шрифтом; від
    /// ширини поля віднімаємо паддінги хедера і внутрішні відступи
    /// TextEditor (lineFragmentPadding 5 з обох боків)
    private var titleLines: Int {
        let text = titleDraft
        guard !text.isEmpty else { return 1 }
        guard titleWidth > 28 else { return text.contains("\n") ? 2 : 1 }
        let font = NSFont(name: "Inter-SemiBold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .semibold)
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: titleWidth - 18 - 10,
                         height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font], context: nil)
        return rect.height > Self.titleLineHeight * 1.5 ? 2 : 1
    }

    private func widthReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { binding.wrappedValue = geo.size.width }
                .onChange(of: geo.size.width) { _, width in
                    binding.wrappedValue = width
                }
        }
    }

    /// Return у заголовку й деталях: Shift+Return — новий рядок у позиції
    /// курсора, самий Return — зберегти й закрити.
    ///
    /// ❗ Ловимо ВСІ клавіші й звіряємо самі: `onKeyPress(.return, …)`
    /// пропускав натиск із модифікатором, тож Shift+Return не доходив
    /// (фідбек 2026-08-19). Рядок вставляємо вручну: системний біндінг
    /// спрацьовував не завжди (фідбек 2026-08-18)
    private func handleReturn(_ press: KeyPress) -> KeyPress.Result {
        guard press.key == .return else { return .ignored }
        guard press.modifiers.contains(.shift) else {
            close()
            return .handled
        }
        guard let editor = focusedTextView else { return .ignored }
        editor.insertNewlineIgnoringFieldEditor(nil)
        return .handled
    }

    /// Поле, що зараз редагують. Панель — nonactivating NSPanel і завжди
    /// вдає з себе key, тож на NSApp.keyWindow покладатись не можна:
    /// шукаємо перше вікно з текстовим першим відповідачем
    private var focusedTextView: NSTextView? {
        for window in NSApp.windows {
            if let editor = window.firstResponder as? NSTextView { return editor }
        }
        return nil
    }

    // MARK: - Дедлайн (вміст тулбара)

    /// Усе про час в одному місці: швидкі пігулки, календар і «Нагадати».
    /// Окремого нагадування більше немає — воно живе тут (2026-08-19)
    private var deadlineMorph: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Галочка зʼявляється лише після першого дотику до дати чи
            // нагадування — до того це просто «закрити»
            morphHeader("Дедлайн", confirmable: deadlineDirty)
            // Швидкі пігулки: активна — та, що збігається з дедлайном за днем
            pillRow([
                (String(localized: "Сьогодні", comment: "Швидкий вибір дедлайну стіка"), isDeadline(endOfDay(0)), { setDeadline(endOfDay(0)) }),
                (String(localized: "Завтра", comment: "Швидкий вибір дедлайну стіка"), isDeadline(endOfDay(1)), { setDeadline(endOfDay(1)) }),
                (String(localized: "Цей тиждень", comment: "Швидкий вибір дедлайну стіка"), isDeadline(endOfWeek()), { setDeadline(endOfWeek()) }),
            ])
            EmbarCalendarPicker(date: deadlineBinding, inks: inks) { confirmMorph() }
            notifyRow
            // Дозвіл відкликали ПІСЛЯ того, як нагадування поставили:
            // саме нагадування не чіпаємо (F6, рішення 2026-08-31 — нічого
            // не видаляти мовчки), але чесно показуємо, що воно не прийде,
            // і даємо двері в системні параметри
            if remindersDenied, sticker.notifyOffsetMinutes != nil {
                remindersDeniedRow
            }
        }
    }

    /// «Не прийде» + кнопка в системні параметри сповіщень. Стиль кнопки —
    /// як «Відкрити ›» у налаштуваннях стіків (та сама дія, той сам вигляд)
    private var remindersDeniedRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.slash")
                .font(.system(size: 10))
                .foregroundStyle(ink3)
            Text("Нагадування не прийде: сповіщення вимкнені")
                .font(.emUI(10.5))
                .foregroundStyle(ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: ReminderScheduler.openSystemNotificationSettings) {
                HStack(spacing: 3) {
                    Text("Відкрити").font(.emUI(10.5, weight: .medium))
                    Image(systemName: "chevron.right").font(.system(size: 8))
                }
                .foregroundStyle(ink2)
            }
            .buttonStyle(.plain)
        }
    }

    /// Освіжити кеш дозволу і своє дзеркало (F6). ensureAuthorized без
    /// ask: статус лише читається, системний запит звідси не зʼявляється
    private func refreshReminderPermission() async {
        _ = await ReminderScheduler.ensureAuthorized(ask: false)
        remindersDenied = ReminderScheduler.cachedDenied
    }

    /// «Нагадати» — степер «− значення +». Праворуч у цьому ж рядку —
    /// смітник «прибрати дедлайн»: текстова кнопка тіснила пігулку, і та
    /// ламала слово на три рядки (фідбек 2026-08-19)
    private var notifyRow: some View {
        HStack(spacing: 8) {
            sectionCaption("Нагадати")
            EmbarStepper(style: .filled, inks: inks,
                         onMinus: { stepNotify(-1) },
                         onPlus: { stepNotify(1) }) {
                // Ширина пігулки — за найдовшим варіантом (решта лежать
                // невидимими): інакше «+» тікав би з-під курсора щоразу,
                // як міняється значення. fixedSize не дає ряду її стиснути
                ZStack {
                    ForEach(StickyNotify.allLabels, id: \.self) { label in
                        Text(label).hidden()
                    }
                    Text(notifyLabel)
                }
                .font(.emUI(10.5, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if sticker.deadline != nil {
                clearDeadlineButton
            }
        }
    }

    private var clearDeadlineButton: some View {
        Button { clearDeadline(); collapseToolbar() } label: {
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundStyle(hoveringClear ? EmbarColors.danger : ink3)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverDarken(Circle())
        .onHover { hoveringClear = $0 }
        .help("Прибрати дедлайн")
    }

    private var notifyLabel: String {
        sticker.notifyOffsetMinutes.map(StickyNotify.label(for:))
            ?? StickyNotify.offLabel
    }

    private func stepNotify(_ direction: Int) {
        // Зсув рахується від дедлайну, а якщо його ще нема — від дати,
        // яку людина бачить у календарі просто над степером: саме її ми
        // й приймемо в setNotify
        let base = sticker.deadline ?? deadlineBinding.wrappedValue
        let next = StickyNotify.step(from: sticker.notifyOffsetMinutes,
                                     by: direction, deadline: base)
        guard next != sticker.notifyOffsetMinutes else { return }
        setNotify(next)
    }

    /// ❗ Зсув без дедлайну не існує: відлічувати нема від чого. Раніше
    /// він усе одно писався в базу, і закритий морф лишав сироту —
    /// наступна швидка пігулка мовчки успадковувала покинуте «за день»
    /// (ревʼю 2026-08-20). Тож спершу приймаємо запропоновану дату
    private func setNotify(_ minutes: Int?) {
        // Явна відмова в сповіщеннях: нагадування не вмикаємо і чесно
        // кажемо чому (F6) — обіцяти нема чого. Вимкнути (nil) можна
        // завжди; «ще не питали» проходить далі до лазі-запиту
        if minutes != nil, ReminderScheduler.cachedDenied {
            remindersDeniedToast()
            return
        }
        if sticker.deadline == nil {
            applyDeadline(deadlineBinding.wrappedValue)
            guard sticker.deadline != nil else { return } // дату відхилили
        }
        let wasOff = sticker.notifyOffsetMinutes == nil
        sticker.notifyOffsetMinutes = minutes
        deadlineDirty = true
        replanNotification(justEnabled: wasOff && minutes != nil)
    }

    /// Шапка розкритого тулбара: підпис і кнопка справа.
    ///
    /// Поки людина нічого не чіпала, там ХРЕСТИК — він просто закриває і
    /// нічого не зберігає (фідбек 2026-08-19: заглянув подивитись, тиснув
    /// галочку — і отримав дедлайн, якого не просив). Щойно щось торкнули,
    /// хрестик плавно переростає в галочку «зберегти й закрити»
    private func morphHeader(_ title: LocalizedStringKey,
                             confirmable: Bool = false) -> some View {
        HStack(alignment: .center) {
            sectionCaption(title)
            Spacer()
            Button { confirmable ? confirmMorph() : cancelMorph() } label: {
                Image(systemName: confirmable ? "checkmark" : "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ink2)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(inks.buttonBg))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverDarken(Circle())
            .animation(StickyToolbarMode.morph, value: confirmable)
        }
    }

    private func sectionCaption(_ title: LocalizedStringKey) -> some View {
        // .textCase, а не .uppercased(): регістр — уже до перекладу (i18n)
        Text(title)
            .textCase(.uppercase)
            .font(.emUI(10, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(ink3)
    }

    /// Чіп «активний», якщо дедлайн стоїть у той самий день
    private func isDeadline(_ date: Date) -> Bool {
        guard let deadline = sticker.deadline else { return false }
        return Calendar.current.isDate(deadline, inSameDayAs: date)
    }

    // MARK: - Чіпи картки (дедлайн · стіна)

    /// Два голі чіпи через крапку-роздільник, як у макеті: жодних плашок —
    /// картка лишається текстом, а не панеллю кнопок
    private var chipsRow: some View {
        HStack(spacing: 8) {
            deadlineChip
            Text(verbatim: "·").font(.emUI(11)).foregroundStyle(ink3)
            wallChip
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    /// Дедлайн: дзвіночок, коли про нього ще й нагадають, інакше календар;
    /// перекреслений дзвіночок — нагадування є, але сповіщення відхилені,
    /// тож воно не прийде (F6: видно просто з чіпа, не лише в тулбарі).
    /// Гола кнопка без фону навіть на hover — курсор просто червонить текст
    /// (фідбек 2026-08-18)
    private var deadlineChip: some View {
        Button { openToolbar(.deadline) } label: {
            HStack(spacing: 5) {
                Image(systemName: notifyDate != nil
                      ? (remindersDenied ? "bell.slash" : "bell") : "calendar")
                    .font(.system(size: 10.5))
                Text(sticker.deadline.map(dateLabel)
                     ?? String(localized: "Додати дедлайн", comment: "Кнопка у розгорнутому стіку, коли дедлайну ще нема"))
                    .lineLimit(1)
            }
            .font(.emUI(11, weight: sticker.deadline == nil ? .regular : .medium))
            .foregroundStyle(
                deadlinePast
                    // Минулий дедлайн уже не сигналить (P2.7) — сірий,
                    // під курсором лише трохи темнішає
                    ? (hoveringDeadline ? ink2 : ink3)
                    : ((deadlineTintActive || hoveringDeadline) ? deadlineRed : ink3)
            )
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // На виконаному стіку чіп не «оживає» під курсором (P2.4)
        .onHover { hoveringDeadline = locked ? false : $0 }
    }

    /// Стіна: тека і назва
    private var wallChip: some View {
        Button { openToolbar(.wall) } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 10.5))
                Text((activeWallName
                      ?? String(localized: "Стіна", comment: "Чіп у розгорнутому стіку, коли стіну не обрано"))
                    .truncatedChip())
                    .lineLimit(1)
            }
            .font(.emUI(11, weight: activeWallName == nil ? .regular : .medium))
            // Один тон із «Додати дедлайн»: обидва чіпи порожні — обидва
            // бліді; названа стіна темнішає, як темнішає заданий дедлайн
            .foregroundStyle(wallTint)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // На виконаному стіку чіп не «оживає» під курсором (P2.4)
        .onHover { hoveringWall = locked ? false : $0 }
    }

    private var wallTint: Color {
        if hoveringWall || toolbarMode == .wall { return ink }
        return activeWallName == nil ? ink3 : ink2
    }

    // MARK: - Емоджі-тег

    /// Куровані 24 стікери (рішення 2026-07-21): перший ряд — кольорові
    /// крапки, далі — символи (🌙 до пари 🌞). Без пошуку
    private static let emojiChoices: [String] = [
        "🔴", "🟠", "🟡", "🟢", "🔵", "🟣",
        "💡", "🔥", "❤️", "📚", "💼", "🎨",
        "🧠", "💰", "🛒", "🏠", "✈️", "💎",
        "🎀", "🌺", "🐚", "🪐", "🌞", "🌙",
    ]

    /// Сітка емоджі — вміст тулбара в режимі .emoji. Вісім колонок на всю
    /// ширину тулбара: три щільні ряди замість чотирьох розкиданих
    /// (фідбек 2026-08-19; було шість колонок, коли пікер був попапом)
    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4),
                                     count: 8), spacing: 4) {
                ForEach(Self.emojiChoices, id: \.self) { emoji in
                    Button {
                        // Повторний тап по вибраному — зняти вибір (P2.5)
                        sticker.emojiTag =
                            sticker.emojiTag == emoji ? nil : emoji // миттєво (§7.2-A)
                        StickerMutation.changed(sticker) // кеш зрізу (F5)
                        collapseToolbar()
                    } label: {
                        Text(emoji)
                            .font(.system(size: 16))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(sticker.emojiTag == emoji
                                      ? inks.wash(0.1) : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if sticker.emojiTag != nil {
                Button {
                    sticker.emojiTag = nil
                    StickerMutation.changed(sticker) // кеш зрізу (F5)
                    collapseToolbar()
                } label: {
                    Text("Прибрати емоджі")
                        .font(.emUI(11.5, weight: .medium))
                        .foregroundStyle(ink2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Дедлайн «сигналить» червоним лише ПІСЛЯ згортання свого редактора
    /// (фідбек 2026-08-18)
    private var deadlineTintActive: Bool {
        sticker.deadline != nil && toolbarMode != .deadline
    }

    /// Строк уже минув (P2.7): чіп і бейдж на картці сіріють —
    /// червоним сигналить лише те, що ще попереду
    private var deadlinePast: Bool {
        sticker.deadline.map { $0 < .now } ?? false
    }

    /// Вибір стіни — вміст тулбара. Один ряд чіпів: «Без стіни», стіни
    /// (активна — чорна) і пунктирний «+ Нова стіна», що розкривається в
    /// інлайн-поле (редизайн 2026-08-18: повнорядкове поле забирало
    /// забагато місця)
    private var wallMorph: some View {
        VStack(alignment: .leading, spacing: 8) {
            morphHeader("Стіна")
            wallRows
        }
    }

    /// Фактична висота рядів пігулок — щоб не різати короткий список (P2.8)
    @State private var wallRowsHeight: CGFloat = 0
    /// ~3 ряди пігулок (22pt ряд + 6pt міжряддя), далі прокрутка
    private static let wallRowsCap: CGFloat = 84

    /// Ряди стін: шапка «Стіна» з хрестиком стоїть на місці, а список при
    /// переповненні прокручується і йде у fade ПІД шапкою (P2.8, фідбек
    /// 2026-09-01: розчинення зверху, як скрізь під шапками). Fade —
    /// маскою, а не градієнтом-накладкою: тло тулбара — напівпрозоре
    /// скло під пастеллю, суцільним кольором його не підробити
    private var wallRows: some View {
        let capped = wallRowsHeight > Self.wallRowsCap
        // Reader - щоб поле нової стіни (і пігулка ліміту) не лишались
        // за нижнім зрізом капнутого списку (фідбек 2026-09-04)
        return ScrollViewReader { proxy in
        ScrollView {
            FlowRow(spacing: 5) {
                optionPill(String(localized: "Без стіни", comment: "Опція вибору стіни — жодної"),
                           active: activeWallName == nil && !newWallFieldOpen) {
                    sticker.wall = nil
                    StickerMutation.changed(sticker) // кеш зрізу (F5)
                    collapseToolbar()
                }
                ForEach(walls) { wall in
                    optionPill(wall.name.truncatedChip(),
                               active: sticker.wall == wall) {
                        sticker.wall = wall
                        StickerMutation.changed(sticker) // кеш зрізу (F5)
                        collapseToolbar()
                    }
                }
                if newWallFieldOpen {
                    newWallField
                        .id(Self.newWallFieldID)
                        .onAppear { revealNewWallField(proxy) }
                } else {
                    newWallChip
                }
            }
            .background { heightReader($wallRowsHeight) }
        }
        .scrollIndicators(.hidden) // правило проєкту
        .frame(height: capped ? Self.wallRowsCap : nil)
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: capped ? 18 : 0)
                Rectangle()
            }
        }
        }
    }

    /// Пунктирний чіп «+ Нова стіна»
    private var newWallChip: some View {
        Button {
            newWallFieldOpen = true
        } label: {
            Text("+ \(String(localized: "Нова стіна", comment: "Чіп створення стіни в острівці стін"))")
                .font(.emUI(12))
                .foregroundStyle(ink3)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    Capsule().strokeBorder(
                        ink3.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverDarken(Capsule())
    }

    /// Інлайн-поле назви нової стіни на місці чіпа. Enter створює,
    /// Escape/втрата фокуса ховає назад у чіп (як NewChipField у барі стін)
    private var newWallField: some View {
        NewChipField(placeholder: "Нова стіна", text: $newWallName,
                     onSubmit: addWall,
                     onCancel: { newWallFieldOpen = false; newWallName = "" },
                     onLimitHit: { if let p = wallRowsProxy { revealNewWallField(p) } },
                     style: .tinted)
    }

    private static let newWallFieldID = "new-wall-field"
    /// Проксі списку стін - живе, поки острівець розгорнутий
    @State private var wallRowsProxy: ScrollViewProxy?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Догорнути до поля нової стіни (з пігулкою). Наступним тіком:
    /// у момент виклику вони ще без розміру; Reduce Motion - миттєво
    private func revealNewWallField(_ proxy: ScrollViewProxy) {
        wallRowsProxy = proxy
        DispatchQueue.main.async {
            EmbarMotion.reorder(reduceMotion: reduceMotion) {
                proxy.scrollTo(Self.newWallFieldID, anchor: .bottom)
            }
        }
    }

    // MARK: - Тіло

    private var bodyField: some View {
        // TextEditor (не TextField): Shift+Enter вставляє новий рядок у позиції
        // курсора, Enter — зберігає і закриває стік
        ZStack(alignment: .topLeading) {
            if bodyDraft.isEmpty {
                // Дрібніший і блідіший за сам текст — це підказка, а не
                // вміст. Відступ 5pt — власний внутрішній відступ
                // TextEditor: інакше підказка стоїть лівіше за курсор
                Text("Додати деталі…")
                    .font(.emUI(11.5))
                    .foregroundStyle(ink3.opacity(0.55))
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $bodyDraft)
                .font(.emUI(13))
                .foregroundStyle(ink)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                // Рівно три рядки, далі прокрутка — пʼять зяяли порожнечею
                // (фідбек 2026-08-19). Рахуємо так само, як заголовок
                .frame(height: Self.bodyHeight)
                .onKeyPress(phases: .down, action: handleReturn)
        }
        // Легка тонована підкладка — афорданс поля вводу: без неї не було
        // видно, що сюди можна писати (фідбек 2026-08-19). Роздільника над
        // нею немає — підкладка сама відділяє деталі від заголовка
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(inks.wash(0.04)))
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    // MARK: - Вміст розкритого тулбара

    @ViewBuilder
    private func morphContent(_ mode: StickyToolbarMode) -> some View {
        switch mode {
        case .deadline: deadlineMorph
        case .emoji: emojiPicker
        case .wall: wallMorph
        case .bar: EmptyView()
        }
    }

    /// Виконаний стік не редагується (P2.4): морфи не відкриваються,
    /// текст і чіпи лише читаються. Повернути в активні можна галочкою
    /// на стіні — тут лише чесний тост при спробі щось змінити
    private var locked: Bool { sticker.done }

    private func lockedToast() {
        toasts.showMini("Виконані стіки не можна редагувати")
    }

    /// Розкрити тулбар (повторний клік по тій самій дії — згорнути).
    /// Анімацію ставить сам тулбар, тож withAnimation тут не треба
    private func openToolbar(_ mode: StickyToolbarMode) {
        guard !locked else { lockedToast(); return } // P2.4
        guard toolbarMode != mode else { collapseToolbar(); return }
        toolbarMode = mode
    }

    private func collapseToolbar() {
        toolbarMode = .bar
    }

    /// Згорнути морф як ВІДМОВУ: хрестик у шапці, клік повз, Escape.
    ///
    /// ❗ Степер часу комітить недонабране у своєму `onDisappear` — тобто
    /// вже ПІСЛЯ того, як ми згорнули морф, і його запис приходить сюди,
    /// у `deadlineBinding`. Без цього прапорця «тицьнув хвилини, набрав,
    /// передумав і закрив хрестиком» створювало дедлайн разом із
    /// нагадуванням — рівно та скарга, від якої хрестик і зʼявився
    /// (ревʼю 2026-08-20)
    private func cancelMorph() {
        discardingMorph = true
        collapseToolbar()
        // Прапорець живе рівно один прохід оновлення: onDisappear
        // трапляється всередині нього, а це вже після
        DispatchQueue.main.async { discardingMorph = false }
    }

    /// Явне підтвердження (галочка, Enter у календарі): якщо власної дати
    /// ще нема — зберігаємо ЗАПРОПОНОВАНУ (округлене «зараз»), яку людина
    /// бачить у пікері. Раніше «прийняти як є» не робило нічого (баг
    /// 2026-08-18). Клік повз — то відмова, він нічого не створює
    private func confirmMorph() {
        if toolbarMode == .deadline, sticker.deadline == nil {
            applyDeadline(deadlineBinding.wrappedValue)
        }
        collapseToolbar()
    }

    /// Пігулка «Нагадаю …» після згортання дедлайна — якщо його справді
    /// міняли (будь-яким шляхом: пігулка, календар, тайп)
    private func announceDeadline() {
        defer { deadlineDirty = false }
        guard deadlineDirty else { return }
        if ReminderScheduler.cachedDenied, sticker.deadline != nil {
            // Дедлайн збережено, але нагадування не буде: замість
            // обіцянки — чому і двері в параметри (F6, нічого не обіцяти).
            // Покриває і швидкі пігулки, де тулбар згортається одразу
            // і рядка «не прийде» людина не бачила
            remindersDeniedToast()
        } else if !ReminderScheduler.cachedResolved,
                  ReminderScheduler.job(for: sticker) != nil {
            // Системне віконце дозволу ще на екрані: МОВЧИМО. Тост скаже
            // правду, коли людина відповість (onResolved нижче) — інакше
            // «Нагадаю о …» встигало прозвучати обіцянкою навмання, а
            // після відмови його спростовував другий тост (ревʼю
            // 2026-08-31, пункт 3)
            promiseDeferred = true
        } else if let at = notifyDate {
            toasts.showMini("Нагадаю \(dateLabel(at))")
        }
    }

    // MARK: - Спільні дрібниці

    /// Пігулки опцій: (назва, активна?, дія). Активна — чорна заливка з
    /// білим текстом (редизайн 2026-08-18, як у макеті)
    private func pillRow(_ options: [(String, Bool, () -> Void)]) -> some View {
        FlowRow(spacing: 5) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                optionPill(opt.0, active: opt.1, action: opt.2)
            }
        }
    }

    private func optionPill(_ label: String, active: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.emUI(11.5, weight: active ? .medium : .regular))
                .foregroundStyle(active ? .white : ink2)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(active ? EmbarColors.ink
                                                  : inks.wash(0.06)))
        }
        .buttonStyle(.plain)
        .hoverDarken(Capsule())
    }

    /// Коли прийде сповіщення (дедлайн мінус зсув) — nil, якщо нагадувати
    /// не просили
    private var notifyDate: Date? {
        guard let deadline = sticker.deadline,
              let offset = sticker.notifyOffsetMinutes else { return nil }
        return StickyNotify.triggerDate(deadline: deadline, offsetMinutes: offset)
    }

    /// Минуле — з допуском на поточну хвилину (пікер зрізає секунди)
    private func isFuture(_ date: Date) -> Bool {
        date > Date.now.addingTimeInterval(-60)
    }

    /// Error state: дата/час у минулому — червона пігулка, значення не
    /// зберігаємо (фідбек 2026-08-18)
    private func rejectPast() {
        toasts.showMini("Цей час уже минув", style: .danger)
    }

    private func close() {
        flushDrafts()
        sticker.updatedAt = .now
        onClose()
    }

    // MARK: - Чернетки: завантаження і запис у модель

    private func loadDrafts() {
        guard draftStickerID != sticker.id else { return }
        draftStickerID = sticker.id
        titleDraft = sticker.text
        bodyDraft = sticker.bodyText
    }

    /// Пауза в друці — момент записати чернетку в базу. Скасовується
    /// автоматично: .task(id:) знімає завдання на кожен новий символ
    private func flushAfterPause() async {
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        flushDrafts()
    }

    /// Записати чернетки в модель. Без змін — no-op: інакше кожне
    /// відкрити-закрити бампало б updatedAt на порожньому місці
    private func flushDrafts() {
        guard draftStickerID == sticker.id else { return }
        if sticker.text != titleDraft { sticker.text = titleDraft }
        if sticker.bodyText != bodyDraft { sticker.bodyText = bodyDraft }
    }

    /// Escape: спершу згортаємо розкрите (тулбар, острівець), і лише коли
    /// згортати нічого — закриваємо сам стік
    private func escape() {
        if toolbarMode != .bar {
            cancelMorph() // Escape — теж відмова
        } else {
            close()
        }
    }

    private func setDeadline(_ date: Date) {
        applyDeadline(date)
        collapseToolbar()
    }

    private var deadlineBinding: Binding<Date> {
        // Дефолт — «зараз», округлене вгору до кратної 5 хвилини
        // (3:33 → 3:35), щоб степер одразу ходив по рівних поділках.
        // Кастомна дата НЕ закриває острівець — інакше перший дотик до
        // календаря миттєво його ховав
        Binding(get: { sticker.deadline ?? EmbarTimeStepper.roundUpToStep(.now) },
                set: { applyDeadline($0) })
    }

    /// Новий дедлайн. Перше встановлення само вмикає нагадування «у момент»
    /// (нагадування злилося з дедлайном — окремо його вже не поставити)
    private func applyDeadline(_ date: Date) {
        // Морф уже згорнули відмовою — це запізнілий коміт степера,
        // а не воля людини (див. cancelMorph)
        guard !discardingMorph else { return }
        guard isFuture(date) else { rejectPast(); return }
        sticker.deadline = date
        var justEnabled = false
        if sticker.notifyOffsetMinutes == nil {
            // Перший дедлайн сам вмикає нагадування «у момент» — але не
            // при явній відмові в сповіщеннях: тоді зберігаємо дедлайн
            // БЕЗ нагадування, чому — скаже тост при згортанні (F6).
            // «Ще не питали» вмикає як завжди: лазі-запит у replan
            if !ReminderScheduler.cachedDenied {
                sticker.notifyOffsetMinutes = 0
                justEnabled = true
            }
        } else {
            // Новий дедлайн міг зробити наявний зсув недосяжним («за
            // день» при дедлайні на сьогодні) — опускаємо до найближчого,
            // що ще попереду. Інакше дзвіночок обіцяв би сповіщення,
            // якого система ніколи не отримає (ревʼю 2026-08-20)
            sticker.notifyOffsetMinutes = StickyNotify.nearestReachable(
                sticker.notifyOffsetMinutes, deadline: date)
        }
        deadlineDirty = true
        StickerMutation.changed(sticker) // кеш зрізу (F5): членство/сорт «Дедлайн»
        replanNotification(justEnabled: justEnabled)
    }

    private func clearDeadline() {
        sticker.deadline = nil
        sticker.notifyOffsetMinutes = nil
        deadlineDirty = false
        StickerMutation.changed(sticker) // кеш зрізу (F5)
        replanNotification()
    }

    /// Дедлайн чи зсув змінились — переставити сповіщення. Дозвіл питаємо
    /// саме тут: це дія людини, а не фон.
    ///
    /// `justEnabled` — нагадування ввімкнула САМЕ ЦЯ дія (перший дедлайн
    /// чи степер з «вимкнено»): якщо людина відхилила системний запит,
    /// прибираємо його з моделі — обіцянки, якої не буде, не зберігаємо
    /// (F6). Давнє нагадування (дозвіл відкликали пізніше) НЕ чіпаємо —
    /// його чесно показує рядок «не прийде» (рішення 2026-08-31)
    private func replanNotification(justEnabled: Bool = false) {
        ReminderScheduler.replan(for: sticker, askPermission: true) { granted in
            // ❗ Модель пережила `await` системного віконця — до дотику
            // перевіряємо, що вона жива: обидві ознаки, як у кеші зрізу
            // (`isDeleted` живе лише до save). Дотик до вибитого @Model
            // валить процес (ревʼю 2026-08-31, пункт 4)
            let alive = !sticker.isDeleted && sticker.modelContext != nil
            remindersDenied = ReminderScheduler.cachedDenied
            if !granted, justEnabled, alive {
                // Обіцянки, якої не буде, не зберігаємо: дедлайн лишається,
                // нагадування знімаємо (F6)
                sticker.notifyOffsetMinutes = nil
            }
            guard promiseDeferred else { return }
            promiseDeferred = false
            if granted, alive, let at = notifyDate {
                toasts.showMini("Нагадаю \(dateLabel(at))")
            } else if !granted {
                remindersDeniedToast()
            }
        }
    }

    /// Тост «потрібен дозвіл» + двері в системні параметри (F6). Той
    /// самий компонент, що undo-тост: повідомлення з кнопкою дії
    private func remindersDeniedToast() {
        toasts.showUndo(
            message: "Щоб нагадати, Embar потрібен дозвіл на сповіщення",
            actionLabel: "Відкрити",
            action: ReminderScheduler.openSystemNotificationSettings)
    }

    private func addWall() {
        // Режим читання: поле лишається відкритим із набраною назвою
        guard ProGate.allowCreate() else { return }
        let name = newWallName.trimmingCharacters(in: .whitespacesAndNewlines)
        newWallName = ""
        newWallFieldOpen = false
        guard let wall = onCreateWall(name) else { return }
        sticker.wall = wall
        StickerMutation.changed(sticker) // кеш зрізу (F5)
        collapseToolbar()
    }

    /// Назва стіни для чіпа — лише якщо стіна не soft-видалена
    private var activeWallName: String? {
        guard let wall = sticker.wall, wall.deletedAt == nil else { return nil }
        return wall.name
    }

    // MARK: - Дати (українською — StickyDateFormat, фідбек 2026-07-19)

    private func dateLabel(_ date: Date) -> String {
        StickyDateFormat.shortDateTime(date)
    }

    private func endOfDay(_ offset: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: offset, to: .now)!
        return cal.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
    }

    private func endOfWeek() -> Date {
        let cal = Calendar.current
        let interval = cal.dateInterval(of: .weekOfYear, for: .now)
        return interval.map { $0.end.addingTimeInterval(-1) } ?? endOfDay(6)
    }

}
