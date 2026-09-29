//
//  ReaderTagsTests.swift
//  EmbarTests
//
//  Парсер #тегів і детермінований колір (SPEC §4.3). Еталонні індекси
//  порахував прототипний JS-алгоритм (osascript JXA, 2026-07-07) —
//  Swift-порт має збігатися біт-у-біт.
//

import XCTest
import SwiftUI
@testable import Embar

final class ReaderTagsTests: XCTestCase {

    // MARK: - Парсер

    func testFindsUkrainianAndLatinTags() {
        let names = ReaderTags.matches(in: "про #ідею та #mind_set разом").map(\.name)
        XCTAssertEqual(names, ["ідею", "mind_set"])
    }

    func testRangeCoversHashSign() {
        let text = "а #б в"
        let match = try! XCTUnwrap(ReaderTags.matches(in: text).first)
        XCTAssertEqual((text as NSString).substring(with: match.range), "#б")
    }

    func testNoTags() {
        XCTAssertTrue(ReaderTags.matches(in: "чистий текст без ґраток").isEmpty)
    }

    func testUniqueTagsSortedAcrossEntries() {
        let tags = ReaderTags.uniqueTags(in: ["#б і #а", "#а знову"])
        XCTAssertEqual(tags, ["а", "б"])
    }

    func testStrippedRemovesTagsAndLeadingSpace() {
        XCTAssertEqual(ReaderTags.stripped("думка #ідея про світ #в2"),
                       "думка про світ")
    }

    // MARK: - Колір (еталон хеша: прототипний getTagColor через JXA,
    // на його 10 кошиках; продакшн ділить той самий хеш на 5 слотів
    // активної палітри - P2.25)

    func testHashMatchesPrototypeJS() {
        XCTAssertEqual(ReaderTags.colorIndex(for: "ідея", buckets: 10), 3)
        XCTAssertEqual(ReaderTags.colorIndex(for: "дизайн", buckets: 10), 1)
        XCTAssertEqual(ReaderTags.colorIndex(for: "книга", buckets: 10), 9)
        XCTAssertEqual(ReaderTags.colorIndex(for: "mind", buckets: 10), 7)
        XCTAssertEqual(ReaderTags.colorIndex(for: "a", buckets: 10), 5)
        XCTAssertEqual(ReaderTags.colorIndex(for: "філософія", buckets: 10), 8)
    }

    func testCapsuleIsDeterministic() {
        let palette = Palette.byDefault
        XCTAssertEqual(ReaderTags.capsule(for: "тег", palette: palette),
                       ReaderTags.capsule(for: "тег", palette: palette))
    }

    /// Фон капсули — саме стік-колір активної палітри (P2.25)
    func testCapsuleBackgroundComesFromPalette() {
        for palette in Palette.all {
            let capsule = ReaderTags.capsule(for: "ідея", palette: palette)
            XCTAssertTrue(palette.sticky.contains(capsule.bg),
                          "фон капсули не з палітри \(palette.slug)")
        }
    }

    /// Текст капсули читабельний на своєму фоні в КОЖНІЙ палітрі:
    /// WCAG 4.5:1 — той самий поріг, що в адаптивному чорнилі стіків
    func testCapsuleInkContrastInEveryPalette() {
        for palette in Palette.all {
            // Хеш імен непередбачуваний — перебираємо, поки не побачимо
            // ВСІ слоти палітри (кожен фон мусить бути перевірений)
            var covered = Set<Int>()
            var i = 0
            while covered.count < palette.sticky.count, i < 200 {
                let name = "тег\(i)"
                i += 1
                let slot = ReaderTags.colorIndex(
                    for: name, buckets: palette.sticky.count)
                guard covered.insert(slot).inserted else { continue }
                let capsule = ReaderTags.capsule(for: name, palette: palette)
                let ratio = wcagContrast(capsule.fg, capsule.bg)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.4, // невеликий люфт на округлення компонентів
                    "контраст \(ratio) у \(palette.slug), слот \(slot)")
            }
            XCTAssertEqual(covered.count, palette.sticky.count,
                           "не всі слоти покриті у \(palette.slug)")
        }
    }

    private func wcagContrast(_ a: Color, _ b: Color) -> CGFloat {
        func luminance(_ c: Color) -> CGFloat {
            guard let rgb = NSColor(c).usingColorSpace(.sRGB) else { return 0 }
            func channel(_ v: CGFloat) -> CGFloat {
                v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(rgb.redComponent)
                + 0.7152 * channel(rgb.greenComponent)
                + 0.0722 * channel(rgb.blueComponent)
        }
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
