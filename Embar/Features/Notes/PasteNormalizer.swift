//
//  PasteNormalizer.swift
//  Embar
//
//  Нормалізація вставки (SPEC §15.24, roadmap #4). Будь-який зовнішній rich-
//  текст (Safari, Word, VS Code…) приводиться до НАШОЇ схеми: ролі абзаців за
//  відносним кеглем, bold/italic, списки, цитати за відступом, лінки. Чужі
//  кольори/фони/таблиці/картинки — викидаються. Внутрішній copy/paste Embar —
//  власний pasteboard-тип, минає нормалізацію (без втрат, зі згадками).
//
//  normalize(_:settings:) — ЧИСТА функція, покрита тестами
//  (EmbarTests/PasteNormalizerTests).
//

import AppKit

enum PasteNormalizer {

    /// Внутрішній тип фрагмента Embar: архів NSAttributedString без втрат
    static let internalType = NSPasteboard.PasteboardType("com.nechai.embar.note-fragment")

    // MARK: - Читання пейстборда (нечиста оболонка)

    static func read(_ pb: NSPasteboard, settings: NoteDocSettings) -> NSAttributedString? {
        // 1. Наш фрагмент — без втрат (згадки/хайлайти/ролі/списки), але
        // косметика перевиводиться під налаштування ЦІЛЬОВОЇ нотатки
        // (P2.19): вставка з нотатки з іншим шрифтом/кеглем/міжряддям не
        // привозить чужого вигляду — маркери лишаються, вигляд цільовий
        if let data = pb.data(forType: internalType), let s = NoteArchiver.decode(data) {
            let out = NSMutableAttributedString(attributedString: s)
            NoteFormatter.restyleAllParagraphs(out, settings: settings)
            return out
        }
        // 2. Зовнішній rich: RTFD → RTF → HTML → плейн
        if let data = pb.data(forType: .rtfd),
           let s = NSAttributedString(rtfd: data, documentAttributes: nil) {
            return normalize(s, settings: settings)
        }
        if let data = pb.data(forType: .rtf),
           let s = NSAttributedString(rtf: data, documentAttributes: nil) {
            return normalize(s, settings: settings)
        }
        if let data = pb.data(forType: .html),
           let s = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.html],
               documentAttributes: nil) {
            return normalize(s, settings: settings)
        }
        if let str = pb.string(forType: .string) {
            return normalize(NSAttributedString(string: str), settings: settings)
        }
        return nil
    }

    // MARK: - Нормалізація (чиста)

    static func normalize(_ rawInput: NSAttributedString, settings: NoteDocSettings) -> NSAttributedString {
        let out = NSMutableAttributedString()
        guard rawInput.length > 0 else { return out }
        let input = sanitized(rawInput)
        let s = input.string as NSString
        // Базовий кегль вставки = модальний (найпоширеніший) розмір шрифту:
        // ролі класифікуються за СПІВВІДНОШЕННЯМ до нього — стійко до Word
        // (12pt тіло) і Safari (16px тіло) одночасно
        let baseline = modalFontSize(input)

        var loc = 0
        while loc < s.length {
            let pr = s.paragraphRange(for: NSRange(location: loc, length: 0))
            loc = pr.location + max(pr.length, 1)
            out.append(normalizedParagraph(input, range: pr, baseline: baseline, settings: settings))
        }
        return out
    }

    // MARK: - Абзац

    private static func normalizedParagraph(_ input: NSAttributedString, range pr: NSRange,
                                            baseline: CGFloat, settings: NoteDocSettings) -> NSAttributedString {
        let s = input.string as NSString
        var contentRange = pr
        var hasNewline = false
        if pr.length > 0, s.character(at: pr.location + pr.length - 1) == 0x0A {
            contentRange.length -= 1
            hasNewline = true
        }
        let startAttrs: [NSAttributedString.Key: Any] =
            (pr.length > 0 && pr.location < input.length)
            ? input.attributes(at: pr.location, effectiveRange: nil) : [:]
        let srcStyle = startAttrs[.paragraphStyle] as? NSParagraphStyle

        // Список: textLists імпортера АБО літеральний маркер у тексті
        var list: ListStyle? = nil
        if let lists = srcStyle?.textLists, !lists.isEmpty {
            let fmt = lists[0].markerFormat.rawValue
            list = (fmt.contains("decimal") || fmt.contains("arabic")) ? .number : .bullet
        }
        var markerStripLen = 0
        if contentRange.length > 0,
           let m = literalMarker(in: s.substring(with: contentRange)) {
            list = m.style
            markerStripLen = m.length
        }

        // Роль — за домінантним кеглем абзацу відносно базового
        var role: ParagraphRole = .p
        if let dom = dominantFontSize(input, in: contentRange), baseline > 0 {
            let ratio = dom / baseline
            if ratio >= 1.35 { role = .h1 }
            else if ratio >= 1.15 { role = .h2 }
            else if ratio <= 0.85 { role = .s }
        }

        // Цитата — відступ без списку (best effort для HTML blockquote)
        let quote = list == nil && (srcStyle?.headIndent ?? 0) > 20
        if quote || list != nil { role = .p }

        let alignment = srcStyle?.alignment ?? .natural
        let paraStyle = NoteTypography.paragraphStyle(role: role, list: list, quote: quote,
                                                      alignment: alignment, settings: settings)

        func baseAttrs(bold: Bool = false, italic: Bool = false) -> [NSAttributedString.Key: Any] {
            var a: [NSAttributedString.Key: Any] = [
                .embarRole: role.rawValue as NSString,
                .paragraphStyle: paraStyle,
            ]
            if quote {
                a[.embarQuote] = NSNumber(value: true)
                a[.font] = NoteTypography.quoteFont()
                a[.foregroundColor] = NoteTypography.quoteTextColor
            } else {
                a[.font] = NoteTypography.font(role: role, bold: bold, italic: italic, settings: settings)
                a[.foregroundColor] = NoteTypography.inkColor
                if bold { a[.embarBold] = NSNumber(value: true) }
                if italic { a[.embarItalic] = NSNumber(value: true) }
            }
            if let list { a[.embarList] = list.rawValue as NSString }
            return a
        }

        let out = NSMutableAttributedString()
        if let list {
            var ma = NoteFormatter.markerAttrs(role, list, settings: settings)
            ma[.paragraphStyle] = paraStyle
            out.append(NSAttributedString(string: NoteFormatter.markerText(list, index: 1), attributes: ma))
        }

        // Рани вмісту: лишаємо ЛИШЕ bold/italic (перерендерені нашим шрифтом)
        // і .link; кольори/фони/кернінг/таблиці/чужі .embar* — геть
        let runRange = NSRange(location: contentRange.location + markerStripLen,
                               length: max(contentRange.length - markerStripLen, 0))
        if runRange.length > 0 {
            input.enumerateAttributes(in: runRange) { attrs, r, _ in
                guard attrs[.attachment] == nil else { return } // картинки — v1 викидаємо
                let text = s.substring(with: r).replacingOccurrences(of: "\u{FFFC}", with: "")
                guard !text.isEmpty else { return }
                let f = attrs[.font] as? NSFont
                var a = baseAttrs(bold: isBoldish(f) || boolFlag(attrs, .embarBold),
                                  italic: isItalicish(f) || boolFlag(attrs, .embarItalic))
                if let link = attrs[.link] { a[.link] = link }
                out.append(NSAttributedString(string: text, attributes: a))
            }
        }
        if hasNewline {
            out.append(NSAttributedString(string: "\n", attributes: baseAttrs()))
        }
        return out
    }

    // MARK: - Прибирання перед розбором (2026-08-20)

    /// Чужі роздільники рядків і невидимий мотлох.
    ///
    /// Word ставить мʼякий перенос U+000B, презентації й Google Docs —
    /// U+2028; `paragraphRange` їх за межу абзацу НЕ вважає, і рядок
    /// приїжджав склеєним із сусіднім. Замінюємо на звичайний перенос
    /// (посимвольно, тож атрибути на місці), а нульової ширини символи й
    /// «дірки» від картинок вирізаємо
    static func sanitized(_ input: NSAttributedString) -> NSAttributedString {
        let breaks: Set<unichar> = [0x000B, 0x000C, 0x2028, 0x2029, 0x000D]
        // ❗ Зʼєднувачі НЕ чіпаємо (P2.32): U+200D (ZWJ) тримає складені
        // емоджі вкупі (👨‍👩‍👧 - це три емоджі через ZWJ), U+200C (ZWNJ) -
        // законний символ у перській/гінді. Викидався ZWJ - і вставлена
        // сімʼя розпадалась на трьох людей. Варіаційні селектори і
        // модифікатори тону шкіри в цьому списку не були й не мають бути
        let drop: Set<unichar> = [0x200B, 0xFEFF, 0xFFFC]
        let s = input.string as NSString
        var needsWork = false
        for i in 0..<s.length where breaks.contains(s.character(at: i))
            || drop.contains(s.character(at: i)) {
            needsWork = true
            break
        }
        guard needsWork else { return input }

        let out = NSMutableAttributedString(attributedString: input)
        // Ззаду наперед: видалення зсуває індекси
        for i in stride(from: out.length - 1, through: 0, by: -1) {
            let ch = (out.string as NSString).character(at: i)
            let range = NSRange(location: i, length: 1)
            if drop.contains(ch) {
                out.deleteCharacters(in: range)
            } else if breaks.contains(ch) {
                // CRLF: «\r» перед «\n» просто прибираємо, щоб не подвоїти абзац
                let nextIsLF = i + 1 < out.length
                    && (out.string as NSString).character(at: i + 1) == 0x000A
                if ch == 0x000D, nextIsLF {
                    out.deleteCharacters(in: range)
                } else {
                    out.replaceCharacters(in: range, with: "\n")
                }
            }
        }
        return out
    }

    // MARK: - Детектори

    /// Модальний кегль усієї вставки (зважений довжиною ранів)
    private static func modalFontSize(_ input: NSAttributedString) -> CGFloat {
        // Той самий алгоритм, що dominantFontSize, на повному діапазоні
        dominantFontSize(input, in: NSRange(location: 0, length: input.length)) ?? 12
    }

    private static func dominantFontSize(_ input: NSAttributedString, in range: NSRange) -> CGFloat? {
        guard range.length > 0 else { return nil }
        var counts: [CGFloat: Int] = [:]
        input.enumerateAttribute(.font, in: range) { v, r, _ in
            let size = (v as? NSFont)?.pointSize ?? 12
            counts[(size * 2).rounded() / 2, default: 0] += r.length
        }
        return counts.max { $0.value < $1.value }?.key
    }

    private struct LiteralMarker { let style: ListStyle; let length: Int }

    /// Літеральний маркер списку на початку абзацу ("- ", "• ", "1) ", "→ "…)
    ///
    /// ❗ Набір гліфів широкий свідомо: презентації малюють булет чим
    /// завгодно — Keynote любить «●», PowerPoint «○» і «■», Notion «•»
    /// (фідбек 2026-08-20: «маркери списків приїжджають величезними з
    /// презентацій»). Нерозпізнаний булет лишався в тексті окремим
    /// символом і виглядав чужорідним поруч із нашим маркером.
    ///
    /// ⚠️ Тире («—», «–») тут НЕМАЄ навмисно: у прозі з нього починається
    /// пряма мова, і список із діалогу був би гіршою бідою за булет
    private static func literalMarker(in text: String) -> LiteralMarker? {
        let bullets = "•◦▪▫●○■□◆◇‣⁃∙\\-\\*"
        let pattern = "^\\s{0,3}(?:([\(bullets)])|(→)|(▸)|(\\d{1,3}[.)]))[ \\t]+"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        let style: ListStyle
        if m.range(at: 2).location != NSNotFound { style = .arrow }
        else if m.range(at: 3).location != NSNotFound { style = .triangle }
        else if m.range(at: 4).location != NSNotFound { style = .number }
        else { style = .bullet }
        return LiteralMarker(style: style, length: m.range.length)
    }

    /// «Жирність»: справжній bold-трейт або вага ≥ semibold (наш bold = SemiBold)
    private static func isBoldish(_ f: NSFont?) -> Bool {
        guard let f else { return false }
        if f.fontDescriptor.symbolicTraits.contains(.bold) { return true }
        return NSFontManager.shared.weight(of: f) >= 7
    }

    private static func isItalicish(_ f: NSFont?) -> Bool {
        guard let f else { return false }
        if f.fontDescriptor.symbolicTraits.contains(.italic) { return true }
        return f.italicAngle != 0
    }

    private static func boolFlag(_ attrs: [NSAttributedString.Key: Any], _ k: NSAttributedString.Key) -> Bool {
        (attrs[k] as? NSNumber)?.boolValue ?? false
    }
}
