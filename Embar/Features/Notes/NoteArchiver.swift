//
//  NoteArchiver.swift
//  Embar
//
//  Серіалізація rich-тіла нотатки (SPEC §11.3). NSKeyedArchiver зберігає ВСЕ,
//  включно з кастомними `.embar*`-атрибутами (RTFD їх губить). Значення
//  кастомних ключів — лише NSString/NSNumber, тож secure unarchiving працює.
//

import AppKit

enum NoteArchiver {

    /// Архів NSAttributedString → Data (для Note.contentData)
    static func encode(_ text: NSAttributedString) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: text, requiringSecureCoding: true)
    }

    /// Data → NSAttributedString. Явний список дозволених класів: attachments,
    /// paragraph styles, шрифти й кольори мають бути дозволені окремо.
    static func decode(_ data: Data) -> NSAttributedString? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        let allowed: [AnyClass] = [
            NSAttributedString.self, NSMutableAttributedString.self,
            NSParagraphStyle.self, NSMutableParagraphStyle.self,
            NSFont.self, NSColor.self, NSTextAttachment.self, EmbarPhotoRowAttachment.self,
            NSTextList.self, NSTextBlock.self, NSTextTab.self,
            NSString.self, NSNumber.self, NSURL.self, NSArray.self, NSDictionary.self,
        ]
        let result = unarchiver.decodeObject(of: allowed, forKey: NSKeyedArchiveRootObjectKey)
        unarchiver.finishDecoding()
        return result as? NSAttributedString
    }

    /// Плейн-дзеркало: рядок без attachment-символів (для пошуку/прев'ю/`content`)
    static func plainText(_ text: NSAttributedString) -> String {
        let full = text.string
        // Символ attachment (U+FFFC) прибираємо — у прев'ю він як пусте «□»
        return full.replacingOccurrences(of: "\u{FFFC}", with: "")
    }
}
