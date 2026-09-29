//
//  WindowChromeTests.swift
//  EmbarTests
//
//  Утилітарна смужка заголовка (App Review Guideline 4, 2026-09-25,
//  SPEC §15.78): панель, пейвол, знайомство і віджети мають лише
//  червону кнопку закриття. Тести тримають три речі:
//  · поведінка панелі (рівень, Spaces, nonactivating…) переживає зміну
//    styleMask - фабрика PanelController.makePanelWindow;
//  · геометрія кнопки узгоджена з константами верстки шапки;
//  · червона кнопка і ⌘W ідуть у windowShouldClose (звідки панель
//    ховається, а не закривається), і клік у прозорій смужці доходить
//    до нашого вмісту;
//  · нових borderless-вікон без свідомого рішення не зʼявляється
//    (source-scan).
//

import XCTest
import AppKit
import SwiftUI
@testable import Embar

@MainActor
final class WindowChromeTests: XCTestCase {

    /// Делегат-свідок: рахує, скільки разів вікно просило дозволу закритись
    private final class CloseWitness: NSObject, NSWindowDelegate {
        nonisolated deinit {}
        var asks = 0
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            asks += 1
            return false
        }
    }

    private func makeProbeWindow() -> EmbarPanel {
        let win = EmbarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 600),
            styleMask: WindowChrome.utilityMask.union([.nonactivatingPanel]),
            backing: .buffered, defer: false)
        WindowChrome.applyUtilityTitlebar(to: win, title: "Probe")
        win.backgroundColor = .clear
        win.isOpaque = false
        return win
    }

    // MARK: - Панель: поведінка після зміни маски

    func testPanelWindowKeepsBehaviorWithTitlebar() {
        let panel = PanelController.makePanelWindow()
        defer { panel.orderOut(nil) }

        // Маска: утилітарний патерн, без згортання/ресайзу, nonactivating
        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.styleMask.contains(.closable))
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        // Три кнопки (§15.78є): жовта потребує .miniaturizable, зелена -
        // .resizable (без нього AppKit тримає її вимкненою)
        XCTAssertTrue(panel.styleMask.contains(.miniaturizable))
        XCTAssertTrue(panel.styleMask.contains(.resizable))

        // Смужка невидима, назва лишилась для VoiceOver
        XCTAssertEqual(panel.title, "Embar")
        XCTAssertEqual(panel.titleVisibility, .hidden)
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        XCTAssertEqual(panel.titlebarSeparatorStyle, .none)
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            XCTAssertEqual(panel.standardWindowButton(kind)?.isHidden, false, "\(kind)")
            XCTAssertEqual(panel.standardWindowButton(kind)?.isEnabled, true, "\(kind)")
        }

        // Присутність над усім і фокус - усе, що могла скинути маска
        XCTAssertEqual(panel.level, PanelController.panelLevel)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
        // Зелена = Zoom, не Full Screen: primary-поведінки немає
        XCTAssertFalse(panel.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertFalse(panel.isOpaque)

        // Докована: за смужку не відтягнути
        XCTAssertFalse(panel.isMovable)
        XCTAssertFalse(panel.isMovableByWindowBackground)
    }

    // MARK: - Єдине правило кута (ревізія 2026-09-27)

    /// Кнопка концентрична з дугою кута: центр на (r, r). Просвіт до
    /// верхнього краю, лівого краю і до кривої однаковий; для панелі
    /// (r = 16) це стандартне місце macOS
    func testCloseButtonInsetRule() {
        XCTAssertEqual(WindowChrome.closeButtonInset(cornerRadius: 32), 32)
        XCTAssertEqual(WindowChrome.closeButtonInset(cornerRadius: 16), 16)
        let half = WindowChrome.closeButtonDiameter / 2
        for r: CGFloat in [16, 32] {
            let inset = WindowChrome.closeButtonInset(cornerRadius: r)
            let gapToEdge = inset - half
            // Відстань від центру кнопки до дуги вздовж діагоналі:
            // центр дуги на (r, r), радіус r
            let centerToArcCenter = abs(inset - r) * sqrt(2)
            let gapToArc = r - centerToArcCenter - half
            XCTAssertEqual(gapToEdge, gapToArc, accuracy: 0.5,
                           "r=\(r): просвіт до краю і до кривої мають збігатись")
            XCTAssertGreaterThan(gapToArc, 0, "r=\(r): кнопка виступає за дугу")
        }
    }

    /// Пін ставить кнопку в ціль і повертає її після перетилінгу смужки
    func testPinnedCloseButtonHoldsPosition() throws {
        for r: CGFloat in [16, 32] {
            let win = makeProbeWindow()
            win.contentView = NSView(frame: .zero)
            WindowChrome.pinCloseButton(in: win, cornerRadius: r)
            win.orderFrontRegardless()
            defer { win.orderOut(nil) }
            win.layoutIfNeeded()

            let inset = WindowChrome.closeButtonInset(cornerRadius: r)
            let content = try XCTUnwrap(win.contentView)
            var close = try XCTUnwrap(WindowChrome.closeButtonFrame(in: win))
            XCTAssertEqual(close.midX, inset, accuracy: 0.5, "r=\(r)")
            XCTAssertEqual(content.bounds.height - close.midY, inset, accuracy: 0.5, "r=\(r)")

            // AppKit «перекладає» кнопку (імітуємо перетилінг) - пін повертає
            let button = try XCTUnwrap(win.standardWindowButton(.closeButton))
            button.setFrameOrigin(NSPoint(x: 40, y: 3))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            close = try XCTUnwrap(WindowChrome.closeButtonFrame(in: win))
            XCTAssertEqual(close.midX, inset, accuracy: 0.5, "r=\(r): пін не повернув кнопку")

            // Ресайз вікна: кнопка лишається у верхньому лівому куті
            var frame = win.frame
            frame.size.height += 100
            win.setFrame(frame, display: true)
            win.layoutIfNeeded()
            close = try XCTUnwrap(WindowChrome.closeButtonFrame(in: win))
            XCTAssertEqual(content.bounds.height - close.midY, inset, accuracy: 0.5, "r=\(r): після ресайзу")

            // Кнопка КЛІКАЄТЬСЯ по центру (r = 32 виходила за смужку і
            // хіт-тест повертав вміст - 2026-09-27) і після перетилінгу
            // на рамці вікна лишається рівно одна область наведення там,
            // де кнопка, а не там, де вона стояла в смужці
            let themeFrame = try XCTUnwrap(content.superview)
            let center = content.convert(NSPoint(x: close.midX, y: close.midY), to: themeFrame)
            XCTAssertTrue(themeFrame.hitTest(center) === button, "r=\(r): центр кнопки не клікається")
            let areas = themeFrame.trackingAreas.filter { $0.owner === themeFrame }
            let closeInFrame = content.convert(close, to: themeFrame)
            XCTAssertTrue(areas.allSatisfy { $0.rect.intersects(closeInFrame) },
                          "r=\(r): застаріла область наведення поза кнопкою: \(areas.map(\.rect))")
            XCTAssertFalse(areas.isEmpty, "r=\(r): область наведення для гліфа зникла")
        }
    }

    /// Панель із фабрики: кнопка за правилом для її радіуса 16
    func testPanelCloseButtonPinned() throws {
        let panel = PanelController.makePanelWindow()
        panel.contentView = NSView(frame: .zero)
        panel.setFrame(NSRect(x: 0, y: 0, width: 360, height: 600), display: false)
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        panel.layoutIfNeeded()
        let close = try XCTUnwrap(WindowChrome.closeButtonFrame(in: panel))
        let inset = WindowChrome.closeButtonInset(
            cornerRadius: PanelController.panelCornerRadius)
        XCTAssertEqual(close.midX, inset, accuracy: 0.5)
        XCTAssertEqual(600 - close.midY, inset, accuracy: 0.5)
        // Вміст на повну висоту вікна (fullSizeContentView)
        XCTAssertEqual(panel.contentView?.frame.height, panel.frame.height)
    }

    /// Смужка прозора і НЕ перехоплює кліки: у верхніх 28pt поза кнопкою
    /// хіт-тест доходить до нашої вьюхи (шапка панелі лишається клікабельною)
    func testTitlebarStripPassesClicksToContent() throws {
        let win = makeProbeWindow()
        let content = NSView(frame: .zero)
        win.contentView = content
        let button = NSButton(frame: NSRect(x: 60, y: 600 - 24, width: 40, height: 20))
        content.addSubview(button)
        win.orderFrontRegardless()
        defer { win.orderOut(nil) }

        let themeFrame = try XCTUnwrap(content.superview)
        let inStrip = NSPoint(x: 70, y: 600 - 14)
        XCTAssertTrue(themeFrame.hitTest(inStrip) === button,
                      "клік у смужці мав дійти до нашої кнопки")
        let close = try XCTUnwrap(WindowChrome.closeButtonFrame(in: win))
        let onClose = NSPoint(x: close.midX, y: close.midY)
        XCTAssertFalse(themeFrame.hitTest(onClose) === button)
    }

    /// Старт слайду - за правим краєм екрана: titled-панель не «повертається»
    /// на екран сама (constrainFrameRect лишився нашим)
    func testOffscreenFrameSurvivesOrderFront() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let off = NSRect(x: screen.frame.maxX + 20, y: 100, width: 360, height: 600)
        let win = makeProbeWindow()
        win.setFrame(off, display: false)
        win.orderFrontRegardless()
        defer { win.orderOut(nil) }
        XCTAssertEqual(win.frame, off)
    }

    /// Центроване вікно (пейвол/знайомство) з SwiftUI-хостингом фіксованого
    /// розміру: після layout рамка НЕ виростає на висоту смужки (752
    /// замість 720 - знімок 2026-09-25). Тримає fullHeightContainer
    func testHostingContainerKeepsFrameAfterLayout() {
        let size = NSSize(width: 640, height: 720)
        let win = PaywallPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: WindowChrome.utilityMask,
                               backing: .buffered, defer: false)
        WindowChrome.applyUtilityTitlebar(to: win, title: "Probe")
        let hosting = NSHostingView(rootView: Color.red.frame(width: 640, height: 720))
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        win.contentView = WindowChrome.fullHeightContainer(for: hosting)
        win.orderFrontRegardless()
        defer { win.orderOut(nil) }
        win.layoutIfNeeded()
        XCTAssertEqual(win.frame.size, size)
        XCTAssertEqual(hosting.frame.size, size)
    }

    // MARK: - Три кнопки панелі на справжньому PanelController (§15.78є)

    /// Чиста геометрія zoom-у: 320 ↔ 480, правий край і висота на місці
    func testZoomedFrameToggles() {
        let at360 = NSRect(x: 1000, y: 6, width: 360, height: 800)
        let wide = PanelController.zoomedFrame(current: at360)
        XCTAssertEqual(wide, NSRect(x: 880, y: 6, width: 480, height: 800))
        let narrow = PanelController.zoomedFrame(current: wide)
        XCTAssertEqual(narrow, NSRect(x: 1040, y: 6, width: 320, height: 800))
        XCTAssertEqual(PanelController.zoomedFrame(current: narrow).width, 480)
    }

    /// Зелена кнопка перемикає ширину через AppKit-zoom і зберігає її як
    /// ручний ресайз; нативне тягання країв відхиляється
    func testPanelZoomAndNativeResize() throws {
        let controller = PanelController(rootView: Color.clear)
        let panel = controller.window
        defer { panel.orderOut(nil) }
        controller.show(reason: .programmatic)
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        let before = panel.frame

        // Нативний ресайз: лівий край - як ручка (ширина в межах, висота
        // та сама), правий край / верх / низ - відхиляється
        let left = PanelController.nativeResizeSize(
            proposed: NSSize(width: 500, height: 500), current: before,
            mouseX: before.minX + 2)
        XCTAssertEqual(left, NSSize(width: PanelController.resizeMax, height: before.height))
        let right = PanelController.nativeResizeSize(
            proposed: NSSize(width: 400, height: 500), current: before,
            mouseX: before.maxX - 2)
        XCTAssertEqual(right, before.size)

        try XCTUnwrap(panel.standardWindowButton(.zoomButton)).performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let expected = PanelController.zoomedFrame(current: before)
        XCTAssertEqual(panel.frame.width, expected.width, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxX, before.maxX, accuracy: 0.5, "правий край має лишитись")
        XCTAssertEqual(panel.frame.height, before.height, accuracy: 0.5)
        XCTAssertEqual(EmbarDefaults.store.double(forKey: PanelController.widthKey),
                       Double(expected.width), accuracy: 0.5, "ширина зберігається як після ручки")

        try XCTUnwrap(panel.standardWindowButton(.zoomButton)).performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(panel.frame.width,
                       PanelController.zoomedFrame(current: expected).width, accuracy: 0.5)
        XCTAssertFalse(panel.styleMask.contains(.fullScreen), "zoom не мав піти у fullscreen")
    }

    /// Жовта кнопка і ⌘M ховають панель, а не згортають у Dock
    func testPanelYellowAndCommandMHideInsteadOfMiniaturize() throws {
        let controller = PanelController(rootView: Color.clear)
        let panel = controller.window
        defer { panel.orderOut(nil) }
        controller.show(reason: .programmatic)
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        XCTAssertTrue(controller.isOnScreen)

        try XCTUnwrap(panel.standardWindowButton(.miniaturizeButton)).performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(panel.isMiniaturized, "у Dock згортатись не має")
        XCTAssertFalse(controller.isOnScreen, "жовта = сховати панель")

        controller.show(reason: .programmatic)
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            characters: "m", charactersIgnoringModifiers: "m",
            isARepeat: false, keyCode: 46)!
        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(panel.isMiniaturized)
        XCTAssertFalse(controller.isOnScreen, "⌘M = сховати панель")
    }

    // MARK: - Закриття = запит делегату

    func testCloseButtonAsksDelegateAndKeepsWindow() throws {
        let win = makeProbeWindow()
        let witness = CloseWitness()
        win.delegate = witness
        win.orderFrontRegardless()
        defer { win.orderOut(nil) }

        let close = try XCTUnwrap(win.standardWindowButton(.closeButton))
        close.performClick(nil)
        XCTAssertEqual(witness.asks, 1)
        XCTAssertTrue(win.isVisible, "делегат відмовив - вікно лишається")
    }

    func testCommandWAsksDelegate() {
        let win = makeProbeWindow()
        let witness = CloseWitness()
        win.delegate = witness
        win.orderFrontRegardless()
        defer { win.orderOut(nil) }

        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: win.windowNumber, context: nil,
            characters: "w", charactersIgnoringModifiers: "w",
            isARepeat: false, keyCode: 13)!
        XCTAssertTrue(win.performKeyEquivalent(with: event))
        XCTAssertEqual(witness.asks, 1)
        XCTAssertTrue(win.isVisible)
    }

    // MARK: - Source-scan: нові вікна без рамки - лише свідомо

    /// Кожне `.borderless` у коді застосунку (поза Debug/) - у цьому
    /// списку. Невидимі помічники: тригер на краю, тінь-«туман»,
    /// острівець налаштувань віджета, підказка на краю в онбордингу; і
    /// самі стіки-віджети на столі - свідоме рішення 2026-09-27 (SPEC
    /// §15.78ґ: повернуто власний ✕, як у білді 3). Нове borderless-вікно
    /// поза списком - ризик повторної відмови App Review (Guideline 4)
    func testBorderlessWindowsAreOnlyTheKnownHelpers() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Embar")
        let expected: [String: Int] = [
            "PanelController.swift": 2,        // edge trigger + shadow window
            "DesktopStickyController.swift": 2, // widget window + settings popup
            "OnboardingEdgeHint.swift": 1,      // click-through edge hint
        ]
        var found: [String: Int] = [:]
        let files = try XCTUnwrap(FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift"
                && !$0.path.contains("/Debug/") })
        // Саме стиль вікна, не `.borderlessButton` меню
        let pattern = try NSRegularExpression(pattern: #"\.borderless(?![A-Za-z])"#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let count = pattern.numberOfMatches(
                in: text, range: NSRange(text.startIndex..., in: text))
            if count > 0 { found[file.lastPathComponent] = count }
        }
        XCTAssertEqual(found, expected, """
            Borderless-вікна змінились. Видиме вікно без рамки - привід \
            для відмови App Review: дай йому утилітарну смужку \
            (WindowChrome.applyUtilityTitlebar) або, якщо це допоміжне \
            невидиме вікно, внеси його в список тут свідомо.
            """)
    }
}
