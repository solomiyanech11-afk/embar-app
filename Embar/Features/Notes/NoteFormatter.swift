//
//  NoteFormatter.swift
//  Embar
//
//  Мутації rich-тіла (SPEC §3.2). Працює прямо над NSTextStorage text view:
//  для виділення — над діапазоном (з undo-групуванням), для згорнутого
//  курсора — над typingAttributes. Ролі/списки/цитата/хайлайт/жирний/курсив —
//  кастомні `.embar*`-маркери (джерело правди); шрифт і косметика виводяться.
//

import AppKit

enum NoteFormatter {

    // MARK: - Читання стану (для тулбара)

    /// Інлайн-властивості (bold/italic/хайлайт/колір) — з typingAttributes або
    /// початку виділення. Абзацні (роль/список/цитата/вирівнювання) — з
    /// ПОЧАТКУ абзацу: typingAttributes на старті абзацу віддзеркалюють
    /// попередній абзац, і тогл застосовував би те саме вдруге (фідбек)
    static func state(of tv: NSTextView, settings: NoteDocSettings) -> NoteSelectionState {
        guard let storage = tv.textStorage else { return NoteSelectionState() }
        let sel = tv.selectedRange()
        var st = NoteSelectionState()

        let inline: [NSAttributedString.Key: Any]
        if sel.length == 0 || storage.length == 0 {
            inline = tv.typingAttributes
        } else {
            inline = storage.attributes(at: min(sel.location, storage.length - 1), effectiveRange: nil)
        }
        st.bold = flag(inline, .embarBold)
        st.italic = flag(inline, .embarItalic)
        st.highlight = (inline[.embarHighlight] as? String).flatMap(HighlightColor.init)
        st.textColor = (inline[.embarTextColor] as? String).flatMap(BodyTextColor.init)

        var para = inline
        if storage.length > 0 {
            let pr = (storage.string as NSString).paragraphRange(for: sel)
            if pr.length > 0, pr.location < storage.length {
                para = storage.attributes(at: pr.location, effectiveRange: nil)
            }
        }
        st.role = role(from: para)
        st.quote = flag(para, .embarQuote)
        st.list = (para[.embarList] as? String).flatMap(ListStyle.init)
        if let ps = para[.paragraphStyle] as? NSParagraphStyle { st.alignment = ps.alignment }
        return st
    }

    static func role(from attrs: [NSAttributedString.Key: Any]) -> ParagraphRole {
        (attrs[.embarRole] as? String).flatMap(ParagraphRole.init) ?? .p
    }

    /// Єдина перевірка «це абзац фото» — такі абзаци мають власний стиль
    /// (без lineHeightMultiple) і НЕ беруть участі в жодному ре-стайлі.
    /// ❗ Кожен новий прохід по абзацах МУСИТЬ використовувати цей guard:
    /// пропуск у NoteListEngine повертав фото 1.75-множник (review #2)
    static func isPhotoParagraph(_ attrs: [NSAttributedString.Key: Any]) -> Bool {
        attrs[.attachment] is EmbarPhotoRowAttachment
    }

    /// «Це абзац блоку цитати з Рідера» (тіло чи підпис) — блок атомарний,
    /// має власну типографіку (25.5pt, Inter 10.5 капс) і не рестайлиться
    static func isReaderQuoteParagraph(_ attrs: [NSAttributedString.Key: Any]) -> Bool {
        attrs[.embarReaderQuote] != nil || attrs[.embarReaderSource] != nil
    }
    static func flag(_ attrs: [NSAttributedString.Key: Any], _ k: NSAttributedString.Key) -> Bool {
        (attrs[k] as? NSNumber)?.boolValue ?? false
    }

