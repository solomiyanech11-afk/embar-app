//
//  NoteArchiverTests.swift
//  EmbarTests
//
//  R1-проба (SPEC §11.3): кастомні `.embar*`-атрибути мають пережити
//  round-trip через NSKeyedArchiver. Якщо цей тест червоний — весь формат
//  rich-тіла під питанням, далі не йдемо.
//

import XCTest
import AppKit
@testable import Embar

final class NoteArchiverTests: XCTestCase {

    /// Побудувати документ з УСІМА нашими кастомними атрибутами
    private func richSample() -> NSAttributedString {
        let s = NSMutableAttributedString()

        // Абзац H1 з роллю
        let h1 = NSAttributedString(string: "Заголовок\n", attributes: [
            .embarRole: ParagraphRole.h1.rawValue as NSString,
            .font: NoteTypography.font(role: .h1),
        ])
        s.append(h1)

        // Згадка (чіп) з UUID
        let uuid = UUID().uuidString
        let mention = NSAttributedString(string: "інша нотатка", attributes: [
            .embarMention: uuid as NSString,
            .backgroundColor: NSColor(embarHex: "#ecebe9"),
        ])
        s.append(mention)

        // Хайлайт + колір тексту
        let hi = NSAttributedString(string: " важливе ", attributes: [
            .embarHighlight: HighlightColor.yellow.rawValue as NSString,
            .backgroundColor: HighlightColor.yellow.nsColor,
            .embarTextColor: BodyTextColor.red.rawValue as NSString,
            .foregroundColor: BodyTextColor.red.nsColor,
        ])
        s.append(hi)
        s.append(NSAttributedString(string: "\n"))

        // Пункт списку (стрілка) + цитата
        let li = NSAttributedString(string: "→\tпункт\n", attributes: [
            .embarList: ListStyle.arrow.rawValue as NSString,
            .paragraphStyle: NoteTypography.paragraphStyle(role: .p, list: .arrow),
        ])
        s.append(li)
        let quote = NSAttributedString(string: "цитата\n", attributes: [
            .embarQuote: NSNumber(value: true),
            .paragraphStyle: NoteTypography.paragraphStyle(role: .p, quote: true),
        ])
        s.append(quote)

        return s
    }

    func testRoundTripPreservesCustomAttributes() throws {
        let original = richSample()
        let data = try XCTUnwrap(NoteArchiver.encode(original), "encode повернув nil")
        let decoded = try XCTUnwrap(NoteArchiver.decode(data), "decode повернув nil")

        XCTAssertEqual(decoded.string, original.string, "текст змінився")

        // Роль H1 на першому символі
        let role = decoded.attribute(.embarRole, at: 0, effectiveRange: nil) as? String
        XCTAssertEqual(role, "h1")

        // Згадка: знайти діапазон з .embarMention і звірити UUID
        var foundMention: String?
        decoded.enumerateAttribute(.embarMention, in: NSRange(location: 0, length: decoded.length)) { v, _, _ in
            if let u = v as? String { foundMention = u }
        }
        let originalMention = attributeValue(original, .embarMention) as? String
        XCTAssertNotNil(foundMention)
        XCTAssertEqual(foundMention, originalMention)

        // Хайлайт + колір тексту як слаги
        XCTAssertTrue(hasAttribute(decoded, .embarHighlight, equalTo: "yellow"))
        XCTAssertTrue(hasAttribute(decoded, .embarTextColor, equalTo: "red"))

        // Список і цитата
        XCTAssertTrue(hasAttribute(decoded, .embarList, equalTo: "arrow"))
        var quoteFound = false
        decoded.enumerateAttribute(.embarQuote, in: NSRange(location: 0, length: decoded.length)) { v, _, _ in
            if (v as? NSNumber)?.boolValue == true { quoteFound = true }
        }
        XCTAssertTrue(quoteFound, "цитату загублено")
    }

    func testIdempotentReEncode() throws {
        let original = richSample()
        let once = try XCTUnwrap(NoteArchiver.decode(XCTUnwrap(NoteArchiver.encode(original))))
        let twice = try XCTUnwrap(NoteArchiver.decode(XCTUnwrap(NoteArchiver.encode(once))))
        XCTAssertEqual(once.string, twice.string)
        XCTAssertTrue(hasAttribute(twice, .embarHighlight, equalTo: "yellow"))
    }

    /// Регресія 2026-07-05: NSTextAttachment.initWithCoder делегує в
    /// init(data:ofType:) — без override'а в сабкласі декодування нотатки
    /// з фото трапило runtime (краш/«зависання» при відкритті)
    func testPhotoRowAttachmentRoundTrip() throws {
        let ids = [UUID().uuidString, UUID().uuidString]
        let att = EmbarPhotoRowAttachment(imageIDs: ids, columns: 2)
        let body = NSMutableAttributedString(string: "до\n")
        body.append(NSAttributedString(attachment: att))
        body.append(NSAttributedString(string: "\nпісля"))

        let data = try XCTUnwrap(NoteArchiver.encode(body))
        let decoded = try XCTUnwrap(NoteArchiver.decode(data),
                                    "декодування тіла з фото повернуло nil")

        var found: EmbarPhotoRowAttachment?
        decoded.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: decoded.length)) { v, _, _ in
            if let a = v as? EmbarPhotoRowAttachment { found = a }
        }
        let restored = try XCTUnwrap(found, "attachment загубив клас при декодуванні")
        XCTAssertEqual(restored.imageIDs, ids)
        XCTAssertEqual(restored.columns, 2)
        XCTAssertNotNil(restored.attachmentCell, "cell має відтворюватися після декодування")
    }

    func testCorruptDataReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0xFF, 0x10])
        XCTAssertNil(NoteArchiver.decode(garbage), "битий архів мав дати nil, а не крашнути")
    }

    func testPlainTextStripsAttachmentChars() {
        let s = NSMutableAttributedString(string: "до ")
        s.append(NSAttributedString(string: "\u{FFFC}")) // символ attachment
        s.append(NSAttributedString(string: " після"))
        XCTAssertEqual(NoteArchiver.plainText(s), "до  після")
    }

    // MARK: - Хелпери

    private func attributeValue(_ s: NSAttributedString, _ key: NSAttributedString.Key) -> Any? {
        var found: Any?
        s.enumerateAttribute(key, in: NSRange(location: 0, length: s.length)) { v, _, stop in
            if let v { found = v; stop.pointee = true }
        }
        return found
    }

    private func hasAttribute(_ s: NSAttributedString, _ key: NSAttributedString.Key, equalTo slug: String) -> Bool {
        var ok = false
        s.enumerateAttribute(key, in: NSRange(location: 0, length: s.length)) { v, _, stop in
            if let str = v as? String, str == slug { ok = true; stop.pointee = true }
        }
        return ok
    }
}
