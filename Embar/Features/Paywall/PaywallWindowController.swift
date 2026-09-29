//
//  PaywallWindowController.swift
//  Embar
//
//  Вікно Embar Pro: PaywallDesign.width×height по центру, без
//  системної рамки - клон механіки OnboardingWindowController
//  (SPEC §15.77д). Свідомо ОКРЕМЕ центроване вікно, не шит у панелі:
//  там затісно для двох карток планів.
//
//  Вікно НЕ маркується OnboardingAuxWindow: курсор над пейволом має
//  тримати панель відкритою (людина прийшла сюди з панелі й
//  повернеться в неї).
//
//  Модель створюється НА КОЖНЕ відкриття: лічильник думок рахується
//  один раз при відкритті пейвола (рішення 2026-09-16), тож повторне
//  відкриття має рахувати заново.
//

import AppKit
import SwiftUI

/// Книга спроб системного діалогу (рецензія 2026-09-17, правка 3).
///
/// Кожен виклик StoreKit (покупка чи restore) отримує талон. Рівень
/// вікна й панель повертає ЛИШЕ власник найновішого талона: відповідь
/// старої спроби, що зависла, більше не піднімає пейвол над діалогом
/// нової. Книга живе в контролері вікна, а не в моделі: модель
/// створюється на кожне відкриття, і після «хрестик → відкрити знову →
/// купити ще раз» стара модель зі своїм лічильником нічого про нову не
/// знала. Чиста структура - її ганяють юніт-тести.
struct SystemDialogLedger {
    private(set) var generation = 0

    /// Нова спроба: талон, що робить усі попередні недійсними
    mutating func begin() -> Int {
        generation += 1
        return generation
    }

    /// Чи талон досі найновіший
    func owns(_ token: Int) -> Bool { token == generation }

    /// Знецінити всі видані талони (закриття вікна): пізні відповіді
    /// не чіпатимуть ні рівня, ні панелі
    mutating func invalidate() { generation += 1 }
}

/// Утилітарна панель (лише червона кнопка, SPEC §15.78), key-здатна -
/// інакше кнопки не отримували б кліки після активації іншого застосунку
final class PaywallPanel: NSPanel {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    override var canBecomeKey: Bool { true }

    /// Esc = закрити (раніше жив на власному хрестику як .cancelAction).
    /// Без first responder-а, що зʼїв би Esc, keyDown вікна доходить сюди
    override func cancelOperation(_ sender: Any?) { performClose(nil) }

    /// Подвійний клік по смужці - нічого: кнопок згортання/розгортання нема
    override func zoom(_ sender: Any?) {}
    override func performZoom(_ sender: Any?) {}
    override func miniaturize(_ sender: Any?) {}
    override func performMiniaturize(_ sender: Any?) {}
}

@MainActor
final class PaywallWindowController: NSObject, NSWindowDelegate {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    static let shared = PaywallWindowController()
    private override init() { super.init() }

    /// Червона кнопка / ⌘W / Esc - той самий шлях, що йшов хрестик:
    /// знецінити талони, повернути рівень і панель, розтанути. Вікно не
    /// закриваємо системно - close() робить це сам після анімації
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    private var window: PaywallPanel?

    private static let cardSize = NSSize(width: PaywallDesign.width,
                                         height: PaywallDesign.height)

    var isVisible: Bool { window != nil }

    // MARK: - Показ

    func show() {
        // Уже відкрите - просто наперед (лічильник не перераховуємо:
        // це те саме відкриття)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = PaywallPanel(
            contentRect: NSRect(origin: .zero, size: Self.cardSize),
            styleMask: WindowChrome.utilityMask,
            backing: .buffered,
            defer: false
        )
        // Утилітарна смужка ПЕРЕД рівнем/поведінкою (SPEC §15.78)
        WindowChrome.applyUtilityTitlebar(to: win, title: "Embar Pro")
        win.delegate = self
        // ❗ isFloatingPanel ПЕРЕЗАПИСУЄ level - рівень задаємо ПІСЛЯ
        // нього (той самий фікс, що в OnboardingWindowController:
        // інакше вікно опинялось би нижче за панель Embar)
        win.isFloatingPanel = true
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        win.hidesOnDeactivate = false
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        // Драг-ричага всередині нема - за фон тягати можна
        win.isMovableByWindowBackground = true
        // Світле скло (фідбек 2026-09-17): .aqua, матеріал калібрує
        // BehindWindowGlass у вьюсі
        win.appearance = NSAppearance(named: .aqua)

        let hosting = NSHostingView(
            rootView: PaywallView(model: PaywallModel())
                .defaultAppStorage(EmbarDefaults.store))
        hosting.sizingOptions = []             // розмір диктує вікно, не контент
        hosting.safeAreaRegions = []           // смужка не зсуває вміст (§15.78)

