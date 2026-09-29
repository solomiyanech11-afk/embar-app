//
//  ReaderPenTextView.swift
//  Embar
//
//  Selectable-текст запису для пен-режиму (SPEC §4.2; прототип
//  handleReaderSelectionHighlight): показує RAW-текст (індекси 1:1 з
//  Highlight.start/end), користувач тягне виділення мишкою — після
//  відпускання діапазон летить у onSelect, виділення знімається.
//  Трюк: mouseDown → super проганяє ВЕСЬ drag-цикл, після повернення
//  selectedRange уже фінальний.
//

import SwiftUI
import AppKit

struct ReaderPenTextView: NSViewRepresentable {
    let text: String
    let kind: ReaderEntryKind
    let spans: [HighlightSpan]
    /// Шрифт тіла з налаштувань (SPEC §4.4) — щоб перо не міняло вигляд
    var bodyFont: ReaderBodyFont = .inter
    /// true — пен-режим (виділяємо мишкою); false — просто показ хайлайтів
    /// (суцільне товсте підкреслення через атрибут, як у прототипі)
    var selectable: Bool = true
    /// Обгорнути в лапки «…» (цитати показу): індекси хайлайтів зсуваються
    /// на 1, лапки хугають текст природно (не летять у кінець рядка)
    var quoted: Bool = false
    var onSelect: (NSRange) -> Void = { _ in }

    /// Зсув індексів через провідну лапку
    private var offset: Int { quoted ? 1 : 0 }
    private var displayString: String { quoted ? "\u{201C}\(text)\u{201D}" : text }
    /// Спани, зсунуті у простір displayString
    private var shiftedSpans: [HighlightSpan] {
        guard quoted else { return spans }
        return spans.map { HighlightSpan(start: $0.start + offset, end: $0.end + offset,
                                         colorName: $0.colorName, mode: $0.mode) }
    }

    func makeNSView(context: Context) -> PenTextView {
        let tv = PenTextView()
        tv.isEditable = false
        tv.isSelectable = selectable
        tv.showsIBeam = selectable
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        // Наш layout manager: гасить системну заливку виділення в УСІХ
        // станах фокуса (Theme/SelectionColor.swift). Без нього виділення
        // в записі грубішало, щойно вьюха переставала бути first responder
        tv.textContainer?.replaceLayoutManager(EmbarSelectionLayoutManager())
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        // Системну заливку виділення прибрано — малюємо свою, snug
        // (PenTextView.drawSnugSelection). Пара до
        // EmbarSelectionLayoutManager вище: атрибути прибирають заливку у
        // сфокусованому стані, layout manager — в усіх решті
        tv.selectedTextAttributes = [.backgroundColor: NSColor.clear]
        return tv
    }

    func updateNSView(_ tv: PenTextView, context: Context) {
        tv.isSelectable = selectable
        tv.showsIBeam = selectable
        tv.onSelect = selectable ? onSelect : nil
        tv.textStorage?.setAttributedString(attributed())
        // Заливки малює draw() заокругленими (як word-flow показу) —
        // квадратні атрибутні фони прибрано (фідбек 2026-07-07)
        tv.fillSegments = ReaderHighlightRender.segments(
            length: (displayString as NSString).length, spans: shiftedSpans)
            .compactMap { segment in
                guard let fill = segment.fill
                    .flatMap(HighlightColor.init(rawValue:)) else { return nil }
                return (segment.range, fill.nsColor)
            }
        tv.needsDisplay = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PenTextView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0,
              let container = nsView.textContainer,
              let layout = nsView.layoutManager else { return nil }
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return CGSize(width: width, height: ceil(used.height))
    }

    /// Raw-текст у типографіці типу + наявні хайлайти (щоб у пен-режимі
    /// було видно, що вже зафарбовано)
    private func attributed() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        // Те саме міжряддя, що у word-flow показу (lineSpacing 5) —
        // інакше в пен-режимі текст виглядав щільнішим/«меншим» (фідбек)
        paragraph.lineSpacing = 5
        let font: NSFont
        let color: NSColor
        if kind == .quote {
            font = NSFont(name: "Fraunces-Italic", size: 14.5)
                ?? NSFont(name: "Fraunces Italic", size: 14.5)
                ?? .systemFont(ofSize: 14.5)
            color = NoteTypography.inkColor
        } else {
            font = bodyFont.nsFont(13.5)
            color = NoteTypography.inkColor
        }
        let attr = NSMutableAttributedString(
            string: displayString,
            attributes: [.font: font, .foregroundColor: color,
                         .paragraphStyle: paragraph])
        for segment in ReaderHighlightRender.segments(
            length: (displayString as NSString).length, spans: shiftedSpans) {
            let fill = segment.fill.flatMap(HighlightColor.init(rawValue:))
            let stroke = segment.stroke.flatMap(HighlightColor.init(rawValue:))
            // Заливка НЕ атрибутом (квадратні кути) — її малює drawFills.
            // Підкреслення — атрибут .thick: суцільне через пробіли й
            // ширше, як у прототипі (фідбек 2026-07-13)
            if let stroke {
                attr.addAttribute(.underlineStyle,
                                  value: NSUnderlineStyle.thick.rawValue,
                                  range: segment.range)
                attr.addAttribute(.underlineColor,
                                  value: fill != nil ? stroke.combinedStrokeNSColor
                                                     : stroke.strokeNSColor,
                                  range: segment.range)
            }
        }
        return attr
    }
}

