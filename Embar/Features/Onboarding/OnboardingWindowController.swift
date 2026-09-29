//
//  OnboardingWindowController.swift
//  Embar
//
//  Вікно знайомства: 660×440 по центру, без системної рамки.
//
//  Скляну шторку малює SwiftUI усередині (розмита копія тла під маскою).
//  Нативний NSVisualEffectView тут пробували окремим шаром НАД тлом:
//  на повній силі він змішував мʼяту з розмитим кораловим знаком у
//  брудний відтінок, а напівпрозорий переставав читатись як скло
//  взагалі. Рішення 2026-08-09: лишаємо власний блур — він виглядав
//  найкраще з усього, що пробували.
//
//  Рівні й фокус розведені навмисно (щоб не було війни вікон):
//  · вікно знайомства — .statusBar (25), ловить мишу, може бути key;
//  · підказка на краю — нижче за панель і click-through;
//  · панель Embar — dock+1 (21), key лише по кліку.
//

import AppKit
import SwiftUI

/// Маркер вікон онбордингу — щоб панель не рахувала їх «своїми» в
/// логіці auto-hide (див. PanelController.mouseInsideAppWindow)
protocol OnboardingAuxWindow: AnyObject {}

/// Картка знайомства. Утилітарна панель (лише червона кнопка, SPEC
/// §15.78), key-здатна — інакше в полі «Як до тебе звертатися?» не
/// можна було б друкувати
final class OnboardingPanel: NSPanel, OnboardingAuxWindow {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    override var canBecomeKey: Bool { true }

    /// Подвійний клік по смужці - нічого: кнопок згортання/розгортання нема
    override func zoom(_ sender: Any?) {}
    override func performZoom(_ sender: Any?) {}
    override func miniaturize(_ sender: Any?) {}
    override func performMiniaturize(_ sender: Any?) {}
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    static let shared = OnboardingWindowController()
    private override init() { super.init() }

    /// Червона кнопка / ⌘W = пропустити знайомство - те саме, що робив
    /// хрестик. Вікно не закриваємо системно: finish() тане сам
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish()
        return false
    }

    private var window: OnboardingPanel?
    /// Що зробити, коли знайомство завершено або пропущено
    private var onFinish: (() -> Void)?
    /// Панель — такт жесту ховає її, щоб навчити викликати жестом
    private(set) weak var panelController: PanelController?

    private static let cardSize = NSSize(width: OnboardingDesign.width,
                                         height: OnboardingDesign.height)

    var isRunning: Bool { window != nil }

    // MARK: - Запуск

    func start(panelController: PanelController?, onFinish: @escaping () -> Void) {
        guard window == nil else { return }
        self.panelController = panelController
        self.onFinish = onFinish

        let win = OnboardingPanel(
            contentRect: NSRect(origin: .zero, size: Self.cardSize),
            styleMask: WindowChrome.utilityMask,
            backing: .buffered,
            defer: false
        )
        // Утилітарна смужка ПЕРЕД рівнем/поведінкою (SPEC §15.78)
        WindowChrome.applyUtilityTitlebar(to: win, title: "Embar")
        win.delegate = self
        // ❗ isFloatingPanel ПЕРЕЗАПИСУЄ level (ставить .floating = 3), тож
        // рівень задаємо ПІСЛЯ нього — інакше картка опинялась нижче за
        // панель Embar (dock+1 = 21) і та накрила б її на такті жесту
        // (знайдено 2026-08-09 знімком вікон)
        win.isFloatingPanel = true
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        win.hidesOnDeactivate = false          // клік у браузер не має ховати знайомство
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        // Вікно НЕ тягається: усередині живе драг-ричаг, і перетягування
        // за фон забирало б у нього жест (фідбек 2026-08-09)
        win.isMovableByWindowBackground = false
        win.isMovable = false
        win.appearance = NSAppearance(named: .aqua)

        let hosting = NSHostingView(
            rootView: OnboardingView().defaultAppStorage(EmbarDefaults.store))
        hosting.sizingOptions = []             // розмір диктує вікно, не контент
        hosting.safeAreaRegions = []           // смужка не зсуває вміст (§15.78)

        // Контейнер, не сам хостинг: інакше рамка росте на висоту смужки
        // (той самий фікс, що в пейволі; WindowChrome.fullHeightContainer)
        win.contentView = WindowChrome.fullHeightContainer(for: hosting)
        // ПІСЛЯ contentView: для r = 32 кнопка переїжджає в нього
        WindowChrome.pinCloseButton(in: win, cornerRadius: OnboardingDesign.windowRadius)
        centerOnScreen(win)

        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.invalidateShadow()
    }

    /// Трохи вище за геометричний центр — так картка «сидить» на око
    private func centerOnScreen(_ win: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let x = vf.midX - Self.cardSize.width / 2
        let y = vf.midY - Self.cardSize.height / 2 + vf.height * 0.06
        win.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    // MARK: - Завершення

    /// Пройдено до кінця або пропущено хрестиком — для прапорця це одне
    /// й те саме
    func finish() {
        OnboardingStore.complete()
        OnboardingEdgeHintController.shared.hide()

        let done = onFinish
        onFinish = nil
        // Панель виїжджає ще поки картка тане — знайомство передає їй
        // естафету, а не зникає з клацанням (фідбек 2026-08-09)
        done?()

        guard let win = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            win.animator().alphaValue = 0
        } completionHandler: {
            win.orderOut(nil)
        }
    }
}
