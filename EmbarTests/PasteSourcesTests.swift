//
//  PasteSourcesTests.swift
//  EmbarTests
//
//  Вставка з РЕАЛЬНИХ джерел (фідбек 2026-08-20): Keynote/PowerPoint,
//  Word, Google Docs, веб, Notion, простий текст.
//
//  Правило одне: зі вставленого лишається тільки СТРУКТУРА (абзаци,
//  списки, жирний/курсив, посилання), усе оформлення - наше. Тому тут
//  не по одному ассерту на джерело, а спільний інваріант
//  `assertOnlyOurTypography`: він проходить по КОЖНОМУ рану і не пускає
//  жодного чужого шрифту, кегля, кольору, фону чи міжрядкового
//  інтервалу. Нове джерело з новою дивиною завалить саме його.
//

import XCTest
import AppKit
@testable import Embar

final class PasteSourcesTests: XCTestCase {
    private let settings = NoteDocSettings.default

    // MARK: - Спільний інваріант

    /// Кеглі, які взагалі може дати наша типографіка (усі ролі × жирний/
    /// курсив + маркер списку + цитата)
    private var ourFontSizes: Set<CGFloat> {
        var sizes: Set<CGFloat> = [NoteTypography.quoteFont().pointSize]
        for role in [ParagraphRole.h1, .h2, .p, .s] {
            for bold in [false, true] {
                for italic in [false, true] {
                    sizes.insert(NoteTypography.font(role: role, bold: bold,
                                                     italic: italic,
                                                     settings: settings).pointSize)
                }
            }
        }
        return sizes
    }

    private var ourColors: Set<String> {
        Set([NoteTypography.inkColor, NoteTypography.quoteTextColor,
             NoteTypography.mutedColor].map(hex))
    }

    private func hex(_ c: NSColor) -> String {
        guard let s = c.usingColorSpace(.sRGB) else { return "?" }
        return String(format: "#%02X%02X%02X", Int(s.redComponent * 255),
                      Int(s.greenComponent * 255), Int(s.blueComponent * 255))
    }

    /// Міжрядкові інтервали, які може дати наша типографіка
    private var ourLineHeights: Set<CGFloat> {
        var out: Set<CGFloat> = [1.6] // фіксований у цитаті
        for role in [ParagraphRole.h1, .h2, .p, .s] {
            let st = NoteTypography.paragraphStyle(role: role, settings: settings)
            out.insert(st.lineHeightMultiple)
        }
        out.insert(1) // маркери списку йдуть без множника
        return out
    }