        // ❗ Не сам хостинг: із ним Auto Layout titled-вікна додавав до
        // рамки висоту смужки (752 замість 720, кнопка поза карткою -
        // знімок 2026-09-25). Див. WindowChrome.fullHeightContainer
        win.contentView = WindowChrome.fullHeightContainer(for: hosting)
        // ПІСЛЯ contentView: для r = 32 кнопка переїжджає в нього
        WindowChrome.pinCloseButton(in: win, cornerRadius: PaywallDesign.windowRadius)
        centerOnScreen(win)

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // ❗ Тінь рахується з альфа-каналу вікна. На момент показу
        // SwiftUI-вміст ще не скомпоновано, і система бере недомальовану
        // форму - унизу тінь обривалась (фідбек 2026-09-17). Тому
        // перераховуємо ПІСЛЯ компоновки: наступним тіком і ще раз,
        // коли доїде скло behindWindow
        win.invalidateShadow()
        DispatchQueue.main.async { [weak win] in win?.invalidateShadow() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak win] in
            win?.invalidateShadow()
        }
    }

    // MARK: - Режим системного діалогу (блокер 2026-09-17)
    //
    // Вікна StoreKit (пароль Apple ID, Touch ID, підтвердження покупки) -
    // це вікна ЧУЖОГО процесу на звичайному рівні. Наш .statusBar (25)
    // накривав їх: людина бачила очікування і не розуміла, що від неї
    // чекають введення.
    //
    // На час покупки опускаємо пейвол до .normal, щоб система була
    // зверху. Але під пейволом лишається панель Embar (.dock + 1 = 21) -
    // вона накрила б його, тож панель на цей час ховаємо і повертаємо
    // після. Рівень і панель відновлюються ЗАВЖДИ (defer у моделі),
    // навіть якщо покупку скасували чи вона впала, - але лише власником
    // найновішого талона (SystemDialogLedger): стара спроба, що
    // відповіла після «Спробувати ще раз» чи після закриття й
    // повторного відкриття вікна, нічого не піднімає.

    private var levelBeforeDialog: NSWindow.Level?
    private var panelWasVisible = false
    private var ledger = SystemDialogLedger()

    /// Опустити пейвол під системні вікна (якщо ще не опущено) і видати
    /// талон цієї спроби. Повторний виклик, поки попередня спроба ще
    /// чекає, рівня не чіпає - лише знецінює старий талон
    @discardableResult
    func beginSystemDialog() -> Int {
        let token = ledger.begin()
        guard let win = window, levelBeforeDialog == nil else { return token }
        levelBeforeDialog = win.level
        // ❗ Порядок: isFloatingPanel ПЕРЕЗАПИСУЄ level, тож знімаємо
        // його ПЕРШИМ, інакше рівень повернувся б до floating
        win.isFloatingPanel = false
        win.level = .normal
        // Пейвол лишається видимим серед звичайних вікон
        win.orderFront(nil)

        let panel = AppDelegate.current?.panelController
        panelWasVisible = panel?.isPanelVisible ?? false
        if panelWasVisible { panel?.hideForOnboarding() }
        return token
    }

    /// Повернути рівень і панель - лише якщо талон досі найновіший
    func endSystemDialog(token: Int) {
        guard ledger.owns(token) else { return }
        restoreLevelAndPanel()
    }

    /// Чи пейвол зараз опущений під системні вікна (для зонда й тестів)
    var isInSystemDialog: Bool { levelBeforeDialog != nil }

    private func restoreLevelAndPanel() {
        guard let level = levelBeforeDialog else { return }
        levelBeforeDialog = nil
        window?.isFloatingPanel = true      // перезаписує level - до нього
        window?.level = level
        window?.orderFront(nil)
        if panelWasVisible {
            panelWasVisible = false
            AppDelegate.current?.panelController?
                .show(reason: .programmatic)
        }
    }

    #if DEBUG
    /// Зонд рівнів (-SandboxPaywallDialogProbe): руками системний діалог
    /// StoreKit не викличеш, а інваріант «пейвол нижче за систему, але
    /// НЕ під панеллю Embar» треба доводити фактом, а не наміром
    func logWindowLevels(stage: String) {
        let paywall = window?.level.rawValue ?? -999
        let panel = NSApp.windows.first { $0 is EmbarPanel }
        let panelLevel = panel?.level.rawValue ?? -999
        let panelVisible = panel?.isVisible ?? false
        let line = "ЗОНД-РІВНІ [\(stage)] пейвол=\(paywall) "
            + "панель=\(panelLevel) панельВидима=\(panelVisible) "
            + "пейволВидимий=\(window?.isVisible ?? false)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }
    #endif

    /// Трохи вище за геометричний центр - так картка «сидить» на око
    /// (той самий прийом, що в знайомства)
    private func centerOnScreen(_ win: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let x = vf.midX - Self.cardSize.width / 2
        let y = vf.midY - Self.cardSize.height / 2 + vf.height * 0.06
        win.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    // MARK: - Закриття

    func close() {
        guard let win = window else { return }
        window = nil
        // Хрестик посеред покупки: рівень вікна вже не важливий, але
        // панель Embar схована саме нами - повернути її ЗАРАЗ, а не
        // коли (і якщо) StoreKit відповість. Талони знецінюємо: пізня
        // відповідь тієї спроби не торкнеться наступного вікна
        ledger.invalidate()
        restoreLevelAndPanel()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            win.animator().alphaValue = 0
        } completionHandler: {
            win.orderOut(nil)
        }
    }
}
