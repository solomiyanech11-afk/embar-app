//
//  ReaderShelfLayoutTests.swift
//  EmbarTests
//
//  Групування полиці (SPEC §4.1): дзеркалить цикл прототипу
//  renderReaderShelf — залишок 1 → full, 2 → пара, інакше тріо;
//  сторона tall чергується парністю групи.
//

import XCTest
@testable import Embar

final class ReaderShelfLayoutTests: XCTestCase {

    func testEmptyShelf() {
        XCTAssertEqual(ReaderShelfLayout.groups(count: 0), [])
    }

    func testSingleBookIsFullWidth() {
        XCTAssertEqual(ReaderShelfLayout.groups(count: 1), [.full(0)])
    }

    func testTwoBooksArePair() {
        XCTAssertEqual(ReaderShelfLayout.groups(count: 2),
                       [.pair(tall: 0, square: 1, tallLeft: true)])
    }

    func testThreeBooksAreTrio() {
        XCTAssertEqual(ReaderShelfLayout.groups(count: 3),
                       [.trio(tall: 0, squares: [1, 2], tallLeft: true)])
    }

    func testFourBooksTrioPlusFull() {
        XCTAssertEqual(ReaderShelfLayout.groups(count: 4),
                       [.trio(tall: 0, squares: [1, 2], tallLeft: true),
                        .full(3)])
    }

    func testFiveBooksTrioPlusPairOnRight() {
        XCTAssertEqual(ReaderShelfLayout.groups(count: 5),
                       [.trio(tall: 0, squares: [1, 2], tallLeft: true),
                        .pair(tall: 3, square: 4, tallLeft: false)])
    }

    func testSevenBooksAlternateAndEndFull() {
        XCTAssertEqual(ReaderShelfLayout.groups(count: 7),
                       [.trio(tall: 0, squares: [1, 2], tallLeft: true),
                        .trio(tall: 3, squares: [4, 5], tallLeft: false),
                        .full(6)])
    }

    func testTallSideAlternatesAcrossTrios() {
        let groups = ReaderShelfLayout.groups(count: 9)
        XCTAssertEqual(groups,
                       [.trio(tall: 0, squares: [1, 2], tallLeft: true),
                        .trio(tall: 3, squares: [4, 5], tallLeft: false),
                        .trio(tall: 6, squares: [7, 8], tallLeft: true)])
    }
}
