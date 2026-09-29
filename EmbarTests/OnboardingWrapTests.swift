//
//  OnboardingWrapTests.swift
//  EmbarTests
//
//  Пояснювальні тексти тактів мусять лягати у два рядки. Спершу на
//  330pt самотнім лишалось «own.», потім на 360pt - «them.» (фідбек
//  2026-08-11). Ширину підібрано заміром, і тест її стереже - для ВСІХ
//  таких текстів одразу, бо помилка щоразу та сама.
//
//  Міряємо АКТИВНУ локалізацію, а не копію рядка в тесті: інакше після
//  правки перекладу тест і далі перевіряв би застарілий текст.
//

import XCTest
import AppKit
@testable import Embar

final class OnboardingWrapTests: XCTestCase {

    /// Рядки, на які NSLayoutManager розкладає текст у заданій ширині
    private func lines(_ text: String, width: CGFloat, font: NSFont) -> [String] {
        let storage = NSTextStorage(attributedString:
            NSAttributedString(string: text, attributes: [.font: font]))
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: width,
                                                     height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)

        var result: [String] = []
        var glyph = 0
        while glyph < layout.numberOfGlyphs {
            var range = NSRange()
            _ = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
            let chars = layout.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            result.append((text as NSString).substring(with: chars)
                .trimmingCharacters(in: .whitespacesAndNewlines))
            glyph = range.location + range.length
        }
        return result
    }

    func testStageSubtitlesFitTwoLines() {
        FontRegistrar.registerBundledFonts()
        let font = NSFont(name: "Inter-Regular", size: 15) ?? .systemFont(ofSize: 15)
        let texts = [
            String(localized: "Наведи курсор на правий край екрана - панель Embar висунеться сама."),
            String(localized: "Вони покажуть решту. Це звичайні стіки - виконуй, видаляй, переписуй."),
        ]
        for text in texts {
            let laid = lines(text, width: OnboardingDesign.bodyTextWidth, font: font)
            XCTAssertLessThanOrEqual(laid.count, 2,
                                     "мусить лягати у два рядки: \(laid)")
            let last = laid.last?.split(separator: " ").count ?? 0
            XCTAssertGreaterThan(last, 1,
                                 "останній рядок з одного слова читається як обірваний: \(laid)")
        }
    }
}
