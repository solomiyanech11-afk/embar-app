#if DEBUG
//
//  SandboxPanel.swift
//  Embar
//
//  Пульт тестового середовища — маленьке вікно у верхньому лівому куті,
//  яке існує ТІЛЬКИ під `-EmbarTestSandbox`. Три команди:
//
//  · скинути онбординг — прапорці показу й посіву, разом із засіяними
//    стіками, щоб знайомство почалось із чистого аркуша;
//  · засіяти 5000 стіків — стрес-тест стіни (кількість можна задати
//    аргументом `-SandboxSeedStress 20000`);
//  · очистити пісочницю — знести файл бази і суїт налаштувань, після
//    чого застосунок перезапускається порожнім;
//  · монетизація (SPEC §15.77) — скинути trial, «прожити» N днів
//    (зсув якоря назад), тристановий оверайд pro (0 = «не pro» —
//    єдиний шлях побачити режим читання в пісочниці, бо RevenueCat
//    тут не конфігурується і справжнього кешу не буває).
//
//  Кожна команда спершу питає SandboxEnvironment.isActive і без нього
//  НІЧОГО не робить: навіть якщо цей код якось запустять у звичайному
//  режимі, реальні дані він не зачепить.
//
//  Ті самі команди можна ввімкнути галочкою в схемі як аргументи запуску:
//  -SandboxResetOnboarding · -SandboxSeedStress N · -SandboxWipe ·
//  -SandboxResetTrial · -SandboxTrialShiftDays N · -SandboxProOverride 1|0
//

import AppKit
import SwiftUI
import SwiftData

@MainActor
enum SandboxDebug {
    /// Скільки стіків сіє стрес-тест за замовчуванням
    static let defaultStressCount = 5000

    // MARK: - Команди

    /// Онбординг наново: прапорці + прибрати навчальні стіки
    @discardableResult
    static func resetOnboarding(in context: ModelContext) -> Bool {
        guard SandboxEnvironment.isActive else { return false }
        OnboardingStore.isCompleted = false
        OnboardingStore.stickersSeeded = false
        OnboardingStore.noteSeeded = false
        OnboardingStore.notebookSeeded = false
        EmbarDefaults.store.set(false, forKey: SettingsGlow.storageKey)
        // Кнопка «Прибрати навчальні стіки»: визрілість тепер персистентна
        // (P2.6) — без скидання повторний прогін онбордингу показував би
        // її одразу, без свого 5с-відліку
        EmbarDefaults.store.set(false, forKey: "tutorialSweepReady")
        EmbarDefaults.store.set(false, forKey: "tutorialSweepDismissed")
        OnboardingSeeder.removeSeeded(in: context)
        try? context.save()
        StickerMutation.bulkChanged() // кеш зрізу: hard delete навчальних (F5)
        NoteMutation.bulkChanged()
        return true
    }

    /// Стрес-тест: N стіків + N нотаток + блокнот рідера з N записами
    /// одним пакетом (нотатки/рідер додано 2026-08-16 — там теж будуть
    /// тисячі, перевіряємо всі три поверхні)
    @discardableResult
    static func seedStress(_ count: Int, in context: ModelContext) -> Bool {
        guard SandboxEnvironment.isActive else { return false }
        let now = Date.now
        for i in 0..<count {
            let sticker = Sticker(text: "Стрес-тест #\(i + 1)", colorIndex: i % 5)
            // Рознесені в часі — інакше сортування стіни впиралось би в
            // однакові дати й порядок стрибав би між запусками
            sticker.createdAt = now.addingTimeInterval(-Double(i))
            sticker.updatedAt = sticker.createdAt
            // Кожен пʼятий виконаний — щоб фільтри й архів теж мали роботу
            sticker.done = i % 5 == 0
            context.insert(sticker)
        }
        for i in 0..<count {
            let note = Note()
            note.title = "Стрес-нотатка #\(i + 1)"
            // Тіло з текстом — щоб пошук по вмісту мав що сканувати
            note.content = "Абзац для пошуку і превʼю картки. "
                + "Думки визрівають повільно, але впевнено — рядок №\(i + 1)."
            note.createdAt = now.addingTimeInterval(-Double(i))
            note.updatedAt = note.createdAt
            note.pinned = i % 97 == 0
            context.insert(note)
        }
        let book = ReaderBook(title: "Стрес-блокнот")
        context.insert(book)
        let kinds: [ReaderEntryKind] = [.thought, .quote, .question, .insight]
        for i in 0..<count {
            let kind = kinds[i % kinds.count]
            let entry = ReaderEntry(
                kind: kind,
                text: "Стрес-запис #\(i + 1) — думка з тегом #стрес для фільтрів")
            entry.createdAt = now.addingTimeInterval(-Double(i))
            entry.updatedAt = entry.createdAt
            entry.favorite = i % 10 == 0
            if kind == .quote { entry.author = "Автор №\(i % 20 + 1)" }
            entry.book = book
            context.insert(entry)
        }
        try? context.save()
        NSLog("Пісочниця: засіяно \(count) стіків + \(count) нотаток + блокнот із \(count) записами")
        StickerMutation.bulkChanged() // кеш зрізу: стрес-пачка (F5)
        NoteMutation.bulkChanged()
        return true
    }

