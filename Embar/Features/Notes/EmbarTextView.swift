//
//  EmbarTextView.swift
//  Embar
//
//  NSTextView тіла нотатки. Placeholder, Escape-вихід, урізана каретка,
//  кастомне малювання хайлайту (щільна заокруглена підсвітка) і рамки цитати,
//  Enter у списках/цитатах. Вставка-нормалізація й згадки — кроки 7–8.
//

import AppKit

final class EmbarTextView: NSTextView {
    /// Escape (без відкритих попапів) — закрити редактор
    var onEscape: (() -> Void)?
    /// Налаштування рендеру (для маркерів списку / стилів) — оновлює NoteBodyView
    var docSettings: NoteDocSettings = .default
    /// Клік по чіпу-згадці → навігація (UUID згаданої нотатки)
    var onMentionClick: ((UUID) -> Void)?
    /// Клік по підпису цитати Рідера (M5): (bookID, entryID)
    var onReaderSourceClick: ((UUID, UUID) -> Void)?

    /// Клавіші попапа згадок. true = спожито (попап відкритий)
    enum MentionKey { case up, down, commit, close }
    var mentionKeyHandler: ((MentionKey) -> Bool)?

    /// Оживити фрагмент, що приїхав ззовні (драг або вставка нашого архіву):
    /// attachment-и фото декодуються БЕЗ резолвера — зображення живуть у
    /// NoteImage, не в архіві, тож без цього кроку ряд намалювався б сірими
    /// плитками. Ставить NoteBodyView → NoteEditorModel
    var onReviveFragment: ((NSMutableAttributedString) -> Void)?

    /// ⌘B / ⌘I — ті самі дії, що кнопки тулбара (через модель: вона ще й
    /// оновлює підсвітку кнопок і планує збереження)
    var onToggleBold: (() -> Void)?
    var onToggleItalic: (() -> Void)?

