//
//  OnboardingEdgeHint.swift
//  Embar
//
//  Дві підказки такту «Панель поруч»:
//
//  · СВІТІННЯ на правому краю — постійне, поки чекаємо жесту. Два
//    кольори бренду (коралевий і салатовий) повільно перепливають один
//    в одного назустріч, тож смуга «дихає» кольором, а не яскравістю
//    (фідбек 2026-08-09: «зроби насиченішим і хай переливаються»).
//  · ПРИВИД-КУРСОР — одноразовий показ жесту по кнопці «Покажи мені»:
//    напівпрозорий курсор пливе від центру екрана до правого краю, і
//    аж тоді панель виїжджає сама.
//
//  Обидва вікна ЗАВЖДИ click-through (ignoresMouseEvents): інакше вони
//  накрили б 4-піксельну смужку-тригер панелі, і жест, якого ми вчимо,
//  перестав би працювати. Рівень — нижче за панель, щоб вона, виїжджаючи,
//  природно накривала підказку.
//

import AppKit
import SwiftUI

/// Вікна підказок — маркер OnboardingAuxWindow, щоб панель не рахувала
/// їх «своїми» в логіці auto-hide
private final class OnboardingHintPanel: NSPanel, OnboardingAuxWindow {
    // ❗ Явний deinit обовʼязковий: останнє посилання на це вікно
    // відпускає `OnboardingGhostCursor.hide()`, який кличе `.task`
    // вьюхи, що живе ВСЕРЕДИНІ цього ж вікна, — тобто звільнення
    // відбувається в Swift Task. Рівно профіль міни ізольованого
    // deinit (див. CLAUDE.md)
    nonisolated deinit {}
}

/// Спільна фабрика click-through вікна для обох підказок
@MainActor
private func makeHintWindow(frame: NSRect, level: NSWindow.Level,
                            root: some View) -> OnboardingHintPanel {
    let win = OnboardingHintPanel(
        contentRect: frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: false)
    win.level = level
    win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    win.hidesOnDeactivate = false
    win.backgroundColor = .clear
    win.isOpaque = false
    win.hasShadow = false
    win.ignoresMouseEvents = true       // ❗ кліки й hover ідуть КРІЗЬ
    win.appearance = NSAppearance(named: .aqua)
    let hosting = NSHostingView(rootView: AnyView(root))
    hosting.sizingOptions = []
    win.contentView = hosting
    win.setFrame(frame, display: true)
    return win
}

// MARK: - Світіння на краю

@MainActor
final class OnboardingEdgeHintController {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    static let shared = OnboardingEdgeHintController()
    private init() {}

    private var window: OnboardingHintPanel?

    /// Ширина смуги світіння (вікно вужче за екран — менше зайвого
    /// поверх чужих застосунків)
    private static let glowWidth: CGFloat = 130

    func show() {
        hide()
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let frame = NSRect(x: vf.maxX - Self.glowWidth, y: vf.minY,
                           width: Self.glowWidth, height: vf.height)
        // Світіння — на одиницю нижче за панель (dockWindow+1), щоб
        // панель, виїжджаючи, природно його накривала
        let win = makeHintWindow(
            frame: frame,
            level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow))),
            root: EdgeGlowHint())
        // Сяйво не має «клацати» — заходить і йде плавно (фідбек 2026-08-09)
        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.9
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            win.animator().alphaValue = 1
        }
        window = win
    }

    func hide() {
        guard let win = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            win.animator().alphaValue = 0
        } completionHandler: {
            win.orderOut(nil)
        }
    }
}

private struct EdgeGlowHint: View {
    //  Техніка — з ефекту Apple Intelligence
    //  (github.com/jacobamobin/AppleIntelligenceGlowEffect): кілька шарів
    //  однієї смуги, від тонкої й чіткої до широкої й розмитої, залиті
    //  градієнтом, чиї стопи ЩОПІВСЕКУНДИ перетасовуються і переїжджають
    //  анімацією. Саме випадковий переїзд стопів дає відчуття, що кольори
    //  живуть і переплітаються, а не просто пульсують.
    //
    //  У нас замість шести кольорів Apple — два наші: коралевий і
    //  мʼятний, по три стопи кожного.

