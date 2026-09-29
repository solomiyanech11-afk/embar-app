//
//  AppDelegate.swift
//  Embar
//
//  Створює панель при старті. Звичайний застосунок з Dock-іконкою (M1);
//  agent-режим без Dock — перемикач у Settings, заплановано на M7.
//

import AppKit
import SwiftUI
import SwiftData
import UserNotifications

extension Notification.Name {
    /// Настала нова доба (або пробудження зі сну) — Home оновлює «сьогодні»
    static let embarDayChanged = Notification.Name("EmbarDayChanged")
    /// Клік по сповіщенню про дедлайн — панель має показати цей стік
    /// (userInfo["id"]: UUID)
    static let embarOpenSticker = Notification.Name("EmbarOpenSticker")
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    /// Живий делегат процесу.
    ///
    /// ❗ `NSApp.delegate as? AppDelegate` ЗАВЖДИ nil: під
    /// `@NSApplicationDelegateAdaptor` делегатом застосунку стоїть проксі
    /// `SwiftUI.AppDelegate`, а наш екземпляр живе за ним (доведено
    /// зондом 2026-09-17 - лог показав `SwiftUI.AppDelegate`). Через той
    /// каст тихо не працювали: deep-link зі сповіщення на холодному
    /// старті, «Показати знайомство знову» і фолбек панелі в онбордингу
    static private(set) weak var current: AppDelegate?

    private(set) var panelController: PanelController?
    private var hotkey: HotkeyManager?

    /// Стік із натиснутого сповіщення, до якого ще не встигли перейти.
    /// Живе тут, бо на холодному старті клік приходить раніше, ніж
    /// зʼявляється ContentView, — і повідомлення нікому було б слухати
    private var pendingOpenStickerID: UUID?

    override init() {
        super.init()
        Self.current = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Юніт-тести хостяться в цьому застосунку — не піднімаємо панель,
        // не чіпаємо реальний стор і не реєструємо хоткей під час тестів
        if NSClassFromString("XCTestCase") != nil { return }

        // (Кольори процесу — виділення/акцент — вже задано в EmbarApp.init,
        // до створення вікон: Theme/SelectionColor.swift)

        // Дебаг-аргумент `-ResetOnboarding YES` — прогнати знайомство наново
        OnboardingStore.applyLaunchArgumentIfNeeded()

        FontRegistrar.registerBundledFonts()

        #if DEBUG
        // ⚠️ Тимчасовий debug-стенд скла (див. Debug/GlassLab.swift):
        // `Embar -GlassLab YES` показує варіанти матеріалів і виходить
        if GlassLab.isRequested {
            GlassLab.run()
            return
        }
        // ⚠️ Тимчасовий стенд насиченості тінта віджетів (2026-07-30)
        if WidgetTintLab.isRequested {
            WidgetTintLab.run()
            return
        }
        // ⚠️ Тимчасовий стенд матриці розкладки тексту віджетів (2026-07-30)
        if WidgetLayoutLab.isRequested {
            WidgetLayoutLab.run()
            return
        }
        // ⚠️ Тимчасовий стенд порожніх станів (2026-08-02, робота над копірайтом)
        if EmptyStatesLab.isRequested {
            EmptyStatesLab.run()
            return
        }
        // Пісочниця (`-EmbarTestSandbox`): команди-аргументи виконуємо ДО
        // першого дотику до бази — очищення має встигнути знести файл,
        // поки контейнер ще не відкрито
        SandboxDebug.runLaunchCommands(
            in: EmbarApp.sharedModelContainer.mainContext)
        #endif

        // Стан доступу (trial/pro): синхронно з локальних джерел, нуль
        // мережі й очікувань; RevenueCat підтягує справжній статус
        // асинхронно (у пісочниці не конфігурується взагалі).
        // ПІСЛЯ runLaunchCommands - команди пісочниці (скинути/зсунути
        // trial) мають застосуватись до першого обчислення стану
        EntitlementStore.shared.bootstrap()
        EntitlementStore.shared.startPurchases()
        // Trial має минати й без перезапуску (рецензія 2026-09-17):
        // доба/сон/активація/година перераховують стан
        EntitlementStore.shared.startClock()
        #if DEBUG
        // `-DebugResetPurchaseState YES` - пройти покупку заново після
        // Clear Purchase History в App Store Connect. Свідомо БЕЗ вимоги
        // пісочниці: покупка тестується у звичайному Debug, де RC
        // сконфігурований; чистить лише кеш статусу, даних не чіпає
        if LaunchArgs.flag("DebugResetPurchaseState") {
            Task { await EntitlementStore.shared.debugResetPurchaseState() }
        }
        #endif

        // Скло/Левітацію вимкнено - хто на них сидів, повертається на
        // Звичайну (ревʼю №3); ДО створення панелі, щоб вона одразу
        // малювалась правильним матеріалом
        ThemeStore.migrateDisabledMaterialsIfNeeded()

        // Показувати сповіщення про дедлайни, навіть коли застосунок активний
        UNUserNotificationCenter.current().delegate = self
        // Кнопки «Готово» і «Відкласти» просто на банері
        ReminderScheduler.registerCategories()
        // Прогріти кеш стану дозволу (F6): рішення «вмикати нагадування
        // чи чесно відмовити» приймається синхронно в момент дії
        ReminderScheduler.refreshStatusCache()

        // Разові міграції даних стіків — ДО обслуговування, щоб воно вже
        // працювало за новими правилами
        StickyMigrations.run(in: EmbarApp.sharedModelContainer.mainContext)

        // Обслуговування бази при старті (SPEC §5, §8.2, §11.9)
        AppMaintenance.run(in: EmbarApp.sharedModelContainer.mainContext)

        // Перехід доби (опівніч локального часу / зміна таймзони)
        NotificationCenter.default.addObserver(
            self, selector: #selector(dayChanged),
            name: .NSCalendarDayChanged, object: nil)
        // Пробудження зі сну (могло пройти через північ)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(dayChanged),
            name: NSWorkspace.didWakeNotification, object: nil)

