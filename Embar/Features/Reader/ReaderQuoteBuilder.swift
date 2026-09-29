//
//  ReaderQuoteBuilder.swift
//  Embar
//
//  Блок цитати для тіла нотатки (SPEC §12.3; прототип buildQuoteBlock):
//  [тіло: «текст» для цитат, plain для решти] + [підпис: автор/тип ·
//  НАЗВА БЛОКНОТА · ст. N] + порожній абзац для продовження письма.
//  Підпис несе .embarReaderSource("bookUUID|entryUUID") — клік у
//  редакторі нотаток веде назад до запису (goToReaderEntry).
//

import AppKit

enum ReaderQuoteBuilder {

    /// Значення .embarReaderSource
    static func sourceValue(book: UUID, entry: UUID) -> String {
        "\(book.uuidString)|\(entry.uuidString)"
    }

    static func parseSource(_ raw: String) -> (book: UUID, entry: UUID)? {
        let parts = raw.split(separator: "|")
        guard parts.count == 2,
              let book = UUID(uuidString: String(parts[0])),
              let entry = UUID(uuidString: String(parts[1])) else { return nil }
        return (book, entry)
    }

    /// Мітка типу для не-цитат (прототип TYPE_LBL)
    static func typeLabel(_ kind: ReaderEntryKind) -> String {
        switch kind {
        case .thought:
            String(localized: "quote.type.thought", defaultValue: "думка",
                   comment: "Підпис під цитатою в нотатці — тип запису")
        case .question:
            String(localized: "quote.type.question", defaultValue: "питання",
                   comment: "Підпис під цитатою в нотатці — тип запису")
        case .insight:
            String(localized: "quote.type.insight", defaultValue: "інсайт",
                   comment: "Підпис під цитатою в нотатці — тип запису")
        case .voice:
            String(localized: "quote.type.voice", defaultValue: "голосове",
                   comment: "Підпис під цитатою в нотатці — тип запису")
        case .quote:
            ""
        }
    }

    /// Зібрати блок для вставки в тіло нотатки
    static func block(bookID: UUID, bookTitle: String,
                      entryID: UUID, kind: ReaderEntryKind,
                      text: String, author: String?) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // 1. Тіло (прототип .qn-quote — editorial hairline): курсив
        // ЗВИЧАЙНОГО шрифту тіла (не Fraunces), line-height 1.7,
        // світла риска малюється по .embarReaderQuote
        // Лапки — теж переклад: ключ «%@» → укр. «ялинки», англ. “лапки”
        let body = kind == .quote ? String(localized: "«\(text)»") : text
        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.headIndent = NoteTypography.quoteTextIndent
        bodyStyle.firstLineHeadIndent = NoteTypography.quoteTextIndent
        // CSS line-height:1.7 = 1.7×кегль (25.5pt при 15). lineHeightMultiple
        // множив би ПРИРОДНУ висоту рядка (~1.2×кегль) → ~31pt, «подвійні»
        // рядки (фідбек 2026-07-07) — тому фіксуємо висоту явно
        bodyStyle.minimumLineHeight = 25.5
        bodyStyle.maximumLineHeight = 25.5
        bodyStyle.paragraphSpacingBefore = 12
        bodyStyle.paragraphSpacing = 6
        result.append(NSAttributedString(string: body + "\n", attributes: [
            .embarReaderQuote: NSNumber(value: true),
            .embarItalic: NSNumber(value: true),
            .embarRole: ParagraphRole.p.rawValue as NSString,
            .font: NoteTypography.font(role: .p, italic: true),
            .foregroundColor: NoteTypography.inkColor,
            .paragraphStyle: bodyStyle,
        ]))

        // 2. Підпис: [автор цитати | мітка типу] · НАЗВА (UPPERCASE)
        var lead = kind == .quote ? (author ?? "") : typeLabel(kind)
        lead = lead.trimmingCharacters(in: .whitespaces)
        let caption = (lead.isEmpty ? "" : lead + " · ")
            + (bookTitle.isEmpty ? String(localized: "Без назви") : bookTitle)
        var captionAttrs = NoteTypography.quoteAuthorAttributes()
        captionAttrs[.embarReaderSource] =
            sourceValue(book: bookID, entry: entryID) as NSString
        // Маркер блоку і на підписі: риска накриває весь блок (фідбек),
        // а атомарність (delete цілком) працює по суміжному рану
        captionAttrs[.embarReaderQuote] = NSNumber(value: true)
        result.append(NSAttributedString(string: caption.uppercased() + "\n",
                                         attributes: captionAttrs))

        // 3. Порожній p-абзац — курсор має куди стати після вставки
        result.append(NSAttributedString(string: "\n", attributes: [
            .embarRole: ParagraphRole.p.rawValue as NSString,
            .font: NoteTypography.font(role: .p),
            .foregroundColor: NoteTypography.inkColor,
            .paragraphStyle: NoteTypography.paragraphStyle(role: .p),
        ]))
        return result
    }
}
