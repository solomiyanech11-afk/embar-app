//
//  StickyInkTests.swift
//  EmbarTests
//
//  Адаптивне чорнило на стіках (SPEC §15.57): для КОЖНОГО кольору кожної
//  палітри перевіряємо, що добрані чорнила тримають WCAG 4.5:1. Це той
//  самий вимір, з якого рішення народилось (2026-08-20): фіксовані альфи
//  прототипу давали капшни 1.0–2.7:1. Тест — щоб нова палітра чи «дрібне
//  підправлення» альф не повернули проблему мовчки.
//

import XCTest
import SwiftUI
@testable import Embar

final class StickyInkTests: XCTestCase {

    /// Усі 75 кольорів стіків: 15 палітр × 5 слотів
    private var allStickyColors: [(String, Color)] {
        Palette.all.flatMap { palette in
            palette.sticky.enumerated().map { ("\(palette.slug)-\($0.offset + 1)", $0.element) }
        }
    }

    /// Контраст готового токена (кольору з альфою) проти кольору стіка:
    /// змішуємо так само, як це зробить екран
    private func ratio(of token: Color, on background: Color) throws -> Double {
        let bg = try XCTUnwrap(StickyInk.sRGB(of: background))
        let ns = try XCTUnwrap(NSColor(token).usingColorSpace(.sRGB))
        let fg: StickyInk.RGB = (ns.redComponent, ns.greenComponent, ns.blueComponent)
        let blended = StickyInk.blend(fg, over: bg, alpha: ns.alphaComponent)
        return StickyInk.contrast(blended, bg)
    }

    /// Головна гарантія: усі три рівні тексту читаються на будь-якому стіку
    func testAllPaletteColorsMeetWCAG() throws {
        for (name, color) in allStickyColors {
            let tokens = StickyInk.on(color)
            XCTAssertGreaterThanOrEqual(try ratio(of: tokens.ink, on: color), 4.5,
                                        "\(name): основний текст")
            XCTAssertGreaterThanOrEqual(try ratio(of: tokens.ink2, on: color), 4.5,
                                        "\(name): вторинний текст")
            XCTAssertGreaterThanOrEqual(try ratio(of: tokens.ink3, on: color), 4.5,
                                        "\(name): капшни")
        }
    }

    /// Ієрархія не ламається: основне чорнило не блідіше за вторинне,
    /// вторинне — за капшн
    func testHierarchyOrderPreserved() throws {
        for (name, color) in allStickyColors {
            let tokens = StickyInk.on(color)
            let a1 = try XCTUnwrap(NSColor(tokens.ink).usingColorSpace(.sRGB)).alphaComponent
            let a2 = try XCTUnwrap(NSColor(tokens.ink2).usingColorSpace(.sRGB)).alphaComponent
            let a3 = try XCTUnwrap(NSColor(tokens.ink3).usingColorSpace(.sRGB)).alphaComponent
            XCTAssertGreaterThanOrEqual(a1, a2, name)
            XCTAssertGreaterThanOrEqual(a2, a3, name)
        }
    }

    /// Пастельні стіки НЕ темніють без потреби: на найсвітлішому кремовому
    /// альфи лишаються біля прототипних мінімумів, а не стрибають до 1
    func testPastelKeepsPrototypeFeel() throws {
        let cream = Palette.bySlug("cream").sticky[0]
        let tokens = StickyInk.on(cream)
        let a3 = try XCTUnwrap(NSColor(tokens.ink3).usingColorSpace(.sRGB)).alphaComponent
        XCTAssertLessThanOrEqual(a3, 0.70,
            "на пастелі капшн має бути делікатним, а не майже чорним")
    }

    /// Єдиний темний стік (Ponyo-5) перевертає чорнило в біле
    func testDarkStickyFlipsToWhiteInk() throws {
        let ponyoDark = Palette.bySlug("ponyo").sticky[4]
        let tokens = StickyInk.on(ponyoDark)
        let ns = try XCTUnwrap(NSColor(tokens.ink).usingColorSpace(.sRGB))
        XCTAssertGreaterThan(ns.redComponent, 0.5, "чорнило має бути світлим")
    }
}