        let root = ContentView()
            .modelContainer(EmbarApp.sharedModelContainer)
            // @AppStorage без цього пішов би в UserDefaults.standard в обхід
            // пісочниці (див. SandboxEnvironment)
            .defaultAppStorage(EmbarDefaults.store)
        panelController = PanelController(rootView: root)
        // Наявний користувач (є хоч якісь дані) знайомства не бачить -
        // прапорець зʼявився пізніше за перших користувачів (ревʼю №2)
        OnboardingStore.migrateExistingUserIfNeeded(
            hasAnyUserData: OnboardingSeeder.hasAnyUserData(
                in: EmbarApp.sharedModelContainer.mainContext))
        if OnboardingStore.shouldRun {
            // Такт 3: стіки-тутоаріал сідають на стіну ще до першого
            // показу панелі — щоб людина побачила їх одразу, як панель
            // приїде. Посів одноразовий (власний прапорець)
            OnboardingSeeder.seedIfNeeded(
                in: EmbarApp.sharedModelContainer.mainContext)
            // Перший запуск: панель НЕ показуємо. Такт 2 знайомства вчить
            // викликати її жестом — а якщо вона вже стоїть відкрита,
            // вчити нічого. Покажемо, коли знайомство завершиться
            OnboardingWindowController.shared.start(panelController: panelController) { [weak self] in
                self?.panelController?.show(reason: .programmatic)
            }
        } else {
            // Показати одразу при запуску, щоб застосунок не виглядав «порожнім»
            panelController?.show(reason: .launch)
        }

        // Стіки-віджети на столі (SPEC §2.7) — відновити ПІСЛЯ maintenance:
        // стік, що вигрузився при старті, вікна не отримає
        DesktopStickyManager.shared.restoreAtLaunch(
            context: EmbarApp.sharedModelContainer.mainContext)

        #if DEBUG
        // ⚠️ Тимчасовий debug: `-GlassShot YES` — знімок реальної панелі
        // у Documents і вихід (див. Debug/GlassLab.swift)
        if GlassLab.isShotRequested { GlassLab.shootRealPanel() }

        // Пульт пісочниці — існує тільки в тестовому середовищі
        SandboxPanelController.shared.showIfSandbox(
            context: EmbarApp.sharedModelContainer.mainContext)

        // ⚠️ Тимчасовий знімок вікон для звірки дизайну (`-SandboxShot YES`)
        SandboxDebug.captureWindowsIfRequested()

