//
//  DesktopStickyLayoutTests.swift
//  EmbarTests
//
//  Матриця інваріанта розкладки віджета (SPEC §2.7, рефактор 2026-07-30):
//  targetSize — єдина функція правди про розмір вікна. Кожен тест —
//  шлях зміни геометрії × короткий/довгий текст.
//

import XCTest
@testable import Embar

final class DesktopStickyLayoutTests: XCTestCase {

    private typealias C = DesktopStickyController

    // MARK: - Авто-режим (без ручних override)

    func testShortTextAutoHugsBothDimensions() {
        // Короткий текст: вікно обіймає і ширину (ideal+24), і висоту
        let size = C.targetSize(naturalContentHeight: 90, idealTextWidth: 120,
                                manualWidth: nil, manualHeight: nil)
        XCTAssertEqual(size, NSSize(width: 144, height: 90))
    }

    func testTinyTextClampsToMinimums() {
        let size = C.targetSize(naturalContentHeight: 30, idealTextWidth: 40,
                                manualWidth: nil, manualHeight: nil)
        XCTAssertEqual(size, NSSize(width: C.minWidth, height: C.minHeight))
    }

    func testLongTextAutoCapsAtMaxHeight() {
        // Довгий текст: АВТО-ширина впирається у свою стелю (240 — вужчий,
        // росте в висоту), висота — у 420; ЛИШЕ тут показ має право на «…»
        let size = C.targetSize(naturalContentHeight: 900, idealTextWidth: 600,
                                manualWidth: nil, manualHeight: nil)
        XCTAssertEqual(size, NSSize(width: C.autoMaxWidth, height: C.maxHeight))
    }

    func testManualWidthMayExceedAutoCap() {
        // Ручний ресайз правим краєм дозволяє ширше за авто-стелю (до 380)
        let size = C.targetSize(naturalContentHeight: 200, idealTextWidth: 600,
                                manualWidth: 380, manualHeight: nil)
        XCTAssertEqual(size.width, C.maxWidth)
    }

    // MARK: - Ручна висота (низ/кут; шлях «розтягнути/стиснути»)

    func testManualHeightAboveNaturalIsRespected() {
        // Розтягнуте вікно над коротким текстом: порожнеча легальна,
        // бо текст ПОВНИЙ (обрізання в авто-зоні неможливе)
        let size = C.targetSize(naturalContentHeight: 90, idealTextWidth: 120,
                                manualWidth: nil, manualHeight: 300)
        XCTAssertEqual(size.height, 300)
    }

    func testManualHeightBelowNaturalGrowsBackToNatural() {
        // Стиснули нижче тексту → вікно повертається до природної:
        // «обрізаний текст над порожнечею» неможливий за побудовою
        let size = C.targetSize(naturalContentHeight: 200, idealTextWidth: 120,
                                manualWidth: nil, manualHeight: 100)
        XCTAssertEqual(size.height, 200)
    }

    func testManualHeightNeverExceedsMax() {
        let size = C.targetSize(naturalContentHeight: 90, idealTextWidth: 120,
                                manualWidth: nil, manualHeight: 999)
        XCTAssertEqual(size.height, C.maxHeight)
    }

    func testLongTextIgnoresSmallManualHeight() {
        // Довгий текст + колись зафіксована мала висота (сценарій
        // скріна 2026-07-30): виграє природна, обрізання лише на стелі
        let size = C.targetSize(naturalContentHeight: 900, idealTextWidth: 300,
                                manualWidth: nil, manualHeight: 150)
        XCTAssertEqual(size.height, C.maxHeight)
    }

    // MARK: - Ручна ширина (правий край) × авто-висота

    func testManualWidthKeepsAutoHeight() {
        // Звузили правий край: ширина ручна, висота йде за текстом
        let size = C.targetSize(naturalContentHeight: 250, idealTextWidth: 500,
                                manualWidth: 200, manualHeight: nil)
        XCTAssertEqual(size, NSSize(width: 200, height: 250))
    }

    func testManualWidthClamps() {
        XCTAssertEqual(C.targetSize(naturalContentHeight: 90, idealTextWidth: 0,
                                    manualWidth: 90, manualHeight: nil).width,
                       C.minWidth)
        XCTAssertEqual(C.targetSize(naturalContentHeight: 90, idealTextWidth: 0,
                                    manualWidth: 900, manualHeight: nil).width,
                       C.maxWidth)
    }

    // MARK: - Шляхи «шеврон/шрифт/редагування» = зміна природної висоти
    // при незмінних override: вікно слідує за нею монотонно

    func testNaturalGrowthMovesWindowExactly() {
        // Розгортання шеврона / більший кегль / набір тексту: природна
        // виросла — вікно рівно за нею (жодних застарілих бюджетів)
        let collapsed = C.targetSize(naturalContentHeight: 90, idealTextWidth: 200,
                                     manualWidth: nil, manualHeight: nil)
        let expanded = C.targetSize(naturalContentHeight: 240, idealTextWidth: 200,
                                    manualWidth: nil, manualHeight: nil)
        XCTAssertEqual(collapsed.height, 90)
        XCTAssertEqual(expanded.height, 240)
        XCTAssertEqual(collapsed.width, expanded.width) // ширина незалежна
    }

    func testShrinkingTextShrinksWindowUnlessManual() {
        // Стерли текст: авто-вікно тане; з ручною висотою — тримається
        let auto = C.targetSize(naturalContentHeight: 90, idealTextWidth: 100,
                                manualWidth: nil, manualHeight: nil)
        let manual = C.targetSize(naturalContentHeight: 90, idealTextWidth: 100,
                                  manualWidth: nil, manualHeight: 250)
        XCTAssertEqual(auto.height, 90)
        XCTAssertEqual(manual.height, 250)
    }
}
