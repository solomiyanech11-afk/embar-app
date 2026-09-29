//
//  DesktopStickyClampTests.swift
//  EmbarTests
//
//  Clamp-геометрія стіка-віджета (SPEC §2.7): після зміни моніторів рамка
//  лишається, якщо хоч 20pt видно на будь-якому екрані; повністю
//  невидима — притискається в межі fallback-екрана.
//

import XCTest
@testable import Embar

final class DesktopStickyClampTests: XCTestCase {

    private let main = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let widget = NSRect(x: 100, y: 100, width: 230, height: 96)

    func testVisibleFrameUntouched() {
        let result = DesktopStickyController.clampedFrame(
            widget, visible: [main], fallback: main)
        XCTAssertEqual(result, widget)
    }

    func testPartiallyVisibleFrameUntouched() {
        // Половина за правим краєм, але > 20pt видно — не чіпаємо
        let half = NSRect(x: main.maxX - 115, y: 100, width: 230, height: 96)
        let result = DesktopStickyController.clampedFrame(
            half, visible: [main], fallback: main)
        XCTAssertEqual(result, half)
    }

    func testOffscreenSnapsBackInsideFallback() {
        // Був на другому моніторі праворуч — монітор знято
        let orphan = NSRect(x: 2000, y: 300, width: 230, height: 96)
        let result = DesktopStickyController.clampedFrame(
            orphan, visible: [main], fallback: main)
        XCTAssertTrue(main.contains(result))
        XCTAssertEqual(result.size, orphan.size) // розмір не змінюється
    }

    func testBarelyVisibleSliverSnapsBack() {
        // Видно менше 20pt (поріг mustSee) — вважаємо загубленим
        let sliver = NSRect(x: main.maxX - 10, y: 100, width: 230, height: 96)
        let result = DesktopStickyController.clampedFrame(
            sliver, visible: [main], fallback: main)
        XCTAssertTrue(main.contains(result))
    }

    func testSecondScreenKeepsFrame() {
        // Віджет на другому моніторі, який ДОСІ підключений
        let second = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        let onSecond = NSRect(x: 1600, y: 300, width: 230, height: 96)
        let result = DesktopStickyController.clampedFrame(
            onSecond, visible: [main, second], fallback: main)
        XCTAssertEqual(result, onSecond)
    }
}