        // Вимірювальний зонд пісочниці (`-SandboxPerfProbe`)
        PerfProbe.runIfRequested()

        // ⚠️ Тимчасовий зонд P2.33 (`-SandboxEmojiProbe YES`)
        EmojiPaletteProbe.runIfRequested()
        #endif

        // Глобальний хоткей Option+E — показ/приховання панелі (SPEC §15 п.14)
        hotkey = HotkeyManager { [weak self] in
            self?.panelController?.toggle()
        }
    }

    /// Клік по іконці в Dock → показати панель
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show(reason: .dockClick)
        return true
    }

    /// Вихід: позиції віджетів, чий 0.4с-дебаунс не встиг, дотискаються
    /// в модель і на диск (code review 2026-07-30)
    func applicationWillTerminate(_ notification: Notification) {
        DesktopStickyManager.shared.flushPendingSaves()
        try? EmbarApp.sharedModelContainer.mainContext.save()
    }

    /// ❗ NSCalendarDayChanged приходить на ДОВІЛЬНОМУ потоці (didWake — на
    /// main). mainContext привʼязаний до MainActor, а в Swift 5-режимі
    /// @objc-селектор не отримує runtime-хопу — стрибаємо на main явно,
    /// інакше о півночі fetch/save з фонового потоку = data race у SwiftData
    @objc private func dayChanged() {
        DispatchQueue.main.async {
            AppMaintenance.run(in: EmbarApp.sharedModelContainer.mainContext)
            NotificationCenter.default.post(name: .embarDayChanged, object: nil)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Натиснули сповіщення: кнопку «Готово» / «Відкласти» або сам банер
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        guard let raw = content.userInfo["stickerID"] as? String,
              let id = UUID(uuidString: raw) else { return }

        switch response.actionIdentifier {
        case ReminderScheduler.Action.close:
            // Просто прибрати банер. Свій case обовʼязковий: default
            // відкриває стік, і «Закрити» без нього робило б навпаки
            break
        case ReminderScheduler.Action.done:
            markStickerDone(id)
        case ReminderScheduler.Action.snooze:
            await snoozeSticker(content: content, id: id)
        default:
            // Клік по самому банеру (або «показати») — відкрити стік
            openSticker(id)
        }
    }

    /// Стік із бази за id — спільний початок для всіх дій банера
    private func fetchSticker(_ id: UUID) -> Sticker? {
        var descriptor = FetchDescriptor<Sticker>(
            predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? EmbarApp.sharedModelContainer.mainContext.fetch(descriptor).first
    }

    private func markStickerDone(_ id: UUID) {
        guard let sticker = fetchSticker(id),
              sticker.deletedAt == nil, !sticker.done else { return }
        StickerService.toggleDone(sticker)
        ReminderScheduler.cancel(id: id)
        try? EmbarApp.sharedModelContainer.mainContext.save()
    }

    /// «Відкласти» — тільки якщо стіку ще належать сповіщення. Банер міг
    /// провисіти довго: за цей час стік устигали виконати чи видалити, і
    /// відкладене нагадування прилітало вже ні про що (ревʼю 2026-08-19)
    private func snoozeSticker(content: UNNotificationContent, id: UUID) async {
        guard let sticker = fetchSticker(id),
              ReminderScheduler.canRemind(sticker) else {
            ReminderScheduler.cancel(id: id)
            return
        }
        await ReminderScheduler.snooze(content: content, id: id)
    }

    private func openSticker(_ id: UUID) {
        pendingOpenStickerID = id
        // Панель показується без активації (щоб hover не крав фокус) — але
        // клік по банеру якраз просить вийти вперед, інакше вона приїде
        // за чужим вікном
        NSApp.activate()
        panelController?.show(reason: .programmatic)
        NotificationCenter.default.post(name: .embarOpenSticker, object: nil,
                                        userInfo: ["id": id])
    }

    /// Забрати відкладений перехід (і одразу його погасити) — ContentView
    /// питає при появі, щоб не загубити клік, що прийшов до неї
    func takePendingOpenSticker() -> UUID? {
        defer { pendingOpenStickerID = nil }
        return pendingOpenStickerID
    }
}