    /// Шрифт із маркерів рана: роль + bold + italic; цитата — завжди
    /// Fraunces italic 15 (редизайн 2026-07-05); чіп-згадка — ×0.92
    static func font(from attrs: [NSAttributedString.Key: Any], settings: NoteDocSettings) -> NSFont {
        if flag(attrs, .embarQuote) { return NoteTypography.quoteFont() }
        var f = NoteTypography.font(role: role(from: attrs),
                                    bold: flag(attrs, .embarBold),
                                    italic: flag(attrs, .embarItalic),
                                    settings: settings)
        if attrs[.embarMention] is String {
            f = NSFont(descriptor: f.fontDescriptor,
                       size: (f.pointSize * NoteTypography.mentionFontScale).rounded()) ?? f
        }
        return f
    }

    /// Пере-вивести косметику (шрифт + колір) з маркерів для кожного рана:
    /// колір тексту > колір цитати > ink. Приймає NSMutableAttributedString,
    /// а не NSTextStorage: тим самим шляхом рестайлиться і фрагмент вставки
    /// поза text view (P2.19)
    static func restyleCosmetics(_ storage: NSMutableAttributedString, in range: NSRange, settings: NoteDocSettings) {
        storage.enumerateAttributes(in: range) { attrs, r, _ in
            storage.addAttribute(.font, value: font(from: attrs, settings: settings), range: r)
            let color: NSColor
            if let slug = attrs[.embarTextColor] as? String, let c = BodyTextColor(rawValue: slug) {
                color = c.nsColor
            } else if attrs[.embarMention] is String {
                color = NoteTypography.mentionTextColor
            } else if flag(attrs, .embarQuote) {
                color = NoteTypography.quoteTextColor
            } else if flag(attrs, .embarQuoteAuthor) {
                color = NoteTypography.quoteAuthorColor
            } else {
                color = NoteTypography.inkColor
            }
            storage.addAttribute(.foregroundColor, value: color, range: r)
        }
    }