    // MARK: - Монетизація (SPEC §15.77)

    /// Trial наново: якір з обох рівнів, оверайд і кеш геть, новий
    /// «зараз» - ніби перший запуск
    @discardableResult
    static func resetTrial() -> Bool {
        guard SandboxEnvironment.isActive else { return false }
        TrialAnchor.reset()
        let d = EmbarDefaults.store
        d.removeObject(forKey: EntitlementStore.sandboxOverrideKey)
        d.removeObject(forKey: EntitlementStore.cacheKey)
        d.removeObject(forKey: EntitlementStore.cacheSubscriptionKey)
        EntitlementStore.shared.bootstrap()
        return true
    }

    /// «Перевести дату вперед»: зсунути якір назад на N днів і
    /// перерахувати стан (15 - і trial минув)
    @discardableResult
    static func shiftTrial(byDays days: Int) -> Bool {
        guard SandboxEnvironment.isActive else { return false }
        let shifted = TrialAnchor.shift(byDays: days)
        // Перераховуємо ЗАВЖДИ, а не лише при успіху: якщо якір
        // зсунувся хоч в одному рівні, стан має це побачити одразу
        EntitlementStore.shared.bootstrap()
        return shifted
    }

    /// Тристановий цикл оверайду pro: немає → 1 (pro) → 0 («кеш каже
    /// не pro» - єдиний шлях до режиму читання в пісочниці) → немає
    @discardableResult
    static func cycleProOverride() -> Bool {
        guard SandboxEnvironment.isActive else { return false }
        let d = EmbarDefaults.store
        switch d.object(forKey: EntitlementStore.sandboxOverrideKey) as? Int {
        case nil: d.set(1, forKey: EntitlementStore.sandboxOverrideKey)
        case 1:   d.set(0, forKey: EntitlementStore.sandboxOverrideKey)
        default:  d.removeObject(forKey: EntitlementStore.sandboxOverrideKey)
        }
        EntitlementStore.shared.recompute()
        return true
    }

