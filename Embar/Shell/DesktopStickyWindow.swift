//
//  DesktopStickyWindow.swift
//  Embar
//
//  Вікно стіка-віджета на робочому столі (SPEC §2.7).
//
//  ОКРЕМИЙ клас, НЕ EmbarPanel: (а) його isKeyWindow=true — хак для однієї
//  головної панелі; десяток «завжди key» вікон зламав би фокус і рендер;
//  (б) його constrainFrameRect-passthrough дозволив би затягнути віджет
//  повністю за екран. Клас також служить маркером: PanelController виключає
//  ці вікна з mouseInsideAppWindow (курсор над віджетом ≠ «миша в панелі»).
//

import AppKit

final class DesktopStickyPanel: NSPanel {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    /// Потрібно для редагування тексту прямо у віджеті (nonactivating:
    /// вікно стає key без активації застосунку — як головна панель)
    override var canBecomeKey: Bool { true }

    /// Попап налаштувань — той самий клас, але ПРИБИТИЙ до свого віджета:
    /// драг за тіло вимикається, інакше натиск на заголовок/розділювач
    /// відтягував острівець від стіка (code review 2026-07-30, знахідка 7)
    var dragsByBody = true

    /// Драг за тіло віджета — ВЛАСНИЙ, не isMovableByWindowBackground
    /// (стоп-баг 2026-07-30, SPEC §15.49): системний драг-за-фон на
    /// не-key вікні йде server-side по кешованому «draggable region» і
    /// перехоплював mouseDown на краях раніше за ручки ресайзу. Тут же:
    /// клік, який не зайняли ручки/кнопки/текст (SwiftUI пропускає
    /// неінтерактивні зони вгору по responder chain), спливає до вікна —
    /// тягнемо його внутрішньопроцесним performDrag, який із ручками
    /// не конфліктує ніколи.
    override func mouseDown(with event: NSEvent) {
        guard dragsByBody else { return }
        performDrag(with: event)
    }
}

/// Ручка ресайзу віджета (правий/нижній край + кут) — той самий прийом,
/// що ResizeHandleView головної панелі: borderless-вікно нативного ресайзу
/// не має. Тягне свій край, протилежний і ВЕРХ лишаються на місці;
/// шрифти не масштабуються — текст лише пере-переноситься (SPEC §2.7)
final class WidgetResizeEdgeView: NSView {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    enum Edge { case right, bottom, corner }
    let edge: Edge
    /// Початок драгу (який край) — контролер заморожує авто-розмір і
    /// збереження позиції (інакше вони билися з драгом і відкочували
    /// рамку); для правого краю лишає живою лише авто-висоту
    var onResizeBegan: ((Edge) -> Void)?
    /// Кінець драгу (який край + фінальна рамка) — контролер фіксує
    /// розмір у floatW/floatH
    var onResizeEnd: ((Edge, NSRect) -> Void)?
    /// Клік без руху — контролер лише розморожує авто-розмір, нічого
    /// не фіксуючи
    var onResizeCancelled: (() -> Void)?

    private var startFrame: NSRect = .zero
    private var startMouse: NSPoint = .zero
    /// Чи був реальний рух (>2pt): клік без драгу НЕ має фіксувати
    /// floatW/floatH — випадковий mouseUp на 6pt-краю назавжди вимикав
    /// авто-розмір без шляху назад (code review 2026-07-30)
    private var dragged = false

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

    /// Драг по ручці — це ресайз, НЕ переміщення вікна
    override var mouseDownCanMoveWindow: Bool { false }

    /// Не-key вікно не має зʼїдати перший клік — ручка ловить його одразу
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Живий мінімум висоти від контролера: висота поточного тексту в
    /// поточному режимі (title/full) + падінги. Драг упирається в цю межу
    /// прямо в русі — без «дозволь і відскоч» (вимога 2026-07-30)
    var minHeightProvider: (() -> CGFloat)?

    private var cursor: NSCursor {
        switch edge {
        case .right: return .resizeLeftRight
        case .bottom: return .resizeUpDown
        case .corner:
            if #available(macOS 15.0, *) {
                return .frameResize(position: .bottomRight, directions: .all)
            }
            return .crosshair
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    /// Курсор і над НЕ-key вікном: cursorUpdate macOS пригнічує для
    /// неактивного застосунку, тому дублюємо через mouseEntered/Exited —
    /// вони з .activeAlways доставляються завжди. Якщо система курсор
    /// все ж перемалює — відоме обмеження, ресайз працює незалежно
    /// від курсора (SPEC §2.7)
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseEnteredAndExited,
                      .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseEntered(with event: NSEvent) { cursor.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        startFrame = window?.frame ?? .zero
        startMouse = NSEvent.mouseLocation
        dragged = false
        onResizeBegan?(edge)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let loc = NSEvent.mouseLocation
        if !dragged, abs(loc.x - startMouse.x) < 2, abs(loc.y - startMouse.y) < 2 {
            return   // тремтіння в межах кліку — ще не драг
        }
        dragged = true
        // База — ПОТОЧНА рамка, не startFrame: під час right-драгу жива
        // авто-висота (П1) міняє висоту, і рамка зі startFrame відкочувала
        // б її кожен рух — висота джиттерила (code review 2026-07-30).
        // Виміри, які тягне рука, рахуються від startFrame/startMouse
        var frame = window.frame
        if edge == .right || edge == .corner {
            frame.size.width = min(max(startFrame.width + (loc.x - startMouse.x),
                                       DesktopStickyController.minWidth),
                                   DesktopStickyController.maxWidth)
        }
        if edge == .bottom || edge == .corner {
            // Origin у AppKit — нижній лівий: тягнемо низ, верх стоїть.
            // Мінімум — жива висота вмісту: курсор упирається в межу
            let minH = minHeightProvider?() ?? DesktopStickyController.minHeight
            let height = min(max(startFrame.height - (loc.y - startMouse.y), minH),
                             DesktopStickyController.maxHeight)
            frame.origin.y = startFrame.maxY - height
            frame.size.height = height
        }
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard let window else { return }
        // Без руху — без фіксації розміру: авто-режим лишається авто
        guard dragged else {
            onResizeCancelled?()
            return
        }
        onResizeEnd?(edge, window.frame)
    }
}
