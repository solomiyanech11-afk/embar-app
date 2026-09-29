//
//  PhotoCropTests.swift
//  EmbarTests
//
//  P2.27: кроп витягнутого фото. Бокс шита капнутий (0.45…1.4), і
//  вузька смужка показувала лише середину - і зберігала саме так.
//  Тепер зум-аут до цілого фото: NotePhotoCropSheet.cropRect на
//  мінімальному зумі мусить віддати ВСЕ фото, а рамка ніколи не
//  виходить за його межі.
//

import XCTest
@testable import Embar

final class PhotoCropTests: XCTestCase {

    /// Смужка 3000×300 у капнутому боксі 300×135 (аспект 0.45)
    private let strip = CGSize(width: 3000, height: 300)
    private let cappedBox = CGSize(width: 300, height: 135)

    /// contain/cover для цих розмірів: (300/3000)/(135/300) = 0.1/0.45
    private var stripMinZoom: CGFloat { 0.1 / 0.45 }

    func testMinZoomYieldsWholeStrip() {
        let rect = NotePhotoCropSheet.cropRect(
            imageSize: strip, box: cappedBox,
            zoom: stripMinZoom, offset: .zero)
        XCTAssertEqual(rect, CGRect(origin: .zero, size: strip),
                       "на мінімальному зумі зберігається ЦІЛЕ фото")
    }

    func testDefaultZoomCropsMiddleWithinBounds() {
        let rect = NotePhotoCropSheet.cropRect(
            imageSize: strip, box: cappedBox, zoom: 1, offset: .zero)
        XCTAssertEqual(rect.height, strip.height, accuracy: 0.5)
        XCTAssertLessThan(rect.width, strip.width)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertLessThanOrEqual(rect.maxX, strip.width)
        // Без зсуву - рівно середина
        XCTAssertEqual(rect.midX, strip.width / 2, accuracy: 0.5)
    }

    func testExtremeOffsetStaysWithinImage() {
        for dx in [-10_000.0, 10_000.0] {
            let rect = NotePhotoCropSheet.cropRect(
                imageSize: strip, box: cappedBox, zoom: 1.7,
                offset: CGSize(width: dx, height: -10_000))
            XCTAssertGreaterThanOrEqual(rect.minX, 0)
            XCTAssertGreaterThanOrEqual(rect.minY, 0)
            XCTAssertLessThanOrEqual(rect.maxX, strip.width + 0.5)
            XCTAssertLessThanOrEqual(rect.maxY, strip.height + 0.5)
        }
    }

    /// Високий скріншот, капнутий бокс 1.4 - дзеркальний випадок
    func testMinZoomYieldsWholeTallPhoto() {
        let tall = CGSize(width: 300, height: 3000)
        let box = CGSize(width: 300, height: 420) // аспект 1.4
        // cover = 300/300 = 1, contain = 420/3000 = 0.14
        let rect = NotePhotoCropSheet.cropRect(
            imageSize: tall, box: box, zoom: 0.14, offset: .zero)
        // Порівняння з допуском: 0.14 не представляється точно в double
        XCTAssertEqual(rect.minX, 0, accuracy: 0.01)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.01)
        XCTAssertEqual(rect.width, tall.width, accuracy: 0.01)
        XCTAssertEqual(rect.height, tall.height, accuracy: 0.01)
    }

    /// Шлях нотаток (зум від 1) - поведінка як була: рамка в межах фото,
    /// покриває бокс без пустих полів
    func testNotesSlotCropUnchanged() {
        let photo = CGSize(width: 1200, height: 900)
        let box = CGSize(width: 300, height: 300 * 0.62)
        let rect = NotePhotoCropSheet.cropRect(
            imageSize: photo, box: box, zoom: 1, offset: .zero)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, photo.width)
        XCTAssertLessThanOrEqual(rect.maxY, photo.height)
        // Пропорція результату = пропорція бокса (слот повністю покритий)
        XCTAssertEqual(rect.height / rect.width, box.height / box.width,
                       accuracy: 0.01)
    }
}