    private func assertOnlyOurTypography(_ s: NSAttributedString, _ source: String,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) {
        XCTAssertGreaterThan(s.length, 0, "\(source): порожній результат",
                             file: file, line: line)
        let sizes = ourFontSizes, colors = ourColors, heights = ourLineHeights
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attrs, r, _ in
            let piece = (s.string as NSString).substring(with: r)
                .replacingOccurrences(of: "\n", with: "⏎")
            let where_ = "\(source) «\(piece)»"

            if let f = attrs[.font] as? NSFont {
                XCTAssertTrue(sizes.contains(f.pointSize),
                              "\(where_): чужий кегль \(f.pointSize)",
                              file: file, line: line)
                XCTAssertFalse(f.familyName == "Times" || f.familyName == "Times New Roman"
                               || f.familyName == "Calibri" || f.familyName == "Helvetica"
                               || f.familyName == "Arial",
                               "\(where_): чуже сімейство \(f.familyName ?? "?")",
                               file: file, line: line)
            }
            if let c = attrs[.foregroundColor] as? NSColor {
                XCTAssertTrue(colors.contains(hex(c)),
                              "\(where_): чужий колір тексту \(hex(c))",
                              file: file, line: line)
            }
            XCTAssertNil(attrs[.backgroundColor],
                         "\(where_): приїхав чужий фон", file: file, line: line)
            XCTAssertNil(attrs[.strikethroughStyle],
                         "\(where_): приїхало закреслення", file: file, line: line)
            XCTAssertNil(attrs[.shadow], "\(where_): приїхала тінь",
                         file: file, line: line)
            XCTAssertNil(attrs[.kern], "\(where_): приїхав чужий кернінг",
                         file: file, line: line)
            if let st = attrs[.paragraphStyle] as? NSParagraphStyle {
                XCTAssertTrue(heights.contains(st.lineHeightMultiple),
                              "\(where_): чужий міжрядковий \(st.lineHeightMultiple)",
                              file: file, line: line)
                XCTAssertEqual(st.lineSpacing, 0, accuracy: 0.01,
                               "\(where_): чужий lineSpacing", file: file, line: line)
            }
        }
    }

    private func fromHTML(_ html: String) throws -> NSAttributedString {
        let data = try XCTUnwrap(html.data(using: .utf8))
        let s = try XCTUnwrap(NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil))
        return PasteNormalizer.normalize(s, settings: settings)
    }

    // MARK: - Keynote / PowerPoint

    /// ❗ Головна скарга: «маркери списків приїжджають величезними з
    /// презентацій». У слайді тіло 28pt, заголовок 44pt, буліт - окремий
    /// ран того ж кегля
    func testKeynoteSlideWithBigBullets() throws {
        let out = try fromHTML("""
        <div style="font-family: Helvetica; font-size: 44px; color: #FFFFFF;
                    background-color: #1A1A1A">Плани на квартал</div>
        <div style="font-family: Helvetica; font-size: 28px; color: #EFEFEF;
                    line-height: 1.9">● Запустити бету</div>
        <div style="font-family: Helvetica; font-size: 28px; color: #EFEFEF;
                    line-height: 1.9">● Зібрати фідбек</div>
        """)
        assertOnlyOurTypography(out, "Keynote")
        XCTAssertFalse(out.string.contains("●"),
                       "буліт презентації мусить стати НАШИМ маркером")
    }

    /// PowerPoint любить «○» і «▪», а ще суцільний тонований фон
    func testPowerPointBulletsAndBackground() throws {
        let out = try fromHTML("""
        <p style="font-size: 32pt; background-color: #FFF2CC">○ Перший пункт</p>
        <p style="font-size: 32pt; background-color: #FFF2CC">▪ Другий пункт</p>
        """)
        assertOnlyOurTypography(out, "PowerPoint")
        XCTAssertFalse(out.string.contains("○"))
        XCTAssertFalse(out.string.contains("▪"))
    }

    // MARK: - Word

    func testWordDocumentWithStylesAndColors() throws {
        let out = try fromHTML("""
        <p class=MsoNormal style="font-family:Calibri; font-size:11.0pt;
           line-height:150%; color:#1F4E79">Вступний абзац із
           <b style="color:#C00000">жирним</b> і <i>курсивом</i>.</p>
        <p class=MsoListParagraph style="font-family:Calibri; font-size:11.0pt">
           1. Перший</p>
        """)
        assertOnlyOurTypography(out, "Word")
    }

    // MARK: - Google Docs

    /// Google Docs віддає все у <span> з інлайновими стилями, зокрема
    /// vertical-align і letter-spacing
    func testGoogleDocsSpans() throws {
        let out = try fromHTML("""
        <p dir="ltr" style="line-height:1.38; margin-top:0pt; margin-bottom:0pt">
        <span style="font-size:11pt; font-family:Arial; color:#434343;
        background-color:#fff2cc; letter-spacing:0.2pt; font-weight:400">
        Абзац із документа</span>
        <span style="font-size:11pt; font-family:Arial; font-weight:700">жирний хвіст</span></p>
        """)
        assertOnlyOurTypography(out, "Google Docs")
    }

    // MARK: - Веб

    func testWebArticleWithLinkAndQuote() throws {
        let out = try fromHTML("""
        <h2 style="font-size:28px">Підзаголовок</h2>
        <p style="font-size:16px; color:#333">Текст із
        <a href="https://example.com" style="color:#0645AD">посиланням</a>.</p>
        <blockquote style="font-size:16px; color:#777">Цитата зі статті</blockquote>
        """)
        assertOnlyOurTypography(out, "Веб")
        // Структура вижила: посилання лишилось
        var foundLink = false
        out.enumerateAttribute(.link, in: NSRange(location: 0, length: out.length)) { v, _, _ in
            if v != nil { foundLink = true }
        }
        XCTAssertTrue(foundLink, "посилання - це структура, воно лишається")
    }

    // MARK: - Notion

    /// Notion кладе булети як «•» у span із власним кеглем і кольором
    func testNotionBlocks() throws {
        let out = try fromHTML("""
        <ul><li style="font-size:16px; color:#37352F">Перший блок</li>
        <li style="font-size:16px; color:#37352F">Другий блок</li></ul>
        <p style="font-size:16px; color:#37352F">
        <span style="background-color:#FBF3DB">підсвічений фрагмент</span></p>
        """)
        assertOnlyOurTypography(out, "Notion")
    }

    // MARK: - Простий текст

    func testPlainTextStaysPlain() {
        let out = PasteNormalizer.normalize(
            NSAttributedString(string: "Перший рядок\nДругий рядок"),
            settings: settings)
        assertOnlyOurTypography(out, "Плейн")
        XCTAssertEqual(out.string, "Перший рядок\nДругий рядок")
    }

    // MARK: - Чужі роздільники рядків і невидимий мотлох

    /// Word ставить мʼякий перенос U+000B, презентації - U+2028;
    /// `paragraphRange` за межу абзацу їх не вважає, і рядки приїжджали
    /// склеєними
    func testForeignLineBreaksBecomeParagraphs() {
        let out = PasteNormalizer.normalize(
            NSAttributedString(string: "Перший\u{2028}Другий\u{000B}Третій"),
            settings: settings)
        assertOnlyOurTypography(out, "Чужі переноси")
        XCTAssertEqual(out.string, "Перший\nДругий\nТретій")
    }

    /// CRLF не має подвоювати абзац
    func testWindowsLineEndingsCollapse() {
        let out = PasteNormalizer.normalize(
            NSAttributedString(string: "Перший\r\nДругий\rТретій"),
            settings: settings)
        XCTAssertEqual(out.string, "Перший\nДругий\nТретій")
    }

    /// Нульової ширини символи й «дірки» від картинок просто зникають
    func testInvisibleJunkIsDropped() {
        let out = PasteNormalizer.normalize(
            NSAttributedString(string: "Те\u{200B}кст\u{FEFF} з\u{FFFC}вставки"),
            settings: settings)
        XCTAssertEqual(out.string, "Текст звставки")
    }

    /// Плейн-текст із дефісними маркерами - це список, а не текст із дефісами
    func testPlainTextMarkersBecomeList() {
        let out = PasteNormalizer.normalize(
            NSAttributedString(string: "- перший\n- другий"),
            settings: settings)
        assertOnlyOurTypography(out, "Плейн-список")
        XCTAssertFalse(out.string.contains("- перший"),
                       "дефіс мусить стати нашим маркером")
    }
}