final class PenTextView: NSTextView {
    var onSelect: ((NSRange) -> Void)?
    /// Режим показу (false) не ловить курсор і не виділяє
    var showsIBeam = true
    /// Діапазони заливок (малюються заокругленими під текстом)
    var fillSegments: [(range: NSRange, color: NSColor)] = []

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event) // весь drag-цикл виділення всередині
        let range = selectedRange()
        if range.length > 0 {
            onSelect?(range)
            setSelectedRange(NSRange(location: 0, length: 0))
        }
    }

    // I-beam лише в пен-режимі (де виділяють текст)
    override func resetCursorRects() {
        if showsIBeam { addCursorRect(bounds, cursor: .iBeam) }
    }

    // Зміна фокуса міняє ТОН нашого виділення (активний ↔ тихий) — просимо
    // перемальовку самі, бо системної заливки, яку інвалідовував AppKit,
    // більше немає (EmbarSelectionLayoutManager)
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        return accepted
    }

    /// Те саме для key-стану вікна: перехід у чужу програму сам вьюху не
    /// інвалідує (див. EmbarSelection.observeKeyChanges)
    private var keyObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = EmbarSelection.observeKeyChanges(for: self)
    }

    nonisolated deinit {
        keyObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        needsDisplay = true
        return resigned
    }

    // Розширення КОЖНОЇ інвалідації: і заливки, і виділення малюються на
    // 2pt ширше по X та 1pt по Y за межі гліфів, а drag виділення
    // перемальовує лише дельту — тож на місцях колишніх країв лишались
    // тоновані смужки в 1–2 px до самого відпускання миші (ревʼю
    // 2026-08-18, знахідка 8). Той самий прийом, що в EmbarTextView
    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        super.setNeedsDisplay(rect.insetBy(dx: -3, dy: -3),
                              avoidAdditionalLayout: flag)
    }

    // Заокруглені заливки ПІД текстом (той самий вигляд, що word-flow
    // показу; підхід — snug-хайлайт M4 EmbarTextView)
    override func draw(_ dirtyRect: NSRect) {
        drawFills()
        drawSnugSelection()
        super.draw(dirtyRect)
    }

    /// Виділення тією ж snug-геометрією, що й заливки (ревізія
    /// 2026-08-17). Тон — наш спільний (Theme/SelectionColor.swift), бо
    /// системний брав відтінок з акценту macOS і синій/зелений до теплого
    /// паперу не пасував. Висоту теж правимо: системна заливка бере всю
    /// рядкову коробку разом із міжрядковим простором і виглядала грубою.
    ///
    /// Тут це ще й WYSIWYG: у пен-режимі людина тягне виділення, щоб
    /// зробити хайлайт, — тепер прев'ю рівно тієї форми, що й результат.
    /// Пара до цього — `selectedTextAttributes` із прозорим тлом, який
    /// ставить ReaderPenTextView
    private func drawSnugSelection() {
        let ranges = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty, let lm = layoutManager, let tc = textContainer,
              let storage = textStorage, storage.length > 0 else { return }
        let origin = textContainerOrigin
        (EmbarSelection.isEmphasized(self) ? EmbarSelection.tint
                                          : EmbarSelection.inactive).setFill()
        for range in ranges {
            let clamped = NSIntersectionRange(
                range, NSRange(location: 0, length: storage.length))
            guard clamped.length > 0 else { continue }
            let font = storage.attribute(.font, at: clamped.location,
                                         effectiveRange: nil) as? NSFont
                ?? .systemFont(ofSize: 13.5)
            let glyphs = lm.glyphRange(forCharacterRange: clamped,
                                       actualCharacterRange: nil)
            lm.enumerateLineFragments(forGlyphRange: glyphs) {
                _, _, _, lineRange, _ in
                let piece = NSIntersectionRange(lineRange, glyphs)
                guard piece.length > 0 else { return }
                let rect = lm.boundingRect(forGlyphRange: piece, in: tc)
                let snugHeight = font.ascender - font.descender + 2
                let rr = NSRect(x: rect.minX + origin.x - 2,
                                y: rect.minY + origin.y - 1,
                                width: rect.width + 4,
                                height: min(rect.height + 2, snugHeight + 2))
                NSBezierPath(roundedRect: rr, xRadius: 3, yRadius: 3).fill()
            }
        }
    }

    private func drawFills() {
        guard !fillSegments.isEmpty,
              let lm = layoutManager, let tc = textContainer,
              let storage = textStorage else { return }
        let origin = textContainerOrigin
        for segment in fillSegments {
            guard segment.range.length > 0,
                  segment.range.location + segment.range.length <= storage.length
            else { continue }
            let font = storage.attribute(.font, at: segment.range.location,
                                         effectiveRange: nil) as? NSFont
                ?? .systemFont(ofSize: 13.5)
            segment.color.setFill()
            let glyphs = lm.glyphRange(forCharacterRange: segment.range,
                                       actualCharacterRange: nil)
            // ❗ По рядкових фрагментах, НЕ enumerateEnclosingRects:
            // той віддає багаторядковий діапазон трьома блоками (перший
            // рядок · середина одним високим блоком · останній), а кламп
            // висоти «під рядок» зʼїдав середні рядки — у хайлайті на
            // 3+ рядки середина лишалась білою (баг, фідбек 2026-07-22)
            lm.enumerateLineFragments(forGlyphRange: glyphs) {
                _, _, _, lineRange, _ in
                let piece = NSIntersectionRange(lineRange, glyphs)
                guard piece.length > 0 else { return }
                let rect = lm.boundingRect(forGlyphRange: piece, in: tc)
                // Snug-висота від шрифту: коробка рядка включає lineSpacing
                let snugHeight = font.ascender - font.descender + 2
                let rr = NSRect(x: rect.minX + origin.x - 2,
                                y: rect.minY + origin.y - 1,
                                width: rect.width + 4,
                                height: min(rect.height + 2, snugHeight + 2))
                NSBezierPath(roundedRect: rr, xRadius: 3, yRadius: 3).fill()
            }
        }
    }
}
