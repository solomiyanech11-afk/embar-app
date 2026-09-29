//
//  PanelFocusTests.swift
//  EmbarTests
//
//  P2.24: без select-all при програмному фокусі. Правило живе в
//  EmbarPanel.makeFirstResponder - єдиному вузлі, через який проходить
//  здобуття фокуса БУДЬ-ЯКИМ field editor (SwiftUI-поля приносять
//  власний _SystemTextFieldFieldEditor і обходять
//  windowWillReturnFieldEditor - SPEC §15.72, траса [P224] 2026-09-03).
//

import XCTest
import AppKit
@testable import Embar

@MainActor
final class PanelFocusTests: XCTestCase {

    // MARK: - Правило collapsedInitialSelection (чиста функція)

    private let full = NSRange(location: 0, length: 10)

    /// Програмний фокус (@FocusState, відновлення сесії, фолбек
    /// «сироти»): select-all згортається в каретку в кінці
    func testProgrammaticFocusCollapses() {
        let result = EmbarPanel.collapsedInitialSelection(
            current: full, textLength: 10,
            isTabKey: false, recentMultiClick: false)
        XCTAssertEqual(result, NSRange(location: 10, length: 0))
    }

    /// Умова 2: Tab у поле - системний select-all лишається
    func testTabKeepsSelectAll() {
        let result = EmbarPanel.collapsedInitialSelection(
            current: full, textLength: 10,
            isTabKey: true, recentMultiClick: false)
        XCTAssertNil(result, "Tab-фокус не чіпаємо")
    }

    /// Умова 2: подвійний клік (rename теми) - «виділити для заміни»
    func testDoubleClickKeepsSelectAll() {
        let result = EmbarPanel.collapsedInitialSelection(
            current: full, textLength: 10,
            isTabKey: false, recentMultiClick: true)
        XCTAssertNil(result, "select-all після подвійного кліку лишається")
    }

    /// Часткове виділення - не початковий select-all, не чіпаємо
    func testPartialSelectionUntouched() {
        let result = EmbarPanel.collapsedInitialSelection(
            current: NSRange(location: 2, length: 3), textLength: 10,
            isTabKey: false, recentMultiClick: false)
        XCTAssertNil(result)
    }

    /// Порожнє поле - нічого згортати
    func testEmptyTextUntouched() {
        let result = EmbarPanel.collapsedInitialSelection(
            current: NSRange(location: 0, length: 0), textLength: 0,
            isTabKey: false, recentMultiClick: false)
        XCTAssertNil(result)
    }

    /// Каретка (нульове виділення) у непорожньому тексті - не чіпаємо
    func testCaretUntouched() {
        let result = EmbarPanel.collapsedInitialSelection(
            current: NSRange(location: 4, length: 0), textLength: 10,
            isTabKey: false, recentMultiClick: false)
        XCTAssertNil(result)
    }

    // MARK: - Інтеграція: справжня панель + поле з текстом

    /// Програмний фокус поля в EmbarPanel закінчується кареткою в кінці,
    /// а не червоним select-all - у тому ж циклі подій, без жодного
    /// кадру з виділенням
    func testPanelCollapsesSelectAllOnProgrammaticFocus() {
        let panel = EmbarPanel(
            contentRect: NSRect(x: -2000, y: 0, width: 320, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        defer { panel.orderOut(nil) }

        let text = "текст, який раніше мигав червоним"
        let field = NSTextField(string: text)
        field.frame = NSRect(x: 10, y: 40, width: 300, height: 24)
        panel.contentView?.addSubview(field)
        panel.makeKeyAndOrderFront(nil)

        panel.makeFirstResponder(field)

        let editor = panel.firstResponder as? NSTextView
        XCTAssertNotNil(editor, "поле мав редагувати field editor")
        XCTAssertEqual(editor?.isFieldEditor, true)
        let selection = editor?.selectedRange() ?? NSRange()
        XCTAssertEqual(selection.length, 0,
                       "програмний фокус не має лишати select-all")
        XCTAssertEqual(selection.location, (text as NSString).length,
                       "каретка стає в кінець тексту")
    }
}