    /// Прогін режиму системного діалогу без реальної покупки: рівні
    /// вікон до / під час / після (блокер 2026-09-17)
    static func probePaywallDialogLevels() {
        let ctl = PaywallWindowController.shared
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            ctl.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                ctl.logWindowLevels(stage: "до діалогу")
                let token = ctl.beginSystemDialog()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    ctl.logWindowLevels(stage: "під час діалогу")
                    ctl.endSystemDialog(token: token)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        ctl.logWindowLevels(stage: "після діалогу")
                    }
                }
            }
        }
    }

    /// Людський опис стану доступу - для нотатки пульта
    static var accessNote: String {
        switch EntitlementStore.shared.access {
        case .trial(let days): return "Стан: trial, лишилось \(days) дн."
        case .pro:             return "Стан: pro"
        case .readOnly:        return "Стан: режим читання"
        case .open:            return "Стан: відкритий (fail-open)"
        }
    }

    /// Знести пісочницю і перезапуститись порожнім
    static func wipeAndRelaunch() {
        guard SandboxEnvironment.isActive else { return }
        // Позиції віджетів, що чекають дебаунсу, інакше збереглись би вже
        // ПІСЛЯ видалення файлу — і база відродилась би напівживою
        DesktopStickyManager.shared.flushPendingSaves()
        do {
            let done = try SandboxEnvironment.wipe()
            NSLog("Пісочниця: очищено — \(done)")
        } catch {
            NSLog("Пісочниця: не вдалося очистити — \(error)")
        }
        LanguageStore.relaunch()
    }

    // MARK: - Знімок вікон (⚠️ тимчасовий, для звірки дизайну)

    /// `-SandboxShot YES` — через 2.5 с малює КОЖНЕ вікно застосунку в
    /// PNG у Documents контейнера. Рендер іде зсередини процесу
    /// (cacheDisplay), тож дозвіл на запис екрана не потрібен — той
    /// самий прийом, що в GlassLab
    static func captureWindowsIfRequested() {
        guard LaunchArgs.flag("SandboxShot") else { return }
        Task { @MainActor in
            // Підказка краю живе лише на такті жесту — для знімка
            // піднімаємо її примусово
            if LaunchArgs.flag("SandboxShotGlow") {
                OnboardingEdgeHintController.shared.show()
            }
            // Привид живе ~2 с — знімаємо його раніше за решту
            let ghost = LaunchArgs.flag("SandboxShotGhost")
            if ghost { OnboardingGhostCursor.shared.play {} }
            try? await Task.sleep(for: .seconds(ghost ? 0.9 : 1.8))
            // -SandboxShotHoverClose / -SandboxShotHoverStale (2026-09-27):
            // синтетичне наведення у ВЛАСНИЙ процес (NSApp.postEvent, без
            // Accessibility) на червону кнопку пінованого вікна (Close) або
            // на стандартне місце кнопки (Stale) - знімок показує, чи
            // гліф ✕ зʼявляється там, де треба, і не зʼявляється там, де
            // кнопка стояла раніше. Лише читає рамки, даних не чіпає
            if LaunchArgs.flag("SandboxShotHoverClose")
                || LaunchArgs.flag("SandboxShotHoverStale") {
                hoverCloseButtonForShot(stale: LaunchArgs.flag("SandboxShotHoverStale"))
                try? await Task.sleep(for: .seconds(0.7))
            }
            let docs = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask)[0]
            for (i, w) in NSApp.windows.enumerated() where w.isVisible {
                // Спершу — знімок ВЛАСНОГО вікна через window server (той
                // самий прийом, що GlassLab.capture: без дозволу Screen
                // Recording): на відміну від cacheDisplay він містить і
                // композитинг (матеріали), і вміст скрол-вʼюх, який
                // cacheDisplay панелі лишає порожнім
                var rep: NSBitmapImageRep?
                if let cg = CGWindowListCreateImage(
                    .null, .optionIncludingWindow, CGWindowID(w.windowNumber),
                    [.boundsIgnoreFraming, .bestResolution]) {
                    rep = NSBitmapImageRep(cgImage: cg)
                }
                if rep == nil, let view = w.contentView,
                   let cached = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: cached)
                    rep = cached
                }
                guard let png = rep?.representation(using: .png, properties: [:])
                else { continue }
                // -SandboxShotTag wall — префікс у імені, щоб серії знімків
                // з різних запусків (вкладки) не перезаписували одна одну
                let tag = ProcessInfo.processInfo.arguments
                    .drop(while: { $0 != "-SandboxShotTag" }).dropFirst().first
                let name = "shot-\(tag.map { "\($0)-" } ?? "")\(i)-\(type(of: w))-\(Int(w.frame.width))x\(Int(w.frame.height)).png"
                try? png.write(to: docs.appendingPathComponent(name))
                NSLog("ЗНІМОК: \(name) frame=\(w.frame) level=\(w.level.rawValue)")
                // -SandboxShotBase64 — продублювати PNG у stdout: Documents
                // контейнера закритий для терміналу без Full Disk Access
                // (TCC), а stdout дочірнього процесу читається завжди.
                // FileHandle, не print: stdout у пайпі буферизований, і
                // хвіст ОСТАННЬОГО рядка губився, коли знімальний запуск
                // вбивали ззовні (знайдено 2026-09-16)
                if LaunchArgs.flag("SandboxShotBase64") {
                    let line = "SHOT-BASE64 \(name) \(png.base64EncodedString())\n"
                    FileHandle.standardOutput.write(Data(line.utf8))
                }
            }
        }
    }

    /// Навести (синтетично) на кнопку закриття: пейвол чи знайомство, якщо
    /// відкриті, інакше панель. stale = навести на стандартне місце
    /// кнопки (16, 16 від кута) - там гліфа бути НЕ має
    @MainActor
    private static func hoverCloseButtonForShot(stale: Bool) {
        // Не будь-яке closable-вікно: пульт пісочниці теж має кнопку
        let visible = NSApp.windows.filter { $0.isVisible }
        guard let win = visible.first(where: { $0 is PaywallPanel || $0 is OnboardingPanel })
                ?? visible.first(where: { $0 is EmbarPanel && $0.styleMask.contains(.closable) }),
              let content = win.contentView,
              let close = WindowChrome.closeButtonFrame(in: win) else { return }
        let point = stale
            ? NSPoint(x: 16, y: content.bounds.height - 16)
            : NSPoint(x: close.midX, y: close.midY)
        let inWindow = content.convert(point, to: nil)
        // Гліф вмикає СПРАВЖНІЙ курсор (mouseMoved у власну чергу подій
        // AppKit ігнорує - доведено контрольним знімком панелі): варпаємо
        // курсор і шлемо системну подію руху. Два кроки - спершу поза
        // кнопкою, потім на неї, щоб спрацював саме вхід у область
        let screen = win.convertPoint(toScreen: inWindow)
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        for p in [NSPoint(x: screen.x + 60, y: screen.y - 60), screen] {
            let cg = CGPoint(x: p.x, y: mainHeight - p.y)
            CGWarpMouseCursorPosition(cg)
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                    mouseCursorPosition: cg, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(120_000)
        }
        NSLog("ЗНІМОК: наведення на \(stale ? "старе місце" : "кнопку") у \(type(of: win)) точка=\(inWindow)")
    }

    // MARK: - Команди як аргументи запуску

    /// Виконати те, що ввімкнено галочками в схемі. Викликати ОДИН раз
    /// при старті, до підняття панелі
    static func runLaunchCommands(in context: @autoclosure () -> ModelContext) {
        guard SandboxEnvironment.isActive else { return }
        if LaunchArgs.flag("SandboxWipe") {
            // Чистимо ДО того, як хтось встиг записати щось нове
            try? SandboxEnvironment.wipe()
            NSLog("Пісочниця: очищено аргументом запуску")
        }
        if LaunchArgs.flag("SandboxResetOnboarding") {
            resetOnboarding(in: context())
        }
        if let count = LaunchArgs.int("SandboxSeedStress"), count > 0 {
            seedStress(count, in: context())
        } else if LaunchArgs.flag("SandboxSeedStress") {
            seedStress(defaultStressCount, in: context())
        }
        // Демо-дані для маркетингових скріншотів (docs/DEMO-SEED-SPEC.md)
        if LaunchArgs.flag("SandboxSeedDemo") {
            DemoSeeder.seedIfNeeded(in: context())
        }
        // Монетизація: команди застосовуються ДО bootstrap-у
        // EntitlementStore в AppDelegate - перший обчислений стан уже
        // враховує скинутий/зсунутий trial
        if LaunchArgs.flag("SandboxResetTrial") {
            resetTrial()
        }
        if let days = LaunchArgs.int("SandboxTrialShiftDays"), days != 0 {
            shiftTrial(byDays: days)
        }
        // -SandboxProOverride 1|0: явне значення оверайду (кнопка в
        // пульті циклює той самий ключ)
        if let raw = LaunchArgs.int("SandboxProOverride") {
            EmbarDefaults.store.set(raw, forKey: EntitlementStore.sandboxOverrideKey)
        }
        // Відкрити пейвол одразу - для знімків та ітерації дизайну;
        // лише показує вікно, даних не чіпає. Наступним тіком: модель
        // читає стан доступу, а bootstrap EntitlementStore іде в
        // AppDelegate одразу ПІСЛЯ runLaunchCommands
        if LaunchArgs.flag("SandboxShowPaywall") {
            DispatchQueue.main.async {
                PaywallWindowController.shared.show()
                // Знімок пейвола сам не каже, readOnly це чи open
                // (тексти однакові) - друкуємо стан явно
                FileHandle.standardOutput.write(Data("ПЕЙВОЛ \(accessNote)\n".utf8))
            }
        }
        // Зонд рівнів вікна пейвола під час системного діалогу покупки
        if LaunchArgs.flag("SandboxPaywallDialogProbe") {
            probePaywallDialogLevels()
        }
    }
}

