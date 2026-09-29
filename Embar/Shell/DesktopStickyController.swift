//
//  DesktopStickyController.swift
//  Embar
//
//  Контролер ОДНОГО стіка-віджета: вікно + SwiftUI-хостинг.
//  Життєвим циклом керує DesktopStickyManager — вікно існує рівно тоді,
//  коли isFloating && deletedAt == nil && !archived (інваріант SPEC §2.7).
//

import AppKit
import SwiftData
import SwiftUI

@MainActor
final class DesktopStickyController: NSObject, NSWindowDelegate {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    let stickerID: UUID
    /// Живий обʼєкт mainContext: контролер пише сюди позицію/розмір.
    /// Фізичного purge боятися нічого — вікно закривається ще при soft-delete
    private let sticker: Sticker
    private let window: DesktopStickyPanel
    /// Дебаунс запису позиції: windowDidMove сипле подіями весь драг
    private var saveTask: Task<Void, Never>?

    /// Стартовий розмір нового віджета; висота — авто під текст
    /// (230 → 190, фідбек 2026-07-30: «трохи менше»)
    static let defaultSize = NSSize(width: 190, height: 96)
    // Межі розумного clamp (SPEC §2.7); minWidth 170 → 140 (2026-07-30:
    // авто-ширина «обіймає» короткий текст щільніше). nonisolated —
    // чисті константи для targetSize і юніт-тестів
    nonisolated static let minWidth: CGFloat = 140
    nonisolated static let maxWidth: CGFloat = 380
    /// Стеля АВТО-ширини (фідбек 2026-07-30: «вужчий, хай росте в
    /// висоту») — довгий текст переноситься, а не тягне вікно до 380;
    /// ширше — лише ручним ресайзом за правий край
    nonisolated static let autoMaxWidth: CGFloat = 240
    nonisolated static let minHeight: CGFloat = 64
    nonisolated static let maxHeight: CGFloat = 420

