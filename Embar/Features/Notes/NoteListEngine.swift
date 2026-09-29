//
//  NoteListEngine.swift
//  Embar
//
//  Списки нотатки (SPEC §3.2). Маркери — літеральні гліфи «glyph\t» у тексті
//  (під TextKit 1 автомаркери NSTextList не рендеряться). Enter продовжує
//  список, Enter на порожньому пункті — виходить; нумеровані перелічуються.
//
//  ❗ Усі ТЕКСТОВІ зміни реєструються через shouldChangeText з реальним
//  replacementString — вставка маркерів під «attributes-only» (nil) ламала
//  undo: Cmd+Z розʼєднував текст і атрибути (ревізія 2026-07-05).
//

import AppKit

extension NoteFormatter {

    static func markerText(_ style: ListStyle, index: Int) -> String {
        "\(style.marker(index: index))\t"
    }

    /// Атрибути маркера пункту (реюз: рушій списків + нормалізація вставки)
    static func markerAttrs(_ role: ParagraphRole, _ style: ListStyle,
                            settings: NoteDocSettings) -> [NSAttributedString.Key: Any] {
        [
            .embarRole: role.rawValue as NSString,
            .embarList: style.rawValue as NSString,
            .font: NoteTypography.font(role: role, settings: settings),
            .foregroundColor: NoteTypography.inkColor,
            .paragraphStyle: NoteTypography.paragraphStyle(role: role, list: style, settings: settings),
        ]
    }

    // MARK: - Зона маркера (захист каретки, R1)

    /// Діапазон «гліф + таб» на початку абзацу пункту списку. nil — якщо
    /// абзац не пункт (нема `.embarList`) або маркера в тексті вже нема
    /// (фантомний атрибут без гліфа — див. guard-и Enter/typing)
    static func markerZone(in storage: NSTextStorage, paragraph pr: NSRange) -> NSRange? {
        guard pr.length > 0, pr.location < storage.length,
              storage.attribute(.embarList, at: pr.location, effectiveRange: nil) != nil
        else { return nil }
        let s = storage.string as NSString
        var contentLen = pr.length
        if s.character(at: pr.location + contentLen - 1) == 0x0A { contentLen -= 1 }
        guard contentLen > 0 else { return nil }
        let tab = s.range(of: "\t", options: [], range: NSRange(location: pr.location, length: contentLen))
        guard tab.location != NSNotFound else { return nil }
        return NSRange(location: pr.location, length: tab.location + tab.length - pr.location)
    }

    /// Зона маркера, в яку потрапляє позиція каретки `index`
    /// (позиція одразу ПІСЛЯ зони — початок тексту пункту — вже легальна)
    static func markerZone(at index: Int, in storage: NSTextStorage) -> NSRange? {
        guard index >= 0, index <= storage.length, storage.length > 0 else { return nil }
        let s = storage.string as NSString
        let pr = s.paragraphRange(for: NSRange(location: min(index, storage.length), length: 0))
        guard let zone = markerZone(in: storage, paragraph: pr),
              index >= zone.location, index < zone.location + zone.length else { return nil }
        return zone
    }

    // MARK: - Перемикання списку