// MARK: - Вікно-пульт

@MainActor
final class SandboxPanelController {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    static let shared = SandboxPanelController()
    private init() {}

    private var window: NSPanel?

    func showIfSandbox(context: ModelContext) {
        guard SandboxEnvironment.isActive, window == nil else { return }
        // 240pt: четверта кнопка (демо-посів) не влазила у 210;
        // 330pt: три кнопки монетизації (trial/дата/pro) не влазили у 240
        let win = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 360),
                          styleMask: [.titled, .closable, .utilityWindow],
                          backing: .buffered, defer: false)
        win.title = "Пісочниця"
        win.level = .floating
        win.hidesOnDeactivate = false
        win.isReleasedWhenClosed = false
        win.appearance = NSAppearance(named: .aqua)
        // sizingOptions = [] обовʼязково: інакше NSHostingView розтягує
        // ВІКНО під ідеальний розмір контенту — пульт виростав до 715pt
        // порожньої білої плити (знайдено знімком 2026-08-09)
        let hosting = NSHostingView(
            rootView: SandboxPanelView(context: context)
                .defaultAppStorage(EmbarDefaults.store))
        hosting.sizingOptions = []
        win.contentView = hosting
        // Верхній лівий кут — подалі від панелі Embar на правому краю
        if let vf = NSScreen.main?.visibleFrame {
            win.setFrameOrigin(NSPoint(x: vf.minX + 20, y: vf.maxY - 360))
        }
        win.orderFrontRegardless()
        window = win
    }
}