    init(sticker: Sticker, cascadeIndex: Int) {
        stickerID = sticker.id
        self.sticker = sticker
        window = DesktopStickyPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        super.init()

        // Смуга робочого стола: над іконками, ПІД усіма вікнами програм —
        // як системні віджети macOS (рішення §2.7). БЕЗ .fullScreenAuxiliary:
        // на fullscreen-Spaces віджет не зʼявляється взагалі. .stationary —
        // поводиться як стіл в Mission Control/Exposé.
        window.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // ❗ Дефолт NSPanel — true: віджети зникали б, щойно Embar втрачає
        // активність — а неактивність для нього нормальний стан
        window.hidesOnDeactivate = false
        // Клік по фону тягне вікно, не крадучи клавіатуру; клік у текст
        // зробить вікно key сам
        window.becomesKeyOnlyIfNeeded = true
        // ❗ БЕЗ isMovableByWindowBackground (стоп-баг 2026-07-30,
        // SPEC §15.49): системний драг-за-фон на не-key вікні йде
        // server-side і перехоплював краї раніше за ручки ресайзу —
        // тому ресайз «працював лише в редагуванні». Драг за тіло —
        // власний performDrag у DesktopStickyPanel.mouseDown
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        // Світлий вигляд завжди — як панель (dark mode — M6)
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        // Курсор ресайзу має зʼявлятися з наведення на край ЗАВЖДИ, не лише
        // коли вікно key (редагування): гарантуємо доставку mouse-moved/
        // cursorUpdate неактивному вікну
        window.acceptsMouseMovedEvents = true
        window.delegate = self

        let root = DesktopStickyView(sticker: sticker,
                                     onContentHeight: { [weak self] height in
                                         self?.contentHeightChanged(height)
                                     },
                                     onContentIdealWidth: { [weak self] width in
                                         self?.contentIdealWidthChanged(width)
                                     },
                                     onRequestKey: { [weak self] in
                                         self?.window.makeKey()
                                     },
                                     onOpenSettings: { [weak self] in
                                         self?.toggleSettingsPopup()
                                     })
            .modelContainer(EmbarApp.sharedModelContainer)
            .defaultAppStorage(EmbarDefaults.store)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []   // розмір вікна диктує контролер

        // Контейнер: SwiftUI-контент + ручки ресайзу по правому/нижньому краю
        let container = NSView()
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        let rightHandle = WidgetResizeEdgeView(edge: .right)
        let bottomHandle = WidgetResizeEdgeView(edge: .bottom)
        let cornerHandle = WidgetResizeEdgeView(edge: .corner)
        // Кут ОСТАННІМ — вище в hit-тесті за смужки країв
        for handle in [rightHandle, bottomHandle, cornerHandle] {
            handle.onResizeBegan = { [weak self] edge in
                self?.beginManualResize(edge: edge)
            }
            handle.onResizeEnd = { [weak self] edge, frame in
                self?.manualResizeEnded(edge: edge, frame: frame)
            }
            handle.onResizeCancelled = { [weak self] in
                self?.manualResizeCancelled()
            }
            // Живий мінімум: висота поточного тексту (title/full) + падінги
            handle.minHeightProvider = { [weak self] in
                self?.currentMinHeight ?? Self.minHeight
            }
            handle.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(handle)
        }
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rightHandle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rightHandle.topAnchor.constraint(equalTo: container.topAnchor),
            rightHandle.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rightHandle.widthAnchor.constraint(equalToConstant: 6),
            bottomHandle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomHandle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomHandle.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottomHandle.heightAnchor.constraint(equalToConstant: 6),
            cornerHandle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            cornerHandle.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            cornerHandle.widthAnchor.constraint(equalToConstant: 14),
            cornerHandle.heightAnchor.constraint(equalToConstant: 14),
        ])
        window.contentView = container

        window.setFrame(Self.initialFrame(for: sticker, cascadeIndex: cascadeIndex),
                        display: false)
        // Невидимим, поки не прийде перший виміряний розмір: показ одразу
        // світив плейсхолдерну рамку на долю секунди — віджет «будувався
        // пополам» (фідбек 2026-07-30). Зʼявиться мʼяким fade вже
        // правильного розміру (applyAutoSize); страховка — 0.4с
        window.alphaValue = 0
        // Не активує застосунок і не смикає Space
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.revealIfNeeded()
        }
    }

    /// Перший показ: рамка вже справжня — мʼякий fade (поява стіка =
    /// легальний рух поверхні, §7.2-A)
    private var hasRevealed = false
    private func revealIfNeeded() {
        guard !hasRevealed else { return }
        hasRevealed = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 1
        }
    }

    func close() {
        // Флаш, НЕ скасування: рух в останні 0.4с перед закриттям
        // (хрестик, видалення, вихід) губився — дебаунс не встигав
        // (code review 2026-07-30)
        flushPendingSave()
        closeSettingsPopup()
        window.orderOut(nil)
        window.close()
    }

    /// Дотиснути незбережену позицію негайно (закриття вікна / вихід
    /// із застосунку)
    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        saveFrame()
    }

    /// Драг-відкріплення з панелі: вікно їде за курсором — курсор тримає
    /// середину хедера (SPEC §2.7)
    func followDrag(at screenPoint: NSPoint) {
        var frame = window.frame
        frame.origin.x = screenPoint.x - frame.width / 2
        frame.origin.y = screenPoint.y - frame.height + 14
        window.setFrame(frame, display: true)
    }

    // MARK: - Попап налаштувань (⋯): острівець збоку віджета (SPEC §2.7)

    private var settingsPopup: DesktopStickyPanel?
    private var clickMonitors: [Any] = []
    /// Момент закриття кліком-повз: клік по ⋯ спершу ловить монітор
    /// (mouseDown закриває), потім кнопка (mouseUp) — без цієї позначки
    /// тогл одразу відкривав попап знову
    private var settingsClosedAt: Date = .distantPast

    private func toggleSettingsPopup() {
        if settingsPopup != nil {
            closeSettingsPopup()
        } else if Date.now.timeIntervalSince(settingsClosedAt) > 0.35 {
            openSettingsPopup()
        }
    }

    private func openSettingsPopup() {
        guard !sticker.isDeleted else { return }
        let popup = DesktopStickyPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        popup.level = window.level
        popup.collectionBehavior = window.collectionBehavior
        popup.hidesOnDeactivate = false
        popup.becomesKeyOnlyIfNeeded = true
        popup.backgroundColor = .clear
        popup.isOpaque = false
        popup.hasShadow = true
        popup.appearance = NSAppearance(named: .aqua)
        popup.isReleasedWhenClosed = false
        // Острівець прибитий до віджета — сам не тягається (знахідка 7)
        popup.dragsByBody = false

        let root = DesktopStickySettingsView(sticker: sticker)
            .modelContainer(EmbarApp.sharedModelContainer)
            .defaultAppStorage(EmbarDefaults.store)
        let hosting = NSHostingView(rootView: root)
        popup.contentView = hosting
        var size = hosting.fittingSize
        if size.width < 50 || size.height < 50 {
            size = NSSize(width: 186, height: 250)
        }

        // Праворуч від віджета, верхи вирівняні; не влазить — ліворуч
        let vf = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? window.frame
        var x = window.frame.maxX + 8
        if x + size.width > vf.maxX { x = window.frame.minX - size.width - 8 }
        let y = min(window.frame.maxY, vf.maxY) - size.height
        popup.setFrame(NSRect(x: x, y: max(y, vf.minY),
                              width: size.width, height: size.height),
                       display: false)

        // Дочірнє вікно — їздить разом із драгом віджета
        window.addChildWindow(popup, ordered: .above)
        popup.orderFrontRegardless()
        settingsPopup = popup

        // Клік повз попап (у будь-якій програмі чи нашій) закриває його
        let close: (NSPoint) -> Void = { [weak self] location in
            guard let self, let popup = self.settingsPopup else { return }
            if !popup.frame.contains(location) {
                self.settingsClosedAt = .now
                self.closeSettingsPopup()
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { _ in close(NSEvent.mouseLocation) }) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { event in close(NSEvent.mouseLocation); return event }) {
            clickMonitors.append(local)
        }
    }

    private func closeSettingsPopup() {
        clickMonitors.forEach { NSEvent.removeMonitor($0) }
        clickMonitors = []
        guard let popup = settingsPopup else { return }
        settingsPopup = nil
        window.removeChildWindow(popup)
        popup.orderOut(nil)
        popup.close()
    }

    // MARK: - Авто-висота під текст (SPEC §2.7)

    private var lastContentHeight: CGFloat = 0
    /// Йде ручний драг ручкою: авто-розмір і збереження позиції ЗАМОРОЖЕНІ.
    /// ❗ Корінь бага «відскакує назад» (2026-07-30): довгий драг встигав
    /// тригернути дебаунс-збереження позиції → мутація моделі → ре-рендер →
    /// PreferenceKey → авто-висота асинхронно повертала «природну» висоту
    /// ПОСЕРЕД драгу, а mouseUp записував у floatH вже відкочену рамку.
    /// Виняток (ревʼю П1): під час драгу ПРАВОГО краю авто-висота живе
    /// (лише висота — ширину тримає драг), щоб текст, який переноситься
    /// на більше рядків при звуженні, не лишався обрізаним до mouseUp
    private var isManuallyResizing = false
    private var resizingEdge: WidgetResizeEdgeView.Edge?

    /// Ідеальна (без переносу) ширина тексту
    private var lastIdealWidth: CGFloat = 0

    /// Природна висота контенту з SwiftUI (PreferenceKey)
    private func contentHeightChanged(_ contentHeight: CGFloat) {
        lastContentHeight = contentHeight
        applyAutoSize()
    }

    private func contentIdealWidthChanged(_ idealWidth: CGFloat) {
        lastIdealWidth = idealWidth
        applyAutoSize()
    }

    /// Мінімальна висота вікна ЗАРАЗ: не менше за вміст у поточному
    /// режимі — драг ручкою впирається в цю межу без відскоку
    private var currentMinHeight: CGFloat {
        max(Self.minHeight, min(lastContentHeight, Self.maxHeight))
    }

    /// Перше застосування висоти (створення/відновлення) — миттєве;
    /// далі зміни висоти анімуються (розгортання/згортання — рух
    /// реальної поверхні, §7.2-A)
    private var hasAppliedHeightOnce = false
    /// Крива прототипу — та сама, що слайд панелі
    private static let heightTiming = CAMediaTimingFunction(
        controlPoints: 0.4, 0, 0.2, 1)

    /// Вікно НІКОЛИ не нижче природної висоти вмісту — текст не
    /// обрізається в принципі; ручні floatW/floatH діють поверх авто.
    /// Ширина (floatW == nil): обіймає найдовший рядок тексту,
    /// clamp 140–380; далі перенос і ріст висоти. Верхній лівий кут
    /// прибитий — ріст вправо-вниз, як стікер на моніторі.
    /// Рамку читаємо ВСЕРЕДИНІ async-блоку
    /// ЄДИНА функція правди про розмір вікна (інваріант SPEC §2.7,
    /// рефактор 2026-07-30; чиста — покрита юніт-тестами):
    /// висота = clamp(max(природна, ручна), min, max) — вікно ніколи не
    /// менше за текст, «…» можливе лише на стелі maxHeight; ширина =
    /// ручна або «обійми найдовший рядок» (ideal + падінги 24), clamp
    nonisolated static func targetSize(naturalContentHeight: CGFloat,
                                       idealTextWidth: CGFloat,
                                       manualWidth: CGFloat?,
                                       manualHeight: CGFloat?) -> NSSize {
        let naturalH = min(max(naturalContentHeight, minHeight), maxHeight)
        let height = max(naturalH, min(manualHeight ?? naturalH, maxHeight))
        let width: CGFloat
        if let manualWidth {
            width = min(max(manualWidth, minWidth), maxWidth)
        } else {
            width = min(max(idealTextWidth + 24, minWidth), autoMaxWidth)
        }
        return NSSize(width: width, height: height)
    }

    private func applyAutoSize() {
        guard !sticker.isDeleted else { return }
        // Правий край: висота слідує за переносом тексту прямо в драгу
        let heightOnly = resizingEdge == .right
        guard !isManuallyResizing || heightOnly else { return }
        let target = Self.targetSize(
            naturalContentHeight: lastContentHeight,
            idealTextWidth: lastIdealWidth,
            manualWidth: sticker.floatW.map { CGFloat($0) },
            manualHeight: sticker.floatH.map { CGFloat($0) })
        let targetH = target.height
        let targetW = target.width
        // Не з середини view-апдейту SwiftUI (preference приходить звідти)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let heightOnlyNow = self.resizingEdge == .right
            guard !self.isManuallyResizing || heightOnlyNow else { return }
            var frame = self.window.frame
            var changed = false
            if abs(frame.height - targetH) > 0.5 {
                frame.origin.y += frame.height - targetH
                frame.size.height = targetH
                changed = true
            }
            // Ширину під час правого драгу тримає РУКА — не чіпаємо
            if !heightOnlyNow, abs(frame.width - targetW) > 0.5 {
                frame.size.width = targetW
                changed = true
            }
            // Ріст вниз не виштовхує текст за екран/під Dock: низ вікна
            // впирається у visibleFrame — верх при потребі підіймається,
            // каретка лишається видимою (знахідка 8)
            if let vf = (self.window.screen ?? NSScreen.main)?.visibleFrame,
               frame.origin.y < vf.minY {
                frame.origin.y = vf.minY
                changed = true
            }
            // Розмір уже правильний (відновлення з floatW/H) — показ одразу
            guard changed else { self.revealIfNeeded(); return }
            if self.hasAppliedHeightOnce, !heightOnlyNow {
                // Плавний ріст/танення (фідбек 2026-07-30: «нічого не
                // появляється різко»); animator ретаргетиться сам, якщо
                // ціль зміниться посеред анімації
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = Self.heightTiming
                    self.window.animator().setFrame(frame, display: true)
                }
            } else {
                // Перше застосування і живий драг — миттєво (анімація
                // в драгу відставала б від руки)
                self.hasAppliedHeightOnce = true
                self.window.setFrame(frame, display: true)
            }
            // Розмір справжній — можна показуватись
            self.revealIfNeeded()
        }
    }

    private func beginManualResize(edge: WidgetResizeEdgeView.Edge) {
        // Захоплення ручки закриває редагування (скрін 2026-08-18): текст
        // поля верстає field editor, який отримує ширину В МОМЕНТ початку
        // редагування і під живу зміну рамки вікна НЕ переверстується —
        // рядки лишались перенесеними по старій ширині й обрізались правим
        // краєм аж до зміни фокуса. Показовий Text переверстується наживо
        // (виняток П1 нижче) — тож на час драгу лишаємо саме його.
        // makeFirstResponder(nil) → FocusState у вьюсі → endEditing:
        // той самий штатний вихід, що клік повз, зміни тексту зберігаються.
        // Робимо це ДО прапорця isManuallyResizing: разова мутація
        // updatedAt на старті драгу нешкідлива, рамка ще не рухалась
        if window.firstResponder is NSTextView {
            window.makeFirstResponder(nil)
        }
        isManuallyResizing = true
        resizingEdge = edge
        saveTask?.cancel()   // жодних мутацій моделі під час драгу
    }

    /// Клік по ручці без руху: розморозити авто-розмір, НІЧОГО не
    /// фіксуючи (code review 2026-07-30 — випадковий клік вимикав авто)
    private func manualResizeCancelled() {
        isManuallyResizing = false
        resizingEdge = nil
        applyAutoSize()
    }

    /// Кінець ручного ресайзу: правий край фіксує ширину (авто-висота живе
    /// далі — текст пере-переноситься); нижній/кут фіксує висоту. Позиція
    /// пишеться тут же (низ/кут рухають origin.y), одним махом, без
    /// дебаунсу. Стиснули нижче за вміст — applyAutoSize виросте назад.
    private func manualResizeEnded(edge: WidgetResizeEdgeView.Edge,
                                   frame: NSRect) {
        isManuallyResizing = false
        resizingEdge = nil
        guard !sticker.isDeleted else { return }
        switch edge {
        case .right:
            sticker.floatW = frame.width
        case .bottom:
            sticker.floatH = frame.height
        case .corner:
            sticker.floatW = frame.width
            sticker.floatH = frame.height
        }
        sticker.floatX = frame.origin.x
        sticker.floatY = frame.maxY   // верхній край, як у saveFrame
        sticker.updatedAt = .now
        applyAutoSize()
    }

    /// Той самий брендовий field editor, що в панелі (SPEC §15.54):
    /// у віджеті текст стіка теж редагують TextField-и, і без цього
    /// каретка на столі йшла б за акцентом системи
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        BrandFieldEditors.editor(for: sender)
    }

    /// Драг вікна (isMovableByWindowBackground) сипле windowDidMove
    /// безперервно — пишемо в модель раз, коли рух ущух. Під час ресайзу
    /// ручкою — мовчимо (позицію збереже manualResizeEnded)
    func windowDidMove(_ notification: Notification) {
        guard !isManuallyResizing else { return }
        scheduleSaveFrame()
    }

    private func scheduleSaveFrame() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            self?.saveFrame()
        }
    }

    private func saveFrame() {
        guard !sticker.isDeleted else { return }
        let frame = window.frame
        // floatY — ВЕРХНІЙ край (якір авто-висоти): збереження нижнього
        // зсувало віджет після перезапуску, коли висота відновлювалась
        // дефолтною і доростала вже від іншого верху (ревʼю Б2).
        // Не смикати updatedAt, якщо позиція фактично не змінилась
        guard sticker.floatX != frame.origin.x
            || sticker.floatY != frame.maxY else { return }
        sticker.floatX = frame.origin.x
        sticker.floatY = frame.maxY
        sticker.updatedAt = .now
    }

    // MARK: - Clamp при зміні екранів (SPEC §2.7)

    /// Віджет поза видимою областю (відʼєднали монітор) — повернути на
    /// головний екран. Позицію збереже windowDidMove після setFrame.
    func clampToVisibleScreens() {
        let visible = NSScreen.screens.map(\.visibleFrame)
        guard let fallback = NSScreen.main?.visibleFrame ?? visible.first else { return }
        let clamped = Self.clampedFrame(window.frame, visible: visible,
                                        fallback: fallback)
        if clamped != window.frame {
            window.setFrame(clamped, display: true)
            scheduleSaveFrame()
        }
    }

    /// Чиста геометрія (юніт-тести): рамка лишається, якщо хоч 20pt видно
    /// на будь-якому екрані; інакше — притискається в межі fallback-екрана
    nonisolated static func clampedFrame(_ frame: NSRect, visible: [NSRect],
                                         fallback: NSRect) -> NSRect {
        let mustSee = frame.insetBy(dx: 20, dy: 20)
        if visible.contains(where: { $0.intersects(mustSee) }) { return frame }
        var f = frame
        f.origin.x = min(max(f.origin.x, fallback.minX), fallback.maxX - f.width)
        f.origin.y = min(max(f.origin.y, fallback.minY), fallback.maxY - f.height)
        return f
    }

    /// Рамка при створенні: збережена позиція (floatX = лівий, floatY =
    /// ВЕРХНІЙ край — якір авто-висоти) або каскад від верхнього лівого
    /// кута екрана вниз-вправо (правий верх ховав нові віджети за панеллю)
    private static func initialFrame(for sticker: Sticker,
                                     cascadeIndex: Int) -> NSRect {
        let size = NSSize(
            width: sticker.floatW.map { CGFloat($0) } ?? defaultSize.width,
            height: sticker.floatH.map { CGFloat($0) } ?? defaultSize.height)
        if let x = sticker.floatX, let top = sticker.floatY {
            return NSRect(x: x, y: top - size.height,
                          width: size.width, height: size.height)
        }
        let vf = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let step = CGFloat(cascadeIndex % 10) * 26
        return NSRect(x: vf.minX + 60 + step,
                      y: vf.maxY - size.height - 60 - step,
                      width: size.width, height: size.height)
    }
}