    static func toggleList(_ style: ListStyle, in tv: NSTextView, settings: NoteDocSettings) {
        guard let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()
        let s = storage.string as NSString

        // Порожній док або порожній хвостовий абзац (типово: текст → Enter →
        // клік «список») — маркер прямо в позицію курсора. Раніше ітерація
        // абзаців тут не давала нічого і тогл був no-op (ревізія 2026-07-05)
        let paraAll = storage.length == 0 ? NSRange(location: 0, length: 0) : s.paragraphRange(for: sel)
        if paraAll.length == 0 {
            toggleMarkerAtCaret(style, tv: tv, settings: settings)
            return
        }

        // Абзаци виділення (ВКЛЮЧНО з порожніми) — enclosing-діапазони з \n
        var paragraphs: [NSRange] = []
        var cursor = paraAll.location
        let end = paraAll.location + paraAll.length
        while cursor < end {
            let pr = s.paragraphRange(for: NSRange(location: cursor, length: 0))
            paragraphs.append(pr)
            cursor = pr.location + max(pr.length, 1)
        }

        // Абзаци фото не беруть участі в списках (restyleListParagraph їх
        // пропускає) — і не мають ламати allSame-логіку тоглу
        let textParagraphs = paragraphs.filter { pr in
            guard pr.length > 0, pr.location < storage.length else { return true }
            return !NoteFormatter.isPhotoParagraph(
                storage.attributes(at: pr.location, effectiveRange: nil))
        }
        guard !textParagraphs.isEmpty else { return }
        let allSame = textParagraphs.allSatisfy { pr in
            guard pr.length > 0, pr.location < storage.length else { return false }
            return (storage.attribute(.embarList, at: pr.location, effectiveRange: nil) as? String) == style.rawValue
        }
        let target: ListStyle? = allSame ? nil : style

        // Побудувати заміну ОДНИМ attributed-рядком → одна текстова зміна,
        // чистий один-крок undo
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: paraAll))
        var firstDelta = (removed: 0, added: 0)
        for pr in paragraphs.reversed() {
            let local = NSRange(location: pr.location - paraAll.location, length: pr.length)
            let delta = restyleListParagraph(target, in: replacement, paragraph: local, settings: settings)
            if pr.location == paragraphs[0].location { firstDelta = delta }
        }

        guard tv.shouldChangeText(in: paraAll, replacementString: replacement.string) else { return }
        storage.replaceCharacters(in: paraAll, with: replacement)
        tv.didChangeText()

        // Каретка: один абзац — зберегти позицію з поправкою на маркер;
        // кілька — в кінець вмісту заміни
        if paragraphs.count == 1 {
            let minLoc = paraAll.location + firstDelta.added
            let target = sel.location + firstDelta.added - firstDelta.removed
            var maxLoc = paraAll.location + replacement.length
            if replacement.string.hasSuffix("\n") { maxLoc -= 1 }
            tv.setSelectedRange(NSRange(location: max(minLoc, min(target, maxLoc)), length: 0))
        } else {
            var caret = paraAll.location + replacement.length
            if replacement.string.hasSuffix("\n") { caret -= 1 }
            tv.setSelectedRange(NSRange(location: caret, length: 0))
        }
        refreshTypingAttributes(tv)
        renumber(tv, settings: settings)
        tv.needsDisplay = true
    }

    /// Порожній абзац-хвіст: перший клік — вставити маркер, повторний той
    /// самий стиль — зняти (лише typingAttributes, маркера ще немає)
    private static func toggleMarkerAtCaret(_ style: ListStyle, tv: NSTextView, settings: NoteDocSettings) {
        guard let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()
        var attrs = tv.typingAttributes
        let role = role(from: attrs)

        if (attrs[.embarList] as? String) == style.rawValue {
            attrs[.embarList] = nil
            attrs[.paragraphStyle] = NoteTypography.paragraphStyle(role: role, settings: settings)
            tv.typingAttributes = attrs
            return
        }
        let marker = NSAttributedString(string: markerText(style, index: 1),
                                        attributes: markerAttrs(role, style, settings: settings))
        guard tv.shouldChangeText(in: sel, replacementString: marker.string) else { return }
        storage.replaceCharacters(in: sel, with: marker)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: sel.location + marker.length, length: 0))
        tv.typingAttributes = markerAttrs(role, style, settings: settings)
        renumber(tv, settings: settings)
    }

    /// Зняти/накласти маркер і атрибути списку на абзац у буфері заміни.
    /// Повертає (видалено, додано) символів на початку абзацу — для каретки.
    @discardableResult
    private static func restyleListParagraph(_ target: ListStyle?, in buf: NSMutableAttributedString,
                                             paragraph: NSRange, settings: NoteDocSettings) -> (removed: Int, added: Int) {
        let s = buf.string as NSString
        var pr = paragraph
        var removed = 0, added = 0

        // ❗ Абзац фото — недоторканний: без цього guard'а тогл списку через
        // виділення з фото повертав текстовий стиль (1.75-множник) і фото
        // знову «провалювалось» вниз рядка (code review #2)
        if pr.length > 0, pr.location < buf.length,
           NoteFormatter.isPhotoParagraph(buf.attributes(at: pr.location, effectiveRange: nil)) {
            return (0, 0)
        }

        var contentLen = pr.length
        if contentLen > 0, s.character(at: pr.location + contentLen - 1) == 0x0A { contentLen -= 1 }

        let a0: [NSAttributedString.Key: Any] = pr.length > 0 && pr.location < buf.length
            ? buf.attributes(at: pr.location, effectiveRange: nil) : [:]
        let hadList = a0[.embarList] != nil
        let hadQuote = NoteFormatter.flag(a0, .embarQuote)
        let role = (a0[.embarRole] as? String).flatMap(ParagraphRole.init) ?? .p
        // Вирівнювання абзацу переживає тогл (раніше тогл скидав центр/право)
        let align = (a0[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural

        // 1. Прибрати старий маркер (до першого \t у вмісті)
        if hadList, contentLen > 0 {
            let tab = s.range(of: "\t", options: [], range: NSRange(location: pr.location, length: contentLen))
            if tab.location != NSNotFound {
                removed = tab.location + tab.length - pr.location
                buf.deleteCharacters(in: NSRange(location: pr.location, length: removed))
                pr.length -= removed
            }
        }
        // 2. Вставити новий маркер
        if let target {
            let marker = NSAttributedString(string: markerText(target, index: 1),
                                            attributes: markerAttrs(role, target, settings: settings))
            buf.insert(marker, at: pr.location)
            added = marker.length
            pr.length += added
        }
        // 3. Атрибути всього абзацу (включно з \n)
        if pr.length > 0 {
            if let target {
                buf.addAttribute(.embarList, value: target.rawValue as NSString, range: pr)
                // Список і цитата взаємовиключні (дзеркально до toggleQuote,
                // який знімає список): гібрид лишав .embarQuote без відступу —
                // риска малювалась поверх маркера
                if hadQuote { buf.removeAttribute(.embarQuote, range: pr) }
            } else {
                buf.removeAttribute(.embarList, range: pr)
            }
            buf.addAttribute(.paragraphStyle,
                             value: NoteTypography.paragraphStyle(role: role, list: target,
                                                                  alignment: align, settings: settings),
                             range: pr)
            if hadQuote, target != nil {
                NoteFormatter.restyleCosmetics(buf, in: pr, settings: settings)
            }
        }
        return (removed, added)
    }

    // MARK: - Enter у списку

    /// true, якщо Enter оброблено (список): продовжити пункт або вийти
    static func handleListReturn(_ tv: NSTextView, settings: NoteDocSettings) -> Bool {
        guard let storage = tv.textStorage, storage.length > 0 else { return false }
        let sel = tv.selectedRange()
        let s = storage.string as NSString
        let pr = s.paragraphRange(for: sel)
        guard pr.length > 0, pr.location < storage.length,
              let raw = storage.attribute(.embarList, at: pr.location, effectiveRange: nil) as? String,
              let style = ListStyle(rawValue: raw) else { return false }

        let tab = s.range(of: "\t", options: [], range: pr)
        let role = (storage.attribute(.embarRole, at: pr.location, effectiveRange: nil) as? String)
            .flatMap(ParagraphRole.init) ?? .p

        // Фантомний .embarList без маркера в тексті (злиття рядків, ⌘⌫,
        // фрагмент, вирізаний зсередини пункту): зачистити атрибут і віддати
        // Enter звичайному шляху — інакше «список» продовжувався б без гліфів
        guard tab.location != NSNotFound else {
            if tv.shouldChangeText(in: pr, replacementString: nil) {
                storage.removeAttribute(.embarList, range: pr)
                storage.addAttribute(.paragraphStyle,
                                     value: NoteTypography.paragraphStyle(role: role, settings: settings),
                                     range: pr)
                tv.didChangeText()
            }
            var t = tv.typingAttributes
            t[.embarList] = nil
            t[.paragraphStyle] = NoteTypography.paragraphStyle(role: role, settings: settings)
            tv.typingAttributes = t
            return false
        }

        let contentStart = tab.location + tab.length
        let hasNewline = s.character(at: pr.location + pr.length - 1) == 0x0A
        let contentLen = pr.location + pr.length - contentStart - (hasNewline ? 1 : 0)

        if contentLen <= 0 {
            // Порожній пункт → прибрати маркер і вийти зі списку
            exitList(tv, paragraph: pr, settings: settings)
            return true
        }

        // Продовжити список: новий рядок + маркер (номер виправить renumber)
        let insert = NSAttributedString(string: "\n" + markerText(style, index: 1),
                                        attributes: markerAttrs(role, style, settings: settings))
        guard tv.shouldChangeText(in: sel, replacementString: insert.string) else { return true }
        storage.replaceCharacters(in: sel, with: insert)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: sel.location + insert.length, length: 0))
        tv.typingAttributes = markerAttrs(role, style, settings: settings)
        renumber(tv, settings: settings)
        return true
    }

    // MARK: - Вихід зі списку (спільне тіло Enter-на-порожньому і Backspace)

    /// Зняти маркер і атрибути списку з ОДНОГО абзацу, каретка — на початок
    /// його тексту. Усі кроки — в одній події: текстова пара (маркер) +
    /// атрибутна пара (зачистка) + renumber → один ⌘Z
    static func exitList(_ tv: NSTextView, paragraph pr: NSRange, settings: NoteDocSettings) {
        guard let storage = tv.textStorage, pr.length > 0, pr.location < storage.length else { return }
        let a0 = storage.attributes(at: pr.location, effectiveRange: nil)
        let role = (a0[.embarRole] as? String).flatMap(ParagraphRole.init) ?? .p
        let align = (a0[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural
        let plainStyle = NoteTypography.paragraphStyle(role: role, alignment: align, settings: settings)

        if let zone = markerZone(in: storage, paragraph: pr) {
            guard tv.shouldChangeText(in: zone, replacementString: "") else { return }
            storage.deleteCharacters(in: zone)
            tv.didChangeText()
        }
        let newPr = (storage.string as NSString).paragraphRange(for: NSRange(location: pr.location, length: 0))
        if newPr.length > 0, tv.shouldChangeText(in: newPr, replacementString: nil) {
            storage.removeAttribute(.embarList, range: newPr)
            storage.addAttribute(.paragraphStyle, value: plainStyle, range: newPr)
            tv.didChangeText()
        }
        tv.setSelectedRange(NSRange(location: pr.location, length: 0))
        // Явно скинути typing-атрибути: інакше набір продовжував би
        // «списковий» відступ (ревізія 2026-07-05)
        var t = tv.typingAttributes
        t[.embarList] = nil
        t[.paragraphStyle] = plainStyle
        tv.typingAttributes = t
        renumber(tv, settings: settings)
    }

    // MARK: - Backspace у списку

    /// true, якщо Backspace оброблено: гола каретка на початку тексту пункту →
    /// перший Backspace знімає маркер і виводить зі списку, текст лишається;
    /// другий (уже звичайний шлях) зливає з попереднім рядком (рішення Mia
    /// 05.09, дзеркально до правила цитати R2)
    static func handleListBackspace(_ tv: NSTextView, settings: NoteDocSettings) -> Bool {
        guard let storage = tv.textStorage, storage.length > 0 else { return false }
        let sel = tv.selectedRange()
        guard sel.length == 0 else { return false }
        let pr = (storage.string as NSString).paragraphRange(for: sel)
        guard let zone = markerZone(in: storage, paragraph: pr),
              sel.location == zone.location + zone.length else { return false }
        exitList(tv, paragraph: pr, settings: settings)
        return true
    }

    // MARK: - Перенумерація

    /// Перелічити суміжні блоки нумерованих пунктів (1., 2., …).
    /// Кожна правка реєструється в undo (реальний replacementString).
    static func renumber(_ tv: NSTextView, settings: NoteDocSettings) {
        guard let storage = tv.textStorage, storage.length > 0 else { return }
        let s = storage.string as NSString
        var edits: [(NSRange, String)] = []
        var counter = 0
        var prevNumbered = false
        var loc = 0
        while loc < s.length {
            let pr = s.paragraphRange(for: NSRange(location: loc, length: 0))
            loc = pr.location + max(pr.length, 1)
            let listType = pr.length > 0
                ? storage.attribute(.embarList, at: pr.location, effectiveRange: nil) as? String
                : nil
            if listType == ListStyle.number.rawValue {
                counter = prevNumbered ? counter + 1 : 1
                prevNumbered = true
                let tab = s.range(of: "\t", options: [], range: pr)
                guard tab.location != NSNotFound else { continue }
                let numRange = NSRange(location: pr.location, length: tab.location - pr.location)
                let desired = "\(counter)."
                if s.substring(with: numRange) != desired { edits.append((numRange, desired)) }
            } else {
                prevNumbered = false
            }
        }
        guard !edits.isEmpty else { return }
        for (range, text) in edits.reversed() {
            guard tv.shouldChangeText(in: range, replacementString: text) else { continue }
            let attrs = storage.attributes(at: range.location, effectiveRange: nil)
            storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attrs))
            tv.didChangeText()
        }
    }
}