private struct SandboxPanelView: View {
    let context: ModelContext
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Окрема база й налаштування.\nРеальні дані не зачеплені.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Скинути онбординг") {
                SandboxDebug.resetOnboarding(in: context)
                note = "Онбординг скинуто - перезапусти"
            }
            Button("Засіяти стрес-набір (\(SandboxDebug.defaultStressCount)×3)") {
                SandboxDebug.seedStress(SandboxDebug.defaultStressCount, in: context)
                note = "Засіяно по \(SandboxDebug.defaultStressCount): стіки, нотатки, рідер"
            }
            Button("Засіяти демо (маркетинг)") {
                let done = DemoSeeder.seedIfNeeded(in: context)
                note = done ? "Демо-набір засіяно - перезапусти"
                            : "Демо вже засіяно (wipe для повтору)"
            }
            Button("Очистити пісочницю") {
                SandboxDebug.wipeAndRelaunch()
            }

            Divider()

            // Монетизація: trial і оверайд pro (SPEC §15.77)
            Button("Скинути trial") {
                SandboxDebug.resetTrial()
                note = SandboxDebug.accessNote
            }
            Button("Зсунути дату: +15 днів") {
                SandboxDebug.shiftTrial(byDays: 15)
                note = SandboxDebug.accessNote
            }
            Button("Pro: авто → увімк → вимк") {
                SandboxDebug.cycleProOverride()
                note = SandboxDebug.accessNote
            }
            Button("Скинути стан покупки") {
                Task {
                    await EntitlementStore.shared.debugResetPurchaseState()
                    note = SandboxDebug.accessNote
                }
            }

            if !note.isEmpty {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        // Пульт — інструмент розробки, а не поверхня продукту: свідомо
        // системні контроли, без нашої дизайн-системи
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