    /// Освіжити typingAttributes після мутації атрибутів під нерухомим
    /// курсором: NSTextView сам їх НЕ перечитує, і набір продовжував би
    /// старе оформлення
    static func refreshTypingAttributes(_ tv: NSTextView) {
        guard let storage = tv.textStorage, storage.length > 0 else { return }
        let sel = tv.selectedRange()
        guard sel.length == 0 else { return }
        let pr = (storage.string as NSString).paragraphRange(for: sel)
        guard pr.length > 0 else { return }
        // Символ перед кареткою В МЕЖАХ цього абзацу (на старті — перший його символ)
        let idx = max(pr.location, min(sel.location - 1, pr.location + pr.length - 1))
        var attrs = storage.attributes(at: min(idx, storage.length - 1), effectiveRange: nil)
        // ❗ Ніколи не «мінтити» typing-атрибути з маркером чіпа: каретка
        // впритул до чіпа (NBSP видалено) → набір продовжував би чіп (review #4)
        attrs[.embarMention] = nil
        // Фантомний .embarList без маркера-гліфа в абзаці (злиття рядків,
        // фрагмент, вирізаний зсередини пункту) — не успадковувати: набір
        // тягнув би «списковий» відступ без маркера (R1)
        if attrs[.embarList] != nil,
           markerZone(in: storage, paragraph: pr) == nil {
            attrs[.embarList] = nil
            let settings = (tv as? EmbarTextView)?.docSettings ?? .default
            let align = (attrs[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural
            attrs[.paragraphStyle] = NoteTypography.paragraphStyle(
                role: role(from: attrs), quote: flag(attrs, .embarQuote),
                alignment: align, settings: settings)
        }
        tv.typingAttributes = attrs
    }

    // MARK: - Bold / Italic (маркери + перерахунок шрифту)

    static func toggleBold(_ tv: NSTextView, settings: NoteDocSettings) {
        setTraitMarker(tv, key: .embarBold, on: !state(of: tv, settings: settings).bold, settings: settings)
    }
    static func toggleItalic(_ tv: NSTextView, settings: NoteDocSettings) {
        setTraitMarker(tv, key: .embarItalic, on: !state(of: tv, settings: settings).italic, settings: settings)
    }

    private static func setTraitMarker(_ tv: NSTextView, key: NSAttributedString.Key,
                                       on: Bool, settings: NoteDocSettings) {
        let sel = tv.selectedRange()
        if sel.length == 0 {
            var attrs = tv.typingAttributes
            if on { attrs[key] = NSNumber(value: true) } else { attrs[key] = nil }
            attrs[.font] = font(from: attrs, settings: settings)
            tv.typingAttributes = attrs
            return
        }
        mutate(tv, range: sel) { storage in
            if on { storage.addAttribute(key, value: NSNumber(value: true), range: sel) }
            else { storage.removeAttribute(key, range: sel) }
            storage.enumerateAttributes(in: sel) { attrs, r, _ in
                storage.addAttribute(.font, value: font(from: attrs, settings: settings), range: r)
            }
        }
    }

    // MARK: - Роль абзацу / вирівнювання / цитата (абзацні)

    static func setRole(_ role: ParagraphRole, in tv: NSTextView, settings: NoteDocSettings) {
        restyleParagraphs(tv, settings: settings) { spec in
            var s = spec; s.role = role; return s
        }
    }
    static func setAlignment(_ align: NSTextAlignment, in tv: NSTextView, settings: NoteDocSettings) {
        restyleParagraphs(tv, settings: settings) { spec in
            var s = spec; s.alignment = align; return s
        }
    }
    static func toggleQuote(_ tv: NSTextView, settings: NoteDocSettings) {
        let makeQuote = !state(of: tv, settings: settings).quote
        restyleParagraphs(tv, settings: settings) { spec in
            var s = spec; s.quote = makeQuote; if makeQuote { s.list = nil }; return s
        }
    }

    /// Специфікація абзацного оформлення (для одного абзацу)
    struct ParaSpec { var role: ParagraphRole; var list: ListStyle?; var quote: Bool; var alignment: NSTextAlignment }

    private static func restyleParagraphs(_ tv: NSTextView, settings: NoteDocSettings,
                                          transform: @escaping (ParaSpec) -> ParaSpec) {
        guard let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()
        let nsstring = storage.string as NSString
        let para = storage.length == 0 ? NSRange(location: 0, length: 0) : nsstring.paragraphRange(for: sel)

        // Порожній док АБО порожній хвостовий абзац → лише typingAttributes
        // (ітерація абзаців тут не дає нічого — тогл був би no-op)
        if para.length == 0 {
            var attrs = tv.typingAttributes
            let old = ParaSpec(role: role(from: attrs),
                               list: (attrs[.embarList] as? String).flatMap(ListStyle.init),
                               quote: flag(attrs, .embarQuote),
                               alignment: (attrs[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural)
            applyParaSpec(transform(old), to: &attrs, settings: settings)
            tv.typingAttributes = attrs
            return
        }

        mutate(tv, range: para) { storage in
            // Ручна ітерація paragraphRange-ами: enumerateSubstrings пропускає
            // ПОРОЖНІ абзаци — порожній рядок усередині виділення лишався б
            // неотогленим і рвав цитату/вирівнювання
            var cursor = para.location
            let end = para.location + para.length
            while cursor < end {
                let pr = nsstring.paragraphRange(for: NSRange(location: cursor, length: 0))
                cursor = pr.location + max(pr.length, 1)
                guard pr.length > 0 else { continue }

                let a0 = storage.attributes(at: pr.location, effectiveRange: nil)
                // Абзац фото має власний стиль (без множника) — не чіпаємо
                if isPhotoParagraph(a0) { continue }
                // Блок цитати з Рідера атомарний і не редагується —
                // тулбар його не рестайлить (code review M5 #2)
                if isReaderQuoteParagraph(a0) { continue }
                let old = ParaSpec(role: role(from: a0),
                                   list: (a0[.embarList] as? String).flatMap(ListStyle.init),
                                   quote: flag(a0, .embarQuote),
                                   alignment: (a0[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural)
                let spec = transform(old)
                storage.addAttribute(.embarRole, value: spec.role.rawValue as NSString, range: pr)
                storage.addAttribute(.paragraphStyle, value: NoteTypography.paragraphStyle(
                    role: spec.role, list: spec.list, quote: spec.quote, alignment: spec.alignment, settings: settings), range: pr)
                if spec.quote { storage.addAttribute(.embarQuote, value: NSNumber(value: true), range: pr) }
                else { storage.removeAttribute(.embarQuote, range: pr) }
                if let l = spec.list { storage.addAttribute(.embarList, value: l.rawValue as NSString, range: pr) }
                else { storage.removeAttribute(.embarList, range: pr) }
                restyleCosmetics(storage, in: pr, settings: settings)
            }
        }
        refreshTypingAttributes(tv)
        tv.needsDisplay = true
    }

    private static func applyParaSpec(_ spec: ParaSpec, to attrs: inout [NSAttributedString.Key: Any],
                                      settings: NoteDocSettings) {
        attrs[.embarRole] = spec.role.rawValue as NSString
        attrs[.paragraphStyle] = NoteTypography.paragraphStyle(
            role: spec.role, list: spec.list, quote: spec.quote, alignment: spec.alignment, settings: settings)
        attrs[.embarQuote] = spec.quote ? NSNumber(value: true) : nil
        attrs[.embarList] = spec.list.map { $0.rawValue as NSString }
        attrs[.font] = font(from: attrs, settings: settings)
        if attrs[.embarTextColor] == nil {
            attrs[.foregroundColor] = spec.quote ? NoteTypography.quoteTextColor
                                                 : NoteTypography.inkColor
        }
    }

    // MARK: - Enter розчиняє спец-оформлення (SPEC §3.2 + фідбек 2026-07-05)

    /// Звичайні plain-атрибути абзацу P (для «повернення до звичайного»)
    static func plainTypingAttributes(settings: NoteDocSettings) -> [NSAttributedString.Key: Any] {
        [
            .embarRole: ParagraphRole.p.rawValue as NSString,
            .font: NoteTypography.font(role: .p, settings: settings),
            .foregroundColor: NoteTypography.inkColor,
            .paragraphStyle: NoteTypography.paragraphStyle(role: .p, settings: settings),
        ]
    }

    /// Правило Enter для спец-оформлення (Shift+Enter обробляється раніше —
    /// лишає в блоці). true = Enter оброблено:
    /// · порожній рядок із цитатою/заголовком/не-лівим вирівнюванням →
    ///   розчинити оформлення НА МІСЦІ (без нового рядка);
    /// · Enter у цитаті або заголовку H1/H2 (будь-де) → вийти у звичайний P;
    ///   хвіст абзацу після каретки теж стає звичайним.
    /// Вирівнювання після тексту НЕ скидається (можна писати кілька
    /// відцентрованих рядків) — лише через порожній рядок.
    static func handleSpecialReturn(_ tv: NSTextView, settings: NoteDocSettings) -> Bool {
        guard let storage = tv.textStorage else { return false }
        let sel = tv.selectedRange()
        guard sel.length == 0 else { return false }

        let s = storage.string as NSString
        let pr = storage.length == 0 ? NSRange(location: 0, length: 0) : s.paragraphRange(for: sel)
        let attrs = (pr.length > 0 && pr.location < storage.length)
            ? storage.attributes(at: pr.location, effectiveRange: nil)
            : tv.typingAttributes

        let role = role(from: attrs)
        let quote = flag(attrs, .embarQuote)
        let align = (attrs[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural
        let aligned = align != .natural && align != .left
        let heading = role == .h1 || role == .h2

        var contentEnd = pr.location + pr.length
        if pr.length > 0, s.character(at: contentEnd - 1) == 0x0A { contentEnd -= 1 }
        let isEmpty = contentEnd <= pr.location

        let plain = plainTypingAttributes(settings: settings)

        if isEmpty {
            // Порожній рядок зі спец-оформленням → розчинити на місці
            guard quote || heading || aligned else { return false }
            if pr.length > 0 {
                guard tv.shouldChangeText(in: pr, replacementString: nil) else { return true }
                storage.beginEditing()
                storage.addAttribute(.embarRole, value: ParagraphRole.p.rawValue as NSString, range: pr)
                storage.addAttribute(.paragraphStyle,
                                     value: NoteTypography.paragraphStyle(role: .p, settings: settings), range: pr)
                storage.removeAttribute(.embarQuote, range: pr)
                restyleCosmetics(storage, in: pr, settings: settings)
                storage.endEditing()
                tv.didChangeText()
            }
            tv.typingAttributes = plain
            tv.needsDisplay = true
            return true
        }

        // Enter будь-де в цитаті/заголовку → розрив у звичайний абзац
        guard quote || heading else { return false }
        guard tv.shouldChangeText(in: sel, replacementString: "\n") else { return true }
        storage.replaceCharacters(in: sel, with: NSAttributedString(string: "\n", attributes: plain))
        tv.didChangeText()
        let caret = sel.location + 1
        // Хвіст абзацу після розриву (якщо був текст праворуч від каретки) —
        // теж звичайний P
        let s2 = storage.string as NSString
        let restPr = s2.paragraphRange(for: NSRange(location: caret, length: 0))
        if restPr.length > 0, tv.shouldChangeText(in: restPr, replacementString: nil) {
            storage.beginEditing()
            storage.addAttribute(.embarRole, value: ParagraphRole.p.rawValue as NSString, range: restPr)
            storage.addAttribute(.paragraphStyle,
                                 value: NoteTypography.paragraphStyle(role: .p, settings: settings), range: restPr)
            storage.removeAttribute(.embarQuote, range: restPr)
            restyleCosmetics(storage, in: restPr, settings: settings)
            storage.endEditing()
            tv.didChangeText()
        }
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        tv.typingAttributes = plain
        return true
    }

    // MARK: - Backspace у цитаті (R2): перший — зняти формат, не зливати

    /// true, якщо Backspace оброблено: гола каретка на початку абзацу цитати →
    /// зняти форматування цитати, текст лишається звичайним; другий Backspace
    /// зливає звичайним шляхом. Без цього злиття тягло ран .embarQuote у
    /// чужий абзац, і риска малювалась поверх тексту вище (знахідка Mia)
    static func handleQuoteBackspace(_ tv: NSTextView, settings: NoteDocSettings) -> Bool {
        guard let storage = tv.textStorage, storage.length > 0 else { return false }
        let sel = tv.selectedRange()
        guard sel.length == 0 else { return false }
        let pr = (storage.string as NSString).paragraphRange(for: sel)
        guard sel.location == pr.location, pr.length > 0, pr.location < storage.length else { return false }
        let a0 = storage.attributes(at: pr.location, effectiveRange: nil)
        guard flag(a0, .embarQuote), !isReaderQuoteParagraph(a0) else { return false }
        unquoteParagraph(tv, paragraph: pr, settings: settings)
        return true
    }

    /// Зняти цитату з одного абзацу: одна атрибутна пара = один ⌘Z
    static func unquoteParagraph(_ tv: NSTextView, paragraph pr: NSRange, settings: NoteDocSettings) {
        guard let storage = tv.textStorage,
              tv.shouldChangeText(in: pr, replacementString: nil) else { return }
        let a0 = storage.attributes(at: pr.location, effectiveRange: nil)
        let role = role(from: a0)
        let align = (a0[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural
        storage.beginEditing()
        storage.removeAttribute(.embarQuote, range: pr)
        storage.addAttribute(.paragraphStyle,
                             value: NoteTypography.paragraphStyle(role: role, alignment: align,
                                                                  settings: settings),
                             range: pr)
        restyleCosmetics(storage, in: pr, settings: settings)
        storage.endEditing()
        tv.didChangeText()
        refreshTypingAttributes(tv)
        tv.needsDisplay = true
    }

    // MARK: - Лікування злиття абзаців (R2/R1): формат голови перемагає

    /// Що накласти на злитий абзац після delete-операції, яка зʼїла \n.
    /// Обчислюється ДО super (голова ще жива), застосовується ПІСЛЯ —
    /// окремою атрибутною парою в тій самій події → один ⌘Z із видаленням.
    /// ❗ Не з делегата shouldChangeTextIn: вкладені правки там ламали
    /// облік undo (блокер 2026-08-25)
    struct MergeHealPlan {
        let headStart: Int
        let quote: Bool
        let list: ListStyle?
        let role: ParagraphRole
        let alignment: NSTextAlignment
        let renumber: Bool
    }

    /// nil — видалення не зливає абзаців або спец-формати не зачеплені
    static func mergeHealPlan(in tv: NSTextView, deleting range: NSRange) -> MergeHealPlan? {
        guard let storage = tv.textStorage, range.length > 0,
              NSMaxRange(range) <= storage.length else { return nil }
        let s = storage.string as NSString
        guard s.range(of: "\n", options: [], range: range).location != NSNotFound else { return nil }
        let head = s.paragraphRange(for: NSRange(location: range.location, length: 0))
        guard head.length > 0, head.location < storage.length else { return nil }
        let a0 = storage.attributes(at: head.location, effectiveRange: nil)
        guard !isPhotoParagraph(a0), !isReaderQuoteParagraph(a0) else { return nil }

        let quote = flag(a0, .embarQuote)
        let list = (a0[.embarList] as? String).flatMap(ListStyle.init)
        // Спец-формати в самому діапазоні (хвіст пункту/цитати, що вливається
        // у звичайну голову, лишав би фантомні атрибути посеред абзацу)
        var specialInRange = false
        var numbersTouched = list == .number
        storage.enumerateAttribute(.embarList, in: range) { v, _, _ in
            guard let v = v as? String else { return }
            specialInRange = true
            if v == ListStyle.number.rawValue { numbersTouched = true }
        }
        if !specialInRange {
            storage.enumerateAttribute(.embarQuote, in: range) { v, _, stop in
                if (v as? NSNumber)?.boolValue == true { specialInRange = true; stop.pointee = true }
            }
        }
        guard quote || list != nil || specialInRange else { return nil }
        return MergeHealPlan(headStart: head.location, quote: quote, list: list,
                             role: role(from: a0),
                             alignment: (a0[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural,
                             renumber: numbersTouched)
    }

    static func applyMergeHeal(_ plan: MergeHealPlan?, to tv: NSTextView, settings: NoteDocSettings) {
        guard let plan, let storage = tv.textStorage else { return }
        let s = storage.string as NSString
        let pr = s.paragraphRange(for: NSRange(location: min(plan.headStart, storage.length), length: 0))
        if pr.length > 0, pr.location < storage.length {
            let cur = storage.attributes(at: pr.location, effectiveRange: nil)
            // Фото-ряд і блок Рідера недоторканні на кожному проході (guard-правило)
            guard !isPhotoParagraph(cur), !isReaderQuoteParagraph(cur) else { return }
            // Маркер голови зʼїло саме видалення → пункт стає звичайним
            var list = plan.list
            if list != nil, markerZone(in: storage, paragraph: pr) == nil { list = nil }
            if tv.shouldChangeText(in: pr, replacementString: nil) {
                storage.beginEditing()
                if plan.quote {
                    storage.addAttribute(.embarQuote, value: NSNumber(value: true), range: pr)
                    storage.removeAttribute(.embarList, range: pr)
                } else if let list {
                    storage.addAttribute(.embarList, value: list.rawValue as NSString, range: pr)
                    storage.removeAttribute(.embarQuote, range: pr)
                } else {
                    storage.removeAttribute(.embarList, range: pr)
                    storage.removeAttribute(.embarQuote, range: pr)
                }
                storage.addAttribute(.embarRole, value: plan.role.rawValue as NSString, range: pr)
                storage.addAttribute(.paragraphStyle, value: NoteTypography.paragraphStyle(
                    role: plan.role, list: list, quote: plan.quote,
                    alignment: plan.alignment, settings: settings), range: pr)
                restyleCosmetics(storage, in: pr, settings: settings)
                storage.endEditing()
                tv.didChangeText()
            }
            refreshTypingAttributes(tv)
        }
        if plan.renumber { renumber(tv, settings: settings) }
        tv.needsDisplay = true
    }

    // MARK: - Вставка всередину цитати (R2): фрагмент набуває її стилю

    /// Абзац під точкою вставки — цитата? (порожній хвіст — за typing-атрибутами)
    static func insertionTargetIsQuote(_ tv: NSTextView) -> Bool {
        guard let storage = tv.textStorage, storage.length > 0 else {
            return flag(tv.typingAttributes, .embarQuote)
        }
        let sel = tv.selectedRange()
        let pr = (storage.string as NSString)
            .paragraphRange(for: NSRange(location: min(sel.location, storage.length), length: 0))
        guard pr.length > 0, pr.location < storage.length else {
            return flag(tv.typingAttributes, .embarQuote)
        }
        let a0 = storage.attributes(at: pr.location, effectiveRange: nil)
        return flag(a0, .embarQuote) && !isReaderQuoteParagraph(a0)
    }

    /// Увесь фрагмент стає цитатою (рішення Mia 05.09: «будь-який текст,
    /// вставлений усередину цитати, набуває її стилю» — всі абзаци).
    /// Винятки — фото-ряди і блоки Рідера, вони лишаються собою; маркери
    /// списків знімаються (список і цитата взаємовиключні). Чиста функція
    /// над буфером ДО вставки: сама вставка далі йде однією текстовою
    /// парою, тож ⌘Z атомарний без додаткових зусиль
    static func adoptQuoteStyle(_ fragment: NSMutableAttributedString, settings: NoteDocSettings) {
        var loc = 0
        while loc < fragment.length {
            var pr = (fragment.string as NSString).paragraphRange(for: NSRange(location: loc, length: 0))
            guard pr.length > 0 else { loc = pr.location + 1; continue }
            let a0 = fragment.attributes(at: pr.location, effectiveRange: nil)
            if isPhotoParagraph(a0) || isReaderQuoteParagraph(a0) {
                loc = pr.location + pr.length
                continue
            }
            // Зняти маркер-гліф списку («•⇥»), якщо є
            if a0[.embarList] != nil {
                let s = fragment.string as NSString
                var contentLen = pr.length
                if s.character(at: pr.location + contentLen - 1) == 0x0A { contentLen -= 1 }
                if contentLen > 0 {
                    let tab = s.range(of: "\t", options: [],
                                      range: NSRange(location: pr.location, length: contentLen))
                    if tab.location != NSNotFound {
                        let marker = NSRange(location: pr.location,
                                             length: tab.location + tab.length - pr.location)
                        fragment.deleteCharacters(in: marker)
                        pr.length -= marker.length
                    }
                }
            }
            if pr.length > 0 {
                let role = role(from: a0)
                fragment.removeAttribute(.embarList, range: pr)
                fragment.addAttribute(.embarQuote, value: NSNumber(value: true), range: pr)
                fragment.addAttribute(.embarRole, value: role.rawValue as NSString, range: pr)
                fragment.addAttribute(.paragraphStyle, value: NoteTypography.paragraphStyle(
                    role: role, quote: true, settings: settings), range: pr)
                restyleCosmetics(fragment, in: pr, settings: settings)
            }
            loc = pr.location + max(pr.length, 1)
        }
    }

    // MARK: - Хайлайт (маркер; малюється кастомно в EmbarTextView)

    static func toggleHighlight(_ color: HighlightColor, in tv: NSTextView) {
        let remove = state(of: tv, settings: .default).highlight == color
        applyInline(tv, set: remove ? [:] : [.embarHighlight: color.rawValue as NSString],
                    clear: remove ? [.embarHighlight] : [])
        tv.needsDisplay = true
    }

    // MARK: - Колір тексту (7 + зняти)

    static func setTextColor(_ color: BodyTextColor?, in tv: NSTextView) {
        if let color, color != .ink {
            applyInline(tv, set: [.embarTextColor: color.rawValue as NSString, .foregroundColor: color.nsColor], clear: [])
        } else {
            applyInline(tv, set: [.foregroundColor: NoteTypography.inkColor], clear: [.embarTextColor])
        }
    }

    private static func applyInline(_ tv: NSTextView, set: [NSAttributedString.Key: Any],
                                    clear: [NSAttributedString.Key]) {
        let sel = tv.selectedRange()
        if sel.length == 0 {
            var attrs = tv.typingAttributes
            for k in clear { attrs[k] = nil }
            for (k, v) in set { attrs[k] = v }
            tv.typingAttributes = attrs
            return
        }
        mutate(tv, range: sel) { storage in
            for k in clear { storage.removeAttribute(k, range: sel) }
            for (k, v) in set { storage.addAttribute(k, value: v, range: sel) }
        }
    }

    // MARK: - Повний ре-стайл документа (зміна налаштувань нотатки, SPEC §3.3)

    /// Перерахувати стилі УСІХ абзаців під нові налаштування (розмір/шрифт/
    /// інтервал): ролі/списки/цитати збережені як маркери, тож це чистий
    /// перерахунок косметики — документ не ламається
    static func restyleDocument(_ tv: NSTextView, settings: NoteDocSettings) {
        guard let storage = tv.textStorage, storage.length > 0 else { return }
        let full = NSRange(location: 0, length: storage.length)
        guard tv.shouldChangeText(in: full, replacementString: nil) else { return }
        storage.beginEditing()
        restyleAllParagraphs(storage, settings: settings)
        storage.endEditing()
        tv.didChangeText()
        refreshTypingAttributes(tv)
        tv.needsDisplay = true
    }

    /// Спільне тіло рестайлу під налаштування: абзацні стилі + косметика з
    /// маркерів. Ним живе і restyleDocument (зміна налаштувань нотатки), і
    /// рестайл внутрішнього фрагмента вставки під ЦІЛЬОВУ нотатку (P2.19)
    static func restyleAllParagraphs(_ storage: NSMutableAttributedString,
                                     settings: NoteDocSettings) {
        let s = storage.string as NSString
        var loc = 0
        while loc < s.length {
            let pr = s.paragraphRange(for: NSRange(location: loc, length: 0))
            loc = pr.location + max(pr.length, 1)
            guard pr.length > 0 else { continue }
            let a0 = storage.attributes(at: pr.location, effectiveRange: nil)
            // Абзац фото має власний стиль (без множника) — не чіпаємо
            if isPhotoParagraph(a0) { continue }
            // Блок цитати з Рідера — власна типографіка, не чіпаємо
            if isReaderQuoteParagraph(a0) { continue }
            let align = (a0[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural
            storage.addAttribute(.paragraphStyle, value: NoteTypography.paragraphStyle(
                role: role(from: a0),
                list: (a0[.embarList] as? String).flatMap(ListStyle.init),
                quote: flag(a0, .embarQuote),
                alignment: align, settings: settings), range: pr)
            restyleCosmetics(storage, in: pr, settings: settings)
        }
    }

    // MARK: - Загальний мутатор з undo-групуванням (ЛИШЕ зміни атрибутів)

    private static func mutate(_ tv: NSTextView, range: NSRange, _ body: (NSTextStorage) -> Void) {
        guard let storage = tv.textStorage,
              tv.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        body(storage)
        storage.endEditing()
        tv.didChangeText()
    }
}