    /// Текст-підказка, коли тіло порожнє (прототип «Почніть писати…»)
    var placeholder: String = "" {
        didSet { needsDisplay = true }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// ⌘B / ⌘I. ❗ Саме `performKeyEquivalent`, а не `doCommand`: без
    /// пункту меню «Формат» ці комбінації не перетворюються на селектор,
    /// а системний `NSFontManager.addFontTrait` нам не підходить — він
    /// міняє шрифт напряму, повз наші атрибути `.embarBold`/`.embarItalic`,
    /// і стан кнопок тулбара розʼїхався б із текстом
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, isEditable else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": onToggleBold?(); return onToggleBold != nil
        case "i": onToggleItalic?(); return onToggleItalic != nil
        default: return super.performKeyEquivalent(with: event)
        }
    }

    /// ↑/↓/Enter/Escape при відкритому попапі згадок — у попап, фокус
    /// лишається в text view (як у прототипі)
    override func doCommand(by selector: Selector) {
        if let handler = mentionKeyHandler {
            switch selector {
            case #selector(moveUp(_:)):        if handler(.up) { return }
            case #selector(moveDown(_:)):      if handler(.down) { return }
            case #selector(insertNewline(_:)): if handler(.commit) { return }
            case #selector(cancelOperation(_:)): if handler(.close) { return }
            default: break
            }
        }
        super.doCommand(by: selector)
    }

    // MARK: - Чіпи-згадки: клік і атомарність виділення

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let uuid = mentionUUID(at: point) {
            onMentionClick?(uuid)
            return
        }
        // Підпис цитати з Рідера (M5): клік веде до запису-джерела
        if let source = readerSource(at: point),
           let separator = source.firstIndex(of: "|"),
           let bookID = UUID(uuidString: String(source[..<separator])),
           let entryID = UUID(uuidString: String(source[source.index(after: separator)...])) {
            onReaderSourceClick?(bookID, entryID)
            return
        }
        super.mouseDown(with: event)
    }

    private func readerSource(at point: NSPoint) -> String? {
        attributeValue(.embarReaderSource, at: point) as? String
    }

    // MARK: - Hover по слотах фото (пігулка «обітнути/замінити/видалити»)

    struct PhotoHoverInfo: Equatable {
        let charIndex: Int
        let slotIndex: Int
        let imageID: String?
        let columns: Int
        let imageIDs: [String]
        /// Рект слота в координатах видимої області тіла (top-left)
        let rectInBody: CGRect
    }
    var onPhotoHover: ((PhotoHoverInfo?) -> Void)?
    private var photoTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = photoTracking { removeTrackingArea(old) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited,
                                            .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        photoTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        reportPhotoHover(at: point)
        updateReaderSourceHover(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPhotoHover?(nil)
        updateReaderSourceHover(at: nil)
    }

    // MARK: - Ховер підпису цитати Рідера (M5): темніший колір + pointer,
    // щоб було видно клікабельність (фідбек 2026-07-07)

    private var hoveredSourceRun: NSRange?

    private func updateReaderSourceHover(at point: NSPoint?) {
        guard let storage = textStorage else { return }
        var newRun: NSRange?
        if let point, attributeValue(.embarReaderSource, at: point) != nil,
           let index = characterIndex(at: point) {
            var run = NSRange()
            if storage.attribute(.embarReaderSource, at: index,
                                 longestEffectiveRange: &run,
                                 in: NSRange(location: 0, length: storage.length)) != nil {
                newRun = run
            }
        }
        guard newRun != hoveredSourceRun else { return }
        // ❗ ТИМЧАСОВІ атрибути layout manager, не storage: ховер —
        // стан UI, він не має потрапляти в архів тіла (code review M5 #10:
        // відкладений autosave міг зберегти темний колір назавжди)
        if let old = hoveredSourceRun, old.location + old.length <= storage.length {
            layoutManager?.removeTemporaryAttribute(.foregroundColor,
                                                    forCharacterRange: old)
        }
        if let run = newRun {
            layoutManager?.addTemporaryAttribute(.foregroundColor,
                                                 value: NoteTypography.inkColor,
                                                 forCharacterRange: run)
        }
        hoveredSourceRun = newRun
    }

    private func reportPhotoHover(at point: NSPoint) {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage,
              storage.length > 0 else { onPhotoHover?(nil); return }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var frac: CGFloat = 0
        let glyph = lm.glyphIndex(for: local, in: tc, fractionOfDistanceThroughGlyph: &frac)
        let idx = lm.characterIndexForGlyph(at: glyph)
        guard idx < storage.length,
              let att = storage.attribute(.attachment, at: idx, effectiveRange: nil)
                as? EmbarPhotoRowAttachment else {
            onPhotoHover?(nil); return
        }
        let gr = lm.glyphRange(forCharacterRange: NSRange(location: idx, length: 1),
                               actualCharacterRange: nil)
        let rowRect = lm.boundingRect(forGlyphRange: gr, in: tc)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            .insetBy(dx: 0, dy: 4) // внутрішні відступи cell (див. EmbarPhotoRowCell)
        guard rowRect.contains(point) else { onPhotoHover?(nil); return }
        let slots = att.slotRects(in: rowRect)
        guard let slotIdx = slots.firstIndex(where: { $0.contains(point) }) else {
            onPhotoHover?(nil); return
        }
        let clip = enclosingScrollView?.contentView.bounds.origin ?? .zero
        onPhotoHover?(PhotoHoverInfo(
            charIndex: idx,
            slotIndex: slotIdx,
            imageID: slotIdx < att.imageIDs.count ? att.imageIDs[slotIdx] : nil,
            columns: att.columns,
            imageIDs: att.imageIDs,
            rectInBody: slots[slotIdx].offsetBy(dx: -clip.x, dy: -clip.y)))
    }

    // MARK: - Контекстне меню фото (видалити ряд)

    override func menu(for event: NSEvent) -> NSMenu? {
        if let idx = photoAttachmentIndex(at: convert(event.locationInWindow, from: nil)) {
            let menu = NSMenu()
            let item = NSMenuItem(title: "Видалити фото", action: #selector(deletePhotoRow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = idx
            menu.addItem(item)
            return menu
        }
        return super.menu(for: event)
    }

    private func photoAttachmentIndex(at point: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage,
              storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var frac: CGFloat = 0
        let glyph = lm.glyphIndex(for: local, in: tc, fractionOfDistanceThroughGlyph: &frac)
        let idx = lm.characterIndexForGlyph(at: glyph)
        guard idx < storage.length,
              storage.attribute(.attachment, at: idx, effectiveRange: nil) is EmbarPhotoRowAttachment
        else { return nil }
        return idx
    }

    /// Видалення фото-ряду йде через модель — вона показує undo-тост
    /// (фідбек 2026-07-29); nil — старе локальне видалення (fallback)
    var onPhotoRowDelete: ((Int) -> Void)?

    @objc private func deletePhotoRow(_ sender: NSMenuItem) {
        guard let idx = sender.representedObject as? Int, let storage = textStorage,
              idx < storage.length else { return }
        if let onPhotoRowDelete {
            onPhotoRowDelete(idx)
            return
        }
        let s = storage.string as NSString
        var range = NSRange(location: idx, length: 1)
        if idx + 1 < s.length, s.character(at: idx + 1) == 0x0A { range.length += 1 }
        guard shouldChangeText(in: range, replacementString: "") else { return }
        storage.replaceCharacters(in: range, with: "")
        didChangeText()
        setSelectedRange(NSRange(location: idx, length: 0))
    }

    private func mentionUUID(at point: NSPoint) -> UUID? {
        guard let raw = attributeValue(.embarMention, at: point) as? String else { return nil }
        return UUID(uuidString: raw)
    }

    /// Індекс символа під точкою (nil — точка не над гліфом)
    private func characterIndex(at point: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage,
              storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = lm.glyphIndex(for: local, in: tc, fractionOfDistanceThroughGlyph: &fraction)
        // Перевірити, що точка реально над гліфом (а не в порожнечі рядка)
        let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
        guard rect.insetBy(dx: -2, dy: -2).contains(local) else { return nil }
        let idx = lm.characterIndexForGlyph(at: glyph)
        return idx < storage.length ? idx : nil
    }

    /// Значення атрибута під точкою кліку (спільний хіт-тест чіпів-згадок
    /// і підписів цитат Рідера)
    private func attributeValue(_ key: NSAttributedString.Key, at point: NSPoint) -> Any? {
        guard let idx = characterIndex(at: point), let storage = textStorage else { return nil }
        return storage.attribute(key, at: idx, effectiveRange: nil)
    }

    /// Ран чіпа-згадки, що містить індекс (координатор пробує ним краї
    /// діапазону редагування — O(1) замість обходу документа)
    func mentionRun(at index: Int) -> NSRange? {
        guard let storage = textStorage, index >= 0, index < storage.length else { return nil }
        var eff = NSRange()
        guard storage.attribute(.embarMention, at: index, longestEffectiveRange: &eff,
                                in: NSRange(location: 0, length: storage.length)) is String
        else { return nil }
        return eff
    }

    /// Блок цитати з Рідера — АТОМАРНИЙ (фідбек 2026-07-07: в нотатці він
    /// не редагується, delete зносить цілком). Ран = суміжні символи з
    /// .embarReaderQuote (тіло) чи .embarReaderSource (підпис)
    func readerBlockRun(at index: Int) -> NSRange? {
        guard let storage = textStorage, index >= 0, index < storage.length else { return nil }
        func isBlock(_ i: Int) -> Bool {
            let attrs = storage.attributes(at: i, effectiveRange: nil)
            return attrs[.embarReaderQuote] != nil || attrs[.embarReaderSource] != nil
        }
        guard isBlock(index) else { return nil }
        var start = index
        var end = index + 1
        while start > 0, isBlock(start - 1) { start -= 1 }
        while end < storage.length, isBlock(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Атомарні острови тіла: чіп-згадка або блок цитати з Рідера
    func atomicRun(at index: Int) -> NSRange? {
        mentionRun(at: index) ?? readerBlockRun(at: index)
    }

    // MARK: - Чіп не ламається посеред рядка (P2.20)
    //
    // Прототип: .qn-mention має white-space:nowrap — чіп або вміщається,
    // або переїжджає на новий рядок ЦІЛИМ. Розірваний чіп малював дві
    // пігулки з накладанням фонів. Делегатом layout manager забороняємо
    // перенос УСЕРЕДИНІ рана згадки (той самий чіп ліворуч і праворуч від
    // точки переносу); межа між двома сусідніми чіпами лишається законною

    /// Чи стоїть одразу за/перед раном згадки інший чіп (впритул або через
    /// один NBSP-спейсер) — тоді пігулки малюються зі згорнутим виступом,
    /// щоб не зливатись (P2.21)
    private func mentionAdjacent(_ storage: NSTextStorage, before range: NSRange) -> Bool {
        mentionNeighbor(storage, at: range.location - 1, step: -1)
    }

    private func mentionAdjacent(_ storage: NSTextStorage, after range: NSRange) -> Bool {
        mentionNeighbor(storage, at: range.location + range.length, step: 1)
    }

    private func mentionNeighbor(_ storage: NSTextStorage, at index: Int, step: Int) -> Bool {
        guard index >= 0, index < storage.length else { return false }
        if storage.attribute(.embarMention, at: index, effectiveRange: nil) != nil {
            return true
        }
        // Через NBSP-спейсер, який вставляється слідом за чіпом
        guard (storage.string as NSString).character(at: index) == 0xA0 else { return false }
        let next = index + step
        guard next >= 0, next < storage.length else { return false }
        return storage.attribute(.embarMention, at: next, effectiveRange: nil) != nil
    }

    /// Перенос перед `charIndex` розірвав би чіп?
    private func breakWouldSplitMention(at charIndex: Int) -> Bool {
        guard let storage = textStorage, charIndex > 0, charIndex < storage.length,
              let here = storage.attribute(.embarMention, at: charIndex,
                                           effectiveRange: nil) as? String,
              let prev = storage.attribute(.embarMention, at: charIndex - 1,
                                           effectiveRange: nil) as? String
        else { return false }
        return here == prev
    }

    /// Delete біля атома: діапазон видалення обчислюється ДО системної пари
    /// shouldChangeText → didChangeText, тож розширення «зачепив частково —
    /// зноситься цілком» робимо теж ДО неї: виділяємо атом повністю, і super
    /// видаляє вже виділення звичайним шляхом. Це єдиний спосіб отримати
    /// часткове видалення з клавіатури — виділення снапить
    /// selectionRange(forProposedRange:) нижче.
    /// ❗ Розширювати правку ЗСЕРЕДИНИ делегатського shouldChangeTextIn не
    /// можна: вкладена заміна під час незавершеної зовнішньої пари ламала
    /// облік undo NSTextView — перший же ⌘Z стирав увесь документ
    /// (блокер тест-плану 2026-08-25)
    private func snapDeletionToAtom(forward: Bool) {
        let sel = selectedRange()
        guard sel.length == 0 else { return } // виділення вже покриває атоми
        let idx = forward ? sel.location : sel.location - 1
        guard idx >= 0, let run = atomicRun(at: idx) else { return }
        setSelectedRange(run)
    }

    /// Backspace на початку тексту пункту списку розформатовує пункт (R1),
    /// на початку абзацу цитати — знімає цитату (R2); обидва БЕЗ злиття,
    /// другий Backspace іде звичайним шляхом
    private func handleSpecialBackspace() -> Bool {
        NoteFormatter.handleListBackspace(self, settings: docSettings)
            || NoteFormatter.handleQuoteBackspace(self, settings: docSettings)
    }

    /// Видалення, що зливає абзаци, лікується ПІСЛЯ super: формат голови
    /// накладається на весь злитий абзац (цитата повертає собі влитий рядок,
    /// пункт — влитий текст; фантомні атрибути хвоста зачищаються). План
    /// обчислюється до super (голова ще жива); якщо super нічого не змінив
    /// (делегат відмовив) — лікування не торкається документа, щоб не
    /// лишити в undo порожню пару
    private func withMergeHeal(forward: Bool, _ body: () -> Void) {
        guard let storage = textStorage else { return body() }
        let sel = selectedRange()
        let probe: NSRange
        if sel.length > 0 {
            probe = sel
        } else if forward {
            probe = NSRange(location: sel.location, length: sel.location < storage.length ? 1 : 0)
        } else {
            probe = NSRange(location: max(sel.location - 1, 0), length: sel.location > 0 ? 1 : 0)
        }
        let plan = NoteFormatter.mergeHealPlan(in: self, deleting: probe)
        let lengthBefore = storage.length
        body()
        if storage.length != lengthBefore {
            NoteFormatter.applyMergeHeal(plan, to: self, settings: docSettings)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        if handleSpecialBackspace() { return }
        snapDeletionToAtom(forward: false)
        withMergeHeal(forward: false) { super.deleteBackward(sender) }
    }

    override func deleteForward(_ sender: Any?) {
        snapDeletionToAtom(forward: true)
        withMergeHeal(forward: true) { super.deleteForward(sender) }
    }

    override func deleteWordBackward(_ sender: Any?) {
        if handleSpecialBackspace() { return }
        snapDeletionToAtom(forward: false)
        withMergeHeal(forward: false) { super.deleteWordBackward(sender) }
    }

    override func deleteWordForward(_ sender: Any?) {
        snapDeletionToAtom(forward: true)
        withMergeHeal(forward: true) { super.deleteWordForward(sender) }
    }

    /// Каретка не може стояти ВСЕРЕДИНІ чіпа/блоку; виділення охоплює їх цілком
    /// Каретка НІКОЛИ не стоїть усередині атома (P2.22): мишачий шлях
    /// снапить selectionRange(forProposedRange:) нижче, але стрілки ←/→
    /// ходять повз нього — крок за кроком заводили каретку в чіп, і там
    /// можна було друкувати, розрізаючи його. Тут — спільний вузол, через
    /// який проходить КОЖНА зміна виділення: голу каретку всередині атома
    /// виштовхуємо за напрямком руху (з-перед чіпа вправо → за чіп),
    /// а без напрямку — до ближчого краю
    override func setSelectedRanges(_ ranges: [NSValue],
                                    affinity: NSSelectionAffinity,
                                    stillSelecting: Bool) {
        var out = ranges
        if ranges.count == 1, let r = ranges.first?.rangeValue, r.length == 0,
           let storage = textStorage, storage.length > 0, r.location < storage.length {
            if let run = atomicRun(at: r.location),
               r.location > run.location, r.location < run.location + run.length {
                let old = selectedRange().location
                let target: Int
                if old <= run.location {
                    target = run.location + run.length          // рух управо
                } else if old >= run.location + run.length {
                    target = run.location                        // рух уліво
                } else {
                    let mid = run.location + run.length / 2      // без напрямку
                    target = r.location <= mid ? run.location : run.location + run.length
                }
                out = [NSValue(range: NSRange(location: target, length: 0))]
            } else if let zone = NoteFormatter.markerZone(at: r.location, in: storage) {
                // Зона маркера списку «•⇥» (R1): гола каретка тут не стоїть —
                // друк перед/усередині маркера ламав би структуру пункту.
                // Рух уліво з початку тексту перескакує маркер на кінець
                // попереднього рядка; решта шляхів — на початок тексту пункту
                let contentStart = zone.location + zone.length
                let old = selectedRange().location
                let target: Int
                if old == contentStart, zone.location > 0 {
                    target = zone.location - 1  // крок ← із межі: перескочити маркер
                } else {
                    target = contentStart       // стрибок/клік/↑↓ → початок тексту
                }
                out = [NSValue(range: NSRange(location: target, length: 0))]
            }
        }
        super.setSelectedRanges(out, affinity: affinity, stillSelecting: stillSelecting)
    }

    override func selectionRange(forProposedRange proposedCharRange: NSRange,
                                 granularity: NSSelectionGranularity) -> NSRange {
        var r = super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
        guard let storage = textStorage, storage.length > 0 else { return r }
        if r.length == 0 {
            if let run = atomicRun(at: min(r.location, storage.length - 1)), r.location > run.location {
                // всередині чіпа/блоку → до ближчого краю
                let mid = run.location + run.length / 2
                r.location = r.location <= mid ? run.location : run.location + run.length
            } else if let zone = NoteFormatter.markerZone(at: r.location, in: storage) {
                // клік у зоні маркера списку → каретка на початок тексту пункту
                r.location = zone.location + zone.length
            }
            return r
        }
        if let startRun = atomicRun(at: r.location), r.location > startRun.location {
            r = NSUnionRange(r, startRun)
        }
        if let zone = NoteFormatter.markerZone(at: r.location, in: storage), r.location > zone.location {
            r = NSUnionRange(r, zone) // виділення, що почалось усередині маркера, бере його цілим
        }
        let endIdx = r.location + r.length - 1
        if let endRun = atomicRun(at: min(endIdx, storage.length - 1)),
           endIdx < endRun.location + endRun.length - 1 {
            r = NSUnionRange(r, endRun)
        }
        if let zone = NoteFormatter.markerZone(at: endIdx, in: storage),
           endIdx < zone.location + zone.length - 1 {
            r = NSUnionRange(r, zone) // кінець виділення всередині маркера → маркер цілком
        }
        return r
    }

    // Стрілочка над клікабельним підписом цитати — через систему
    // cursor rects (ручний NSCursor.set() NSTextView одразу перебивав)
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage,
              storage.length > 0 else { return }
        let origin = textContainerOrigin
        let noSelection = NSRange(location: NSNotFound, length: 0)
        storage.enumerateAttribute(.embarReaderSource,
                                   in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil else { return }
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            lm.enumerateEnclosingRects(forGlyphRange: glyphs,
                                       withinSelectedGlyphRange: noSelection,
                                       in: tc) { rect, _ in
                self.addCursorRect(rect.offsetBy(dx: origin.x, dy: origin.y),
                                   cursor: .pointingHand)
            }
        }
    }

    /// Enter: у списку — продовжити/вийти; у цитаті/заголовку — вийти у
    /// звичайний текст; на порожньому вирівняному рядку — скинути
    /// вирівнювання. Shift+Enter — новий рядок У МЕЖАХ блоку (line separator
    /// U+2028, той самий абзац: цитата/заголовок продовжуються без відступів)
    override func insertNewline(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            insertLineBreak(sender)
            return
        }
        if NoteFormatter.handleListReturn(self, settings: docSettings) { return }
        if NoteFormatter.handleSpecialReturn(self, settings: docSettings) { return }
        super.insertNewline(sender)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true // сховати/показати placeholder + перемалювати декор
    }

    // Зміна фокуса міняє ТОН нашого виділення (активний ↔ тихий), а
    // малюємо його ми — тож і перемальовку просимо самі: система
    // інвалідовувала рівно свою заливку, якої більше немає
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        needsDisplay = true
        return resigned
    }

    /// Підписка на key-стан вікна: виділення тихішає разом із рештою
    /// застосунку, коли людина йде в іншу програму (див.
    /// EmbarSelection.isEmphasized)
    private var keyObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = EmbarSelection.observeKeyChanges(for: self)
    }

    nonisolated deinit {
        keyObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Плавний автоскрол (P2.18)

    /// Штатний автоскрол NSTextView (набір, Enter, вставка) СМИКАЄ кліп у
    /// цільову точку миттєво: коли рядок із курсором доходив до тулбара,
    /// текст стрибав одразу на висоту рядка — читалось, ніби курсор зник.
    /// Тут той самий мінімальний доскрол, але коротким рухом: видно, що
    /// текст прокручується. Reduce Motion — системний миттєвий шлях
    override func scrollRangeToVisible(_ range: NSRange) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              window != nil,
              let scroll = enclosingScrollView,
              let lm = layoutManager, let tc = textContainer,
              let rect = rectForAutoscroll(range, lm, tc) else {
            super.scrollRangeToVisible(range)
            return
        }
        let clip = scroll.contentView
        let insets = scroll.contentInsets
        let visible = clip.bounds
        // Запас, щоб рядок не сидів упритул до межі (тулбара/верху)
        let margin: CGFloat = 8
        let targetY: CGFloat
        if rect.maxY > visible.maxY - insets.bottom {
            targetY = rect.maxY + margin - (visible.height - insets.bottom)
        } else if rect.minY < visible.minY + insets.top {
            targetY = rect.minY - margin - insets.top
        } else {
            return // уже видно — не рухаємось
        }
        let minY = -insets.top
        let maxY = max(minY, frame.height - visible.height + insets.bottom)
        let clamped = min(max(targetY, minY), maxY)
        guard abs(clamped - visible.minY) > 0.5 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(NSPoint(x: visible.minX, y: clamped))
        }
        scroll.reflectScrolledClipView(clip)
    }

    /// Рект рядка, який має стати видимим: для виділення — його гліфи, для
    /// голої каретки — рядковий фрагмент (у хвості порожнього документа —
    /// extraLineFragment). nil — хай працює системний шлях
    private func rectForAutoscroll(_ range: NSRange, _ lm: NSLayoutManager,
                                   _ tc: NSTextContainer) -> NSRect? {
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect: NSRect
        if glyphs.length > 0 {
            rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        } else if glyphs.location < lm.numberOfGlyphs {
            rect = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        } else if lm.extraLineFragmentTextContainer != nil {
            rect = lm.extraLineFragmentRect
        } else if lm.numberOfGlyphs > 0 {
            rect = lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1, effectiveRange: nil)
        } else {
            return nil
        }
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    // MARK: - Вставка з нормалізацією (SPEC §15.24) і lossless-копіювання

    /// Cmd+V: зовнішній rich-текст приводиться до нашої схеми; внутрішній
    /// фрагмент Embar вставляється без втрат (PasteNormalizer.read)
    override func paste(_ sender: Any?) {
        guard let normalized = PasteNormalizer.read(NSPasteboard.general,
                                                    settings: docSettings) else {
            // Нічого, що ми вміємо читати (наприклад, самі лише картинки) —
            // хай вирішує AppKit: importsGraphics = false їх однаково не пустить
            return super.paste(sender)
        }
        // ❗ Розпізнали, але після нормалізації нічого не лишилось (вставка
        // з самих лише невидимих символів) — саме НІЧОГО й вставляємо.
        // Раніше тут спрацьовував super.paste і сипав сирий rich-текст повз
        // усю нормалізацію (ревʼю 2026-08-20)
        guard normalized.length > 0 else { return }
        // Наш власний фрагмент міг привезти ряд фото — резолвер зображень
        // транзієнтний і в архів не потрапляє (див. onReviveFragment)
        let insert = NSMutableAttributedString(attributedString: normalized)
        onReviveFragment?(insert)
        // Вставка всередину цитати → весь фрагмент набуває її стилю (R2)
        if NoteFormatter.insertionTargetIsQuote(self) {
            NoteFormatter.adoptQuoteStyle(insert, settings: docSettings)
        }
        guard insert.length > 0 else { return }
        let sel = selectedRange()
        guard shouldChangeText(in: sel, replacementString: insert.string) else { return }
        textStorage?.replaceCharacters(in: sel, with: insert)
        didChangeText()
        setSelectedRange(NSRange(location: sel.location + insert.length, length: 0))
        NoteFormatter.refreshTypingAttributes(self)
        NoteFormatter.renumber(self, settings: docSettings)
    }

    /// Копіювання: додатково кладемо власний архів-фрагмент — вставка в іншу
    /// нотатку Embar пройде без нормалізації (зі згадками/хайлайтами)
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.writablePasteboardTypes + [PasteNormalizer.internalType]
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == PasteNormalizer.internalType {
            let sel = selectedRange()
            guard sel.length > 0, let storage = textStorage,
                  let data = NoteArchiver.encode(storage.attributedSubstring(from: sel))
            else { return false }
            pboard.setData(data, forType: type)
            return true
        }
        return super.writeSelection(to: pboard, type: type)
    }

    // MARK: - Індикатор дропу (фідбек 2026-08-28): AppKit малює каретку
    // драгу лише для СВОЇХ типів тексту - для нашого фрагмента місце
    // приземлення було невидиме, людина цілилась навмання. Малюємо самі:
    // фрагмент із рядом фото снапиться до межі абзацу (фото не можна
    // вставити в середину слова - лише порожній рядок або початок абзацу,
    // текст зʼїжджає вниз) і показується планкою на всю ширину; чистий
    // текст - точною вертикальною кареткою.

    /// Куди впаде дроп: індекс символу + режим «цілим рядом» (фото)
    private(set) var dropIndicator: (index: Int, wholeRow: Bool)?
    /// Кеш «фрагмент драгу містить ряд фото» на одну драг-сесію
    /// (draggingUpdated сипле щокадру - декодувати архів щоразу дорого)
    private var dragFragmentHasPhoto: (changeCount: Int, has: Bool)?
    /// Снап, який мусить застосувати readSelection цього дропу
    private var pendingSnapIndex: Int?

    /// Файловий драг (Finder, мініатюра скріншота) відхиляємо ЦІЛКОМ:
    /// importsGraphics=false не дає AppKit взяти файл як картинку, і він
    /// робив дурний фолбек - вставляв ШЛЯХ до файлу текстом
    /// («/var/folders/…», фідбек 2026-08-28). Фото заходять лише через
    /// свій конвеєр (пікер → даунскейл → NoteImage); дроп зображень у
    /// той самий конвеєр - беклог
    private func isFileDrag(_ pb: NSPasteboard) -> Bool {
        guard pb.data(forType: PasteNormalizer.internalType) == nil else { return false }
        let fileTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        ]
        return pb.availableType(from: fileTypes) != nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isFileDrag(sender.draggingPasteboard) else { return [] }
        let op = super.draggingEntered(sender)
        updateDropIndicator(sender, operation: op)
        return op
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isFileDrag(sender.draggingPasteboard) else {
            clearDropIndicator()
            return []
        }
        let op = super.draggingUpdated(sender)
        updateDropIndicator(sender, operation: op)
        return op
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearDropIndicator()
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !isFileDrag(sender.draggingPasteboard) else { return false } // страховка
        pendingSnapIndex = dropIndicator?.index
        defer {
            pendingSnapIndex = nil
            clearDropIndicator()
            dragFragmentHasPhoto = nil
        }
        return super.performDragOperation(sender)
    }

    private func clearDropIndicator() {
        guard dropIndicator != nil else { return }
        dropIndicator = nil
        needsDisplay = true
    }

    private func updateDropIndicator(_ info: NSDraggingInfo, operation: NSDragOperation) {
        // Лише для нашого фрагмента: для чужих типів каретку малює AppKit
        guard operation != [],
              info.draggingPasteboard.data(forType: PasteNormalizer.internalType) != nil
        else { clearDropIndicator(); return }
        let point = convert(info.draggingLocation, from: nil)
        var index = characterIndexForInsertion(at: point)
        let wholeRow = fragmentHasPhotoRow(info.draggingPasteboard)
        if wholeRow { index = paragraphBoundary(near: index, point: point) }
        if dropIndicator?.index != index || dropIndicator?.wholeRow != wholeRow {
            dropIndicator = (index, wholeRow)
            needsDisplay = true
        }
    }

    private func fragmentHasPhotoRow(_ pb: NSPasteboard) -> Bool {
        if let cached = dragFragmentHasPhoto, cached.changeCount == pb.changeCount {
            return cached.has
        }
        var has = false
        if let data = pb.data(forType: PasteNormalizer.internalType),
           let decoded = NoteArchiver.decode(data) {
            decoded.enumerateAttribute(.attachment,
                                       in: NSRange(location: 0, length: decoded.length)) { v, _, stop in
                if v is EmbarPhotoRowAttachment { has = true; stop.pointee = true }
            }
        }
        dragFragmentHasPhoto = (pb.changeCount, has)
        return has
    }

    /// Найближча межа абзацу: верхня половина абзацу під курсором - його
    /// початок, нижня - початок наступного
    private func paragraphBoundary(near index: Int, point: NSPoint) -> Int {
        guard let storage = textStorage, storage.length > 0 else { return 0 }
        let s = storage.string as NSString
        let clamped = min(index, storage.length - 1)
        let pr = s.paragraphRange(for: NSRange(location: clamped, length: 0))
        guard let lm = layoutManager, let tc = textContainer else { return pr.location }
        let glyphs = lm.glyphRange(forCharacterRange: pr, actualCharacterRange: nil)
        let rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        let localY = point.y - textContainerOrigin.y
        // >= : нічия на точній середині йде «вниз» (після абзацу) - дроп
        // на рівні останнього рядка означає «під ним», не «перед ним»
        return localY >= rect.midY ? NSMaxRange(pr) : pr.location
    }

    /// Намалювати індикатор (кличе draw(_:) поверх тексту)
    private func drawDropIndicatorIfNeeded() {
        guard let ind = dropIndicator, let lm = layoutManager,
              let tc = textContainer else { return }
        let origin = textContainerOrigin
        let length = textStorage?.length ?? 0
        // Той самий брендовий колір, що в каретки (ставить NoteBodyView)
        let color = insertionPointColor ?? NSColor(embarHex: "#FE3B43")

        func fragmentRect(at charIndex: Int) -> NSRect {
            let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1),
                                       actualCharacterRange: nil)
            return lm.boundingRect(forGlyphRange: glyphs, in: tc)
        }

        if ind.wholeRow {
            // Планка на всю ширину: «ряд фото ляже СЮДИ»
            let y: CGFloat
            if length == 0 {
                y = origin.y
            } else if ind.index >= length {
                y = fragmentRect(at: length - 1).maxY + origin.y
            } else {
                y = fragmentRect(at: ind.index).minY + origin.y
            }
            let pad = tc.lineFragmentPadding
            let bar = NSRect(x: origin.x + pad, y: y - 1,
                             width: max(tc.size.width - pad * 2, 0), height: 2)
            color.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
        } else {
            // Точна вертикальна каретка (2pt, як своя) - AppKit для нашого
            // типу свою не малює
            var rect: NSRect
            var x: CGFloat
            if length == 0 {
                rect = NSRect(x: 0, y: 0, width: 0,
                              height: NoteTypography.font(role: .p).pointSize * 1.4)
                x = origin.x
            } else if ind.index >= length {
                rect = fragmentRect(at: length - 1)
                x = rect.maxX + origin.x
            } else {
                rect = fragmentRect(at: ind.index)
                x = rect.minX + origin.x
            }
            let font = (typingAttributes[.font] as? NSFont) ?? NoteTypography.font(role: .p)
            let caretHeight = min(ceil(font.ascender - font.descender), rect.height)
            let caret = NSRect(x: x, y: rect.maxY + origin.y - caretHeight,
                               width: 2, height: caretHeight)
            color.setFill()
            NSBezierPath(roundedRect: caret, xRadius: 1, yRadius: 1).fill()
        }
    }

    /// ❗ Дроп не питає readablePasteboardTypes (діагностика 2026-08-28):
    /// тип для дропу AppKit звужує до acceptableDragTypes - ОКРЕМОГО,
    /// зашитого списку стандартних типів (RTFD/RTF/HTML/файли), який наш
    /// override readablePasteboardTypes не живить. Наш тип туди не входив,
    /// RTFD відкинуто через importsGraphics=false - лишався RTF, який
    /// викидає attachment-и і всі .embar*-атрибути. Тому перший фікс
    /// (лише readSelection) тримав ⌘V, але не драг: фото зникали, чіпи й
    /// хайлайти тихо гинули. Ставимо свій тип першим і для драгу
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        [PasteNormalizer.internalType] + super.acceptableDragTypes
    }

    /// Незнайомий тип super не приймає (повертає порожню маску) - кажемо
    /// явно: фрагмент Embar приймаємо. .generic лишає рішення move/copy
    /// за системною семантикою драгу (усередині вьюхи - move, з Option -
    /// copy), як і в стандартних типів
    override func dragOperation(for dragInfo: NSDraggingInfo,
                                type: NSPasteboard.PasteboardType) -> NSDragOperation {
        if type == PasteNormalizer.internalType {
            return dragInfo.draggingSourceOperationMask.contains(.generic)
                ? .generic : .copy
        }
        return super.dragOperation(for: dragInfo, type: type)
    }

    /// ❗ Читати наш фрагмент теж мусимо САМІ (блокер F2, тест-план
    /// 2026-08-25). Перетягування всередині нотатки — це round-trip через
    /// пейстборд: writeSelection на старті драгу, readSelection на дропі.
    /// Писали ми свій тип, а читав AppKit чужий (RTFD) — а RTFD не знає ні
    /// нашого підкласу attachment-а, ні uuid-ів фото (зображення живуть у
    /// NoteImage, файлової обгортки в attachment-а немає), ні `.embar*`-
    /// маркерів. Тож на місце ряду фото приземлявся ПОРОЖНІЙ attachment,
    /// а оригінал драг уже видалив — фото зникали назовсім. Свій тип
    /// стоїть першим, отже виграє в будь-якого чужого представлення
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [PasteNormalizer.internalType] + super.readablePasteboardTypes
    }

    override func readSelection(from pboard: NSPasteboard,
                                type: NSPasteboard.PasteboardType) -> Bool {
        guard type == PasteNormalizer.internalType else {
            return super.readSelection(from: pboard, type: type)
        }
        guard let data = pboard.data(forType: type),
              let decoded = NoteArchiver.decode(data), decoded.length > 0,
              let storage = textStorage else { return false }
        let fragment = NSMutableAttributedString(attributedString: decoded)
        onReviveFragment?(fragment)
        // Дроп: приземлення в точку, яку показував індикатор (для фото -
        // снап до межі абзацу), а не в сиру точку відпускання
        if let snap = pendingSnapIndex {
            setSelectedRange(NSRange(location: min(snap, storage.length), length: 0))
        }
        let sel = selectedRange()
        // Межа «кінець документа без переносу»: ряд фото мусить жити на
        // власному рядку - інакше приклеївся б у хвіст останнього абзацу
        if sel.length == 0, sel.location > 0, sel.location == storage.length,
           (storage.string as NSString).character(at: sel.location - 1) != 0x0A,
           fragment.string.contains("\u{FFFC}") {
            fragment.insert(NSAttributedString(string: "\n", attributes: typingAttributes), at: 0)
        }
        // Дроп усередину цитати → фрагмент набуває її стилю (R2, як ⌘V)
        if NoteFormatter.insertionTargetIsQuote(self) {
            NoteFormatter.adoptQuoteStyle(fragment, settings: docSettings)
        }
        guard fragment.length > 0 else { return false }
        guard shouldChangeText(in: sel, replacementString: fragment.string) else { return false }
        storage.replaceCharacters(in: sel, with: fragment)
        didChangeText()
        setSelectedRange(NSRange(location: sel.location + fragment.length, length: 0))
        NoteFormatter.refreshTypingAttributes(self)
        NoteFormatter.renumber(self, settings: docSettings)
        return true
    }

    // MARK: - Каретка (природна висота шрифту, притиснута донизу рядка)

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var r = rect
        let font = (typingAttributes[.font] as? NSFont) ?? NoteTypography.font(role: .p)
        let caretHeight = ceil(font.ascender - font.descender)
        if r.height > caretHeight {
            r.origin.y = rect.maxY - caretHeight
            r.size.height = caretHeight
        }
        // 2pt замість системного волоска (фідбек 2026-08-17: «надто
        // тоненький»). Причина не в ширині, а в контрасті: брендовий
        // червоний на теплому світлому тлі дає ~3.2:1, тож однопіксельна
        // риска читалась блідою — при тій самій ширині чорнильна виглядала
        // щільніше. Ширший штрих повертає вагу, не змінюючи кольору.
        // setNeedsDisplay нижче вже розширює інвалідацію на 3pt, тож
        // слідів від блимання не лишається
        r.size.width = 2
        super.drawInsertionPoint(in: r, color: color, turnedOn: flag)
    }

    // Розширення КОЖНОЇ інвалідації: каретка (урізана) і декор виходять за
    // рамки гліфів — чіп-пігулка на 3pt по X, підсвітки на 2–2.5pt по Y.
    // Без цього лишалися «сліди» при частковій перемальовці
    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        super.setNeedsDisplay(rect.insetBy(dx: -3, dy: -3), avoidAdditionalLayout: flag)
    }

    // MARK: - Малювання
    // ❗ Декор — на початку draw(_:), НЕ в drawBackground(in:): з
    // drawsBackground=false AppKit drawBackground не викликає взагалі —
    // цитата й хайлайт застосовувались, але ніколи не малювались (фідбек
    // 2026-07-05 «цитата не працює»)

    override func draw(_ dirtyRect: NSRect) {
        drawDecorations(in: dirtyRect)
        super.draw(dirtyRect) // текст лягає ПОВЕРХ підсвіток
        drawPlaceholderIfNeeded()
        drawDropIndicatorIfNeeded() // місце приземлення драгу - поверх усього
    }

    /// Повні рани атрибута, що ПЕРЕТИНАЮТЬ діапазон: обхід лише dirty-зони
    /// (а не всього документа — review perf), але ран добудовується до
    /// повного, щоб риска цитати/пігулка не обрізались на межі перемальовки
    private func enumerateFullRuns(_ key: NSAttributedString.Key, in storage: NSTextStorage,
                                   intersecting charRange: NSRange,
                                   _ body: (Any, NSRange) -> Void) {
        var seen = Set<Int>()
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(key, in: charRange) { val, sub, _ in
            guard let val else { return }
            var run = NSRange()
            _ = storage.attribute(key, at: sub.location, longestEffectiveRange: &run, in: full)
            guard seen.insert(run.location).inserted else { return }
            body(val, run)
        }
    }

    /// Чіпи-згадок + хайлайт + риска цитати.
    /// ❗ Вертикаль — від БАЗОВОЇ ЛІНІЇ гліфів (location(forGlyphAt:)), не від
    /// рядкових коробок: коробка включає і зайву висоту lineHeightMultiple
    /// (згори), і міжабзацний відступ paragraphSpacing (знизу 12pt у цитати) —
    /// через це декор з'їжджав нижче тексту (фідбек 2026-07-05)
    private func drawDecorations(in dirtyRect: NSRect) {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage,
              storage.length > 0 else { return }
        let origin = textContainerOrigin

        // Обхід лише символів dirty-зони: раніше три ПОВНІ проходи документа
        // на кожен репейнт (навіть блимання каретки) — O(документ) дарма
        let localDirty = dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: 0, dy: -8)
        let dirtyGlyphs = lm.glyphRange(forBoundingRect: localDirty, in: tc)
        let charRange = lm.characterRange(forGlyphRange: dirtyGlyphs, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        // Чіпи-згадок — м'яка пігулка навколо тексту (прототип .qn-mention)
        enumerateFullRuns(.embarMention, in: storage, intersecting: charRange) { [self] val, range in
            guard val is String else { return }
            // Сусідній чіп впритул (одразу або через NBSP-спейсер):
            // виступ ±3 з того боку згортаємо до 1, інакше пігулки
            // накладались і читались як одна (P2.21)
            let padLeft: CGFloat = mentionAdjacent(storage, before: range) ? 1 : 3
            let padRight: CGFloat = mentionAdjacent(storage, after: range) ? 1 : 3
            NSColor.black.withAlphaComponent(0.06).setFill()
            enumerateSnugLineRects(for: range, pad: 2.5, lm: lm, container: tc, storage: storage) { r in
                let rr = NSRect(x: r.minX + origin.x - padLeft, y: r.minY + origin.y,
                                width: r.width + padLeft + padRight, height: r.height)
                NSBezierPath(roundedRect: rr, xRadius: 6, yRadius: 6).fill()
            }
        }

        // Хайлайт — заокруглені прямокутники навколо базової лінії
        enumerateFullRuns(.embarHighlight, in: storage, intersecting: charRange) { val, range in
            guard let slug = val as? String, let hc = HighlightColor(rawValue: slug) else { return }
            hc.nsColor.setFill()
            enumerateSnugLineRects(for: range, pad: 2, lm: lm, container: tc, storage: storage) { r in
                let rr = NSRect(x: r.minX + origin.x - 1, y: r.minY + origin.y,
                                width: r.width + 2, height: r.height)
                NSBezierPath(roundedRect: rr, xRadius: 4, yRadius: 4).fill()
            }
        }

        // Цитата — тонка риска 2pt кольору ink: від верху першого рядка
        // тексту до низу останнього (за базовими лініями), ±4pt внутрішніх
        NoteTypography.quoteBarColor.setFill()
        enumerateFullRuns(.embarQuote, in: storage, intersecting: charRange) { val, range in
            guard (val as? NSNumber)?.boolValue == true else { return }
            drawQuoteBar(for: range, width: NoteTypography.quoteBarWidth,
                         lm: lm, storage: storage, origin: origin)
        }

        // Цитата з Рідера (M5, прототип .qn-quote): СВІТЛА риска ink4 2.5pt
        NoteTypography.mutedColor.setFill()
        enumerateFullRuns(.embarReaderQuote, in: storage, intersecting: charRange) { val, range in
            guard (val as? NSNumber)?.boolValue == true else { return }
            drawQuoteBar(for: range, width: 2.5,
                         lm: lm, storage: storage, origin: origin)
        }

        // Виділення — ОСТАННІМ: лягає поверх хайлайтів (притемнює їх), але
        // під гліфами (super.draw іде після drawDecorations)
        drawSelection(lm: lm, container: tc, storage: storage, origin: origin)
    }

    /// Власна snug-заливка виділення (ревізія 2026-08-17).
    ///
    /// Системна заливала ВСЮ рядкову коробку, а `lineHeightMultiple` кладе
    /// зайвий простір ЗГОРИ рядка (та сама причина, що в
    /// `drawPlaceholderIfNeeded`) — над текстом висіла порожня смуга, і
    /// виділення виглядало грубим. Тут та сама геометрія, що в хайлайтів:
    /// прямокутник по висоті шрифту навколо базової лінії.
    ///
    /// Пара до цього — `selectedTextAttributes` із прозорим тлом у
    /// NoteBodyView: без нього системна заливка малювалась би поверх.
    private func drawSelection(lm: NSLayoutManager, container tc: NSTextContainer,
                               storage: NSTextStorage, origin: NSPoint) {
        let ranges = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty else { return }
        (EmbarSelection.isEmphasized(self) ? NoteTypography.selectionColor
                                          : EmbarSelection.inactive).setFill()
        for range in ranges {
            // pad 2 — як у хайлайтів, щоб виділення й підсвітка збігались
            enumerateSnugLineRects(for: range, pad: 2, lm: lm,
                                   container: tc, storage: storage) { r in
                let rr = NSRect(x: r.minX + origin.x - 1, y: r.minY + origin.y,
                                width: r.width + 2, height: r.height)
                NSBezierPath(roundedRect: rr, xRadius: 3, yRadius: 3).fill()
            }
        }
    }

    private func drawQuoteBar(for range: NSRange, width: CGFloat,
                              lm: NSLayoutManager, storage: NSTextStorage,
                              origin: NSPoint) {
        let gr = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard gr.length > 0 else { return }
        let font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            ?? NoteTypography.quoteFont()
        let firstFrag = lm.lineFragmentRect(forGlyphAt: gr.location, effectiveRange: nil)
        let firstBaseline = lm.location(forGlyphAt: gr.location).y
        let lastIdx = min(gr.location + gr.length - 1, max(lm.numberOfGlyphs - 1, 0))
        let lastFrag = lm.lineFragmentRect(forGlyphAt: lastIdx, effectiveRange: nil)
        let lastBaseline = lm.location(forGlyphAt: lastIdx).y
        let top = firstFrag.minY + firstBaseline - font.ascender - 4
        let bottom = lastFrag.minY + lastBaseline - font.descender + 4
        let bar = NSRect(x: origin.x + NoteTypography.quoteBarX, y: origin.y + top,
                         width: width, height: max(bottom - top, 4))
        NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
    }

    /// Прямокутники по висоті шрифту навколо базової лінії кожного рядка
    /// діапазону (координати контейнера; origin додає викликач)
    private func enumerateSnugLineRects(for charRange: NSRange, pad: CGFloat,
                                        lm: NSLayoutManager, container tc: NSTextContainer,
                                        storage: NSTextStorage, _ body: @escaping (NSRect) -> Void) {
        let gr = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard gr.length > 0 else { return }
        lm.enumerateLineFragments(forGlyphRange: gr) { fragRect, _, _, lineGlyphs, _ in
            let inter = NSIntersectionRange(gr, lineGlyphs)
            guard inter.length > 0 else { return }
            let hRect = lm.boundingRect(forGlyphRange: inter, in: tc)
            let charIdx = lm.characterIndexForGlyph(at: inter.location)
            let font = (storage.attribute(.font, at: min(charIdx, storage.length - 1),
                                          effectiveRange: nil) as? NSFont)
                ?? NoteTypography.font(role: .p)
            let baseline = lm.location(forGlyphAt: inter.location).y
            let top = fragRect.minY + baseline - font.ascender - pad
            let bottom = fragRect.minY + baseline - font.descender + pad
            body(NSRect(x: hRect.minX, y: top, width: hRect.width, height: bottom - top))
        }
    }

    /// Placeholder — на РІВНІ майбутнього тексту: lineHeightMultiple кладе
    /// зайвий простір ЗГОРИ рядка, тож без компенсації підказка висіла вгорі,
    /// а каретка — внизу (фідбек 2026-07-05 «каретка не там»)
    private func drawPlaceholderIfNeeded() {
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let font = (typingAttributes[.font] as? NSFont) ?? NoteTypography.font(role: .p)
        let natural = ceil(font.ascender - font.descender)
        let multiple = (typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineHeightMultiple ?? 1
        let extra = multiple > 1 ? natural * (multiple - 1) : 0
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NoteTypography.mutedColor,
        ]
        let origin = NSPoint(x: textContainerInset.width + 5,
                             y: textContainerInset.height + extra)
        placeholder.draw(at: origin, withAttributes: attrs)
    }
}

// MARK: - NSLayoutManagerDelegate: заборона переносу всередині чіпа (P2.20)

extension EmbarTextView: NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
        !breakWouldSplitMention(at: charIndex)
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldBreakLineByHyphenatingBeforeCharacterAt charIndex: Int) -> Bool {
        !breakWouldSplitMention(at: charIndex)
    }
}