    @State private var stops: [Gradient.Stop] = EdgeGlowHint.shuffledStops()
    @State private var swim: Task<Void, Never>?

    /// Шари: ширина смуги + розмиття + прозорість. Найтонший — зверху,
    /// він і читається як «нитка» на самому краю
    private static let layers: [(width: CGFloat, blur: CGFloat, opacity: Double)] = [
        (34, 26, 0.55),
        (18, 14, 0.70),
        (9, 6, 0.85),
        (3, 0, 1.00),
    ]

    static func shuffledStops() -> [Gradient.Stop] {
        let colors = [OnboardingDesign.coral, OnboardingDesign.glowMint,
                      OnboardingDesign.coral, OnboardingDesign.glowMint,
                      OnboardingDesign.coral, OnboardingDesign.glowMint]
        return colors
            .map { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }
            .sorted { $0.location < $1.location }
    }

    /// Вертикальне згасання: повна сила в середині, нуль угорі й унизу —
    /// щоб смуга не читалась як накладена на екран панель
    private var verticalFalloff: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.45), location: 0.12),
                .init(color: .white, location: 0.34),
                .init(color: .white, location: 0.66),
                .init(color: .white.opacity(0.45), location: 0.88),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            ForEach(Array(Self.layers.enumerated()), id: \.offset) { _, layer in
                LinearGradient(gradient: Gradient(stops: stops),
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: layer.width)
                    .blur(radius: layer.blur)
                    .opacity(layer.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .drawingGroup()          // усі шари — один прохід рендера
        .mask(verticalFalloff)
        .ignoresSafeArea()
        .onAppear(perform: startSwimming)
        .onDisappear { swim?.cancel() }
    }

    private func startSwimming() {
        swim?.cancel()
        swim = Task { @MainActor in
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 1.0)) {
                    stops = Self.shuffledStops()
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

// MARK: - Привид-курсор (показ жесту по кнопці)

@MainActor
final class OnboardingGhostCursor {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    static let shared = OnboardingGhostCursor()
    private init() {}

    private var window: OnboardingHintPanel?

    /// Програти жест один раз. `completion` — коли привид дійшов до краю
    /// (саме тоді має виїхати панель); вікно гасне вже після
    func play(completion: @escaping () -> Void) {
        hide()
        guard let screen = NSScreen.main else { return completion() }
        let vf = screen.visibleFrame
        // ❗ Привид мусить бути НАД карткою знайомства (.statusBar = 25),
        // інакше більшу частину шляху він летить ПІД нею: картка стоїть
        // по центру екрана, а привид саме звідти й стартує — тому його
        // й «не було видно» (баг 2026-08-11)
        let win = makeHintWindow(
            frame: vf,
            level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1),
            root: GhostCursorRun(onArrive: completion) { [weak self] in self?.hide() })
        win.orderFrontRegardless()
        window = win
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

private struct GhostCursorRun: View {
    let onArrive: () -> Void
    let onDone: () -> Void

    @State private var progress: CGFloat = 0
    @State private var visible = false

    /// Політ навмисно РІВНОМІРНИЙ. Фірмова крива (0.22, 1, 0.36, 1) дуже
    /// передня: дві третини шляху вона проходить за перші 0.3 с, і жест
    /// читався як миготіння, а не як рух
    private static let travel: Double = 1.6

    var body: some View {
        GeometryReader { geo in
            let startX = geo.size.width * 0.5
            let endX = geo.size.width - 14
            Image(nsImage: NSCursor.arrow.image)
                .interpolation(.high)
                .scaleEffect(1.35)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                .opacity(visible ? 0.9 : 0)
                .position(x: startX + progress * (endX - startX),
                          y: geo.size.height * 0.5)
        }
        .ignoresSafeArea()
        .task {
            withAnimation(.easeOut(duration: 0.3)) { visible = true }
            withAnimation(.easeInOut(duration: Self.travel)) { progress = 1 }
            try? await Task.sleep(for: .seconds(Self.travel + 0.1))
            // Привид біля краю - тепер панель виїжджає, наче він її викликав
            onArrive()
            try? await Task.sleep(for: .seconds(0.25))
            withAnimation(.easeIn(duration: 0.45)) { visible = false }
            try? await Task.sleep(for: .seconds(0.5))
            onDone()
        }
    }
}
