//
//  PasteNormalizerTests.swift
//  EmbarTests
//
//  R3-матриця (SPEC §15.24): нормалізація вставки з Safari/Word/VS Code/плейн.
//  normalize — чиста функція; пейстборд-обхід (внутрішній фрагмент) — через
//  унікальний NSPasteboard.
//

import XCTest
import AppKit
@testable import Embar

final class PasteNormalizerTests: XCTestCase {
    private let settings = NoteDocSettings.default

    // MARK: - Хелпери

    private func role(_ s: NSAttributedString, at loc: Int) -> String? {
        guard loc < s.length else { return nil }
        return s.attribute(.embarRole, at: loc, effectiveRange: nil) as? String
    }

    private func paragraphStart(_ s: NSAttributedString, paragraph n: Int) -> Int {
        let ns = s.string as NSString
        var loc = 0, i = 0
        while loc < ns.length {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            if i == n { return pr.location }
            i += 1
            loc = pr.location + max(pr.length, 1)
        }
        return 0
    }

    private func inkColor(_ s: NSAttributedString, at loc: Int) -> NSColor? {
        s.attribute(.foregroundColor, at: loc, effectiveRange: nil) as? NSColor
    }

    // MARK: - Safari-подібний HTML

    func testSafariLikeHTML() throws {
        let html = """
        <h1>Заголовок статті</h1>
        <p>Звичайний текст із <b>жирним</b>, <i>курсивом</i>,
        <a href="https://example.com">лінком</a> і <span style="color:#ff0000">червоним</span>.</p>
        <ul><li>перший пункт</li><li>другий пункт</li></ul>
        """
        let input = try XCTUnwrap(NSAttributedString(
            data: Data(html.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil))
        let out = PasteNormalizer.normalize(input, settings: settings)

        // Роль h1 на першому абзаці
        XCTAssertEqual(role(out, at: 0), "h1", "заголовок HTML має стати h1")

        // Жирний/курсив збережені як маркери, чужий колір — в ink
        var boldFound = false, italicFound = false, linkFound = false
        var foreignColor = false
        out.enumerateAttributes(in: NSRange(location: 0, length: out.length)) { attrs, r, _ in
            if (attrs[.embarBold] as? NSNumber)?.boolValue == true { boldFound = true }
            if (attrs[.embarItalic] as? NSNumber)?.boolValue == true { italicFound = true }
            if attrs[.link] != nil { linkFound = true }
            if let c = attrs[.foregroundColor] as? NSColor,
               c.redComponent > 0.9, c.greenComponent < 0.3 { foreignColor = true }
            XCTAssertNil(attrs[.backgroundColor], "фони мають зникати")
            _ = r
        }
        XCTAssertTrue(boldFound, "bold загублено")
        XCTAssertTrue(italicFound, "italic загублено")
        XCTAssertTrue(linkFound, "лінк загублено")
        XCTAssertFalse(foreignColor, "чужий червоний мав стати ink")

        // Список: наші маркери-гліфи + .embarList
        XCTAssertTrue(out.string.contains("•\t"), "пункти <ul> мають отримати наш маркер")
        var listAttr = false
        out.enumerateAttribute(.embarList, in: NSRange(location: 0, length: out.length)) { v, _, _ in
            if (v as? String) == "bullet" { listAttr = true }
        }
        XCTAssertTrue(listAttr)
    }

    // MARK: - Word-подібні кеглі (модальний базовий)

    func testWordLikeRoleClassification() {
        // Тіло 12pt (найдовше → базовий), заголовки 19/14.5, дрібний 9
        let doc = NSMutableAttributedString()
        doc.append(NSAttributedString(string: "Розділ\n",
                                      attributes: [.font: NSFont.boldSystemFont(ofSize: 19)]))
        doc.append(NSAttributedString(string: "Підрозділ\n",
                                      attributes: [.font: NSFont.systemFont(ofSize: 14.5)]))
        doc.append(NSAttributedString(string: String(repeating: "тіло документа ", count: 10) + "\n",
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        doc.append(NSAttributedString(string: "примітка дрібним\n",
                                      attributes: [.font: NSFont.systemFont(ofSize: 9)]))
        let out = PasteNormalizer.normalize(doc, settings: settings)

        XCTAssertEqual(role(out, at: paragraphStart(out, paragraph: 0)), "h1")   // 19/12 ≈ 1.58
        XCTAssertEqual(role(out, at: paragraphStart(out, paragraph: 1)), "h2")   // 14.5/12 ≈ 1.21
        XCTAssertEqual(role(out, at: paragraphStart(out, paragraph: 2)), "p")
        XCTAssertEqual(role(out, at: paragraphStart(out, paragraph: 3)), "s")    // 9/12 = 0.75
        // Bold трейт заголовка зберігся
        XCTAssertEqual((out.attribute(.embarBold, at: 0, effectiveRange: nil) as? NSNumber)?.boolValue, true)
    }

    // MARK: - VS Code-подібний кольоровий код

    func testVSCodeColoredCode() {
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let doc = NSMutableAttributedString()
        doc.append(NSAttributedString(string: "func ", attributes: [
            .font: mono, .foregroundColor: NSColor.systemPink, .backgroundColor: NSColor.black]))
        doc.append(NSAttributedString(string: "main() {\n", attributes: [
            .font: mono, .foregroundColor: NSColor.systemBlue, .backgroundColor: NSColor.black]))
        doc.append(NSAttributedString(string: "    print(42)\n", attributes: [
            .font: mono, .foregroundColor: NSColor.systemGreen, .backgroundColor: NSColor.black,
            .kern: 1.5]))
        let out = PasteNormalizer.normalize(doc, settings: settings)

        let ink = NSColor(embarHex: "#1a1a1a")
        out.enumerateAttributes(in: NSRange(location: 0, length: out.length)) { attrs, _, _ in
            XCTAssertNil(attrs[.backgroundColor], "фон коду має зникнути")
            XCTAssertNil(attrs[.kern], "кернінг має зникнути")
            if let c = attrs[.foregroundColor] as? NSColor {
                XCTAssertEqual(c, ink, "усі кольори коду мають стати ink")
            }
            if let f = attrs[.font] as? NSFont {
                XCTAssertFalse(f.fontDescriptor.symbolicTraits.contains(.monoSpace),
                               "моноширинний шрифт не має протікати")
            }
            XCTAssertEqual((attrs[.embarRole] as? String), "p")
        }
    }

    // MARK: - Плейн-текст

    func testPlainTextParagraphs() {
        let out = PasteNormalizer.normalize(NSAttributedString(string: "перший\nдругий"), settings: settings)
        XCTAssertEqual(out.string, "перший\nдругий")
        XCTAssertEqual(role(out, at: 0), "p")
        XCTAssertEqual(role(out, at: paragraphStart(out, paragraph: 1)), "p")
        XCTAssertNotNil(out.attribute(.font, at: 0, effectiveRange: nil))
    }

    // MARK: - Літеральні маркери

    func testLiteralMarkersDeduplicated() {
        let doc = NSAttributedString(string: "- пункт один\n1) пункт два\n→ стрілка\n")
        let out = PasteNormalizer.normalize(doc, settings: settings)

        XCTAssertTrue(out.string.hasPrefix("•\tпункт один"), "«- » має стати нашим маркером: \(out.string)")
        XCTAssertTrue(out.string.contains("1.\tпункт два"), "«1) » має стати «1.\\t»")
        XCTAssertTrue(out.string.contains("→\tстрілка"))
        var styles: Set<String> = []
        out.enumerateAttribute(.embarList, in: NSRange(location: 0, length: out.length)) { v, _, _ in
            if let s = v as? String { styles.insert(s) }
        }
        XCTAssertEqual(styles, ["bullet", "number", "arrow"])
    }

    // MARK: - Складені емоджі (P2.32)

    /// ZWJ (U+200D) тримає складені емоджі вкупі: викидати його не можна,
    /// інакше 👨‍👩‍👧 розпадається на трьох окремих людей
    func testCompoundEmojiSurvivesNormalization() {
        let family = "👨\u{200D}👩\u{200D}👧"     // сімʼя через ZWJ
        let flag = "🏳\u{FE0F}\u{200D}🌈"          // прапор: VS16 + ZWJ
        let wave = "👋\u{1F3FD}"                   // тон шкіри
        let out = PasteNormalizer.normalize(
            NSAttributedString(string: "\(family) і \(flag) і \(wave)"),
            settings: settings)
        XCTAssertTrue(out.string.contains(family), "ZWJ зник - сімʼя розпалась: \(out.string)")
        XCTAssertTrue(out.string.contains(flag), "варіаційний селектор або ZWJ зник: \(out.string)")
        XCTAssertTrue(out.string.contains(wave), "модифікатор тону шкіри зник: \(out.string)")
        // Кожен лишився ОДНИМ графемним кластером
        XCTAssertEqual("\(family)".count, 1)
        XCTAssertTrue(out.string.count < out.string.unicodeScalars.count,
                      "кластери мають клеїтись, а не рахуватись по скалярах")
    }

    /// ZWNJ (U+200C) - законний символ письма (перська, гінді), не сміття
    func testZWNJPreserved() {
        let persian = "می\u{200C}خواهم"
        let out = PasteNormalizer.normalize(
            NSAttributedString(string: persian), settings: settings)
        // По скалярах: ZWNJ клеїться до сусіднього кластера, і contains
        // по графемах його не бачить ніколи
        XCTAssertTrue(out.string.unicodeScalars.contains("\u{200C}"),
                      "ZWNJ вирізано: \(out.string)")
    }

    /// А справжнє невидиме сміття далі вирізається
    func testInvisibleJunkStillDropped() {
        let junk = "текст\u{200B}із\u{FEFF}сміттям\u{FFFC}"
        let out = PasteNormalizer.normalize(
            NSAttributedString(string: junk), settings: settings)
        XCTAssertEqual(out.string, "текстізсміттям")
    }

    // MARK: - Ідемпотентність

    func testIdempotence() {
        let doc = NSMutableAttributedString()
        doc.append(NSAttributedString(string: "Заголовок\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 19)]))
        doc.append(NSAttributedString(string: String(repeating: "тіло ", count: 20) + "\n",
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        doc.append(NSAttributedString(string: "- пункт\n", attributes: [.font: NSFont.systemFont(ofSize: 12)]))

        let once = PasteNormalizer.normalize(doc, settings: settings)
        let twice = PasteNormalizer.normalize(once, settings: settings)

        XCTAssertEqual(once.string, twice.string, "текст має бути стабільним")
        // Ролі/списки/трейти стабільні по абзацах
        for n in 0..<3 {
            let l1 = paragraphStart(once, paragraph: n)
            let l2 = paragraphStart(twice, paragraph: n)
            XCTAssertEqual(role(once, at: l1), role(twice, at: l2), "роль абзацу \(n) змінилась")
            XCTAssertEqual(once.attribute(.embarList, at: l1, effectiveRange: nil) as? String,
                           twice.attribute(.embarList, at: l2, effectiveRange: nil) as? String,
                           "список абзацу \(n) змінився")
        }
        XCTAssertEqual((twice.attribute(.embarBold, at: 0, effectiveRange: nil) as? NSNumber)?.boolValue,
                       true, "bold заголовка загубився при повторній нормалізації")
    }

    // MARK: - Внутрішній фрагмент минає нормалізацію

    func testInternalFragmentBypassesNormalization() throws {
        let uuid = UUID().uuidString
        let fragment = NSAttributedString(string: "згадка", attributes: [
            .embarMention: uuid as NSString,
            .embarHighlight: "yellow" as NSString,
        ])
        let pb = NSPasteboard(name: NSPasteboard.Name("embar-test-\(UUID().uuidString)"))
        pb.clearContents()
        pb.declareTypes([PasteNormalizer.internalType], owner: nil)
        pb.setData(try XCTUnwrap(NoteArchiver.encode(fragment)), forType: PasteNormalizer.internalType)

        let read = try XCTUnwrap(PasteNormalizer.read(pb, settings: settings))
        XCTAssertEqual(read.string, "згадка")
        XCTAssertEqual(read.attribute(.embarMention, at: 0, effectiveRange: nil) as? String, uuid,
                       "згадка має пережити внутрішню вставку")
        XCTAssertEqual(read.attribute(.embarHighlight, at: 0, effectiveRange: nil) as? String, "yellow",
                       "хайлайт має пережити внутрішню вставку")
    }

    // MARK: - Картинки викидаються (v1)

    func testAttachmentsStripped() {
        let doc = NSMutableAttributedString(string: "до ")
        doc.append(NSAttributedString(attachment: NSTextAttachment()))
        doc.append(NSAttributedString(string: " після"))
        let out = PasteNormalizer.normalize(doc, settings: settings)
        XCTAssertFalse(out.string.contains("\u{FFFC}"), "attachment-символ мав зникнути")
        XCTAssertEqual(out.string, "до  після")
    }
}
