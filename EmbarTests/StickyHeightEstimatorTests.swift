//
//  StickyHeightEstimatorTests.swift
//  EmbarTests
//
//  Кеш оцінок висоти стіків (ревʼю 2026-08-18, знахідка 6).
//
//  Історія: ключем був рядок «бакет|повний текст стіка», виселення не
//  було взагалі. Кожне натискання клавіші в розгорнутому стіку і кожен
//  новий бакет ширини додавали ПОСТІЙНИЙ запис — на стрес-стіні сесія
//  тримала другу копію всього корпусу текстів до кінця життя панелі.
//
//  Тест тримає обидві половини домовленості: кеш не росте від друку і
//  ресайзу, але оцінка на змінений текст усе одно свіжа.
//

import XCTest
import SwiftData
@testable import Embar

@MainActor
final class StickyHeightEstimatorTests: XCTestCase {

    private let colWidth: CGFloat = 164   // половина стіни 360pt

    /// Контейнер тримаємо полем: @Model-обʼєкт поза контекстом валить
    /// процес при звільненні (той самий урок, що в OnboardingSeederTests)
    private var container: ModelContainer?

    private func makeSticker(_ text: String) throws -> Sticker {
        let context: ModelContext
        if let container {
            context = container.mainContext
        } else {
            let fresh = try ModelContainer(
                for: EmbarApp.schema,
                configurations: ModelConfiguration(schema: EmbarApp.schema,
                                                   isStoredInMemoryOnly: true))
            container = fresh
            context = fresh.mainContext
        }
        let sticker = Sticker(text: text)
        context.insert(sticker)
        return sticker
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    /// ⚠️ Кеш свідомо НЕ звільняємо. У проєкті ввімкнено
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, тож кожен клас
    /// MainActor-ізольований, і його deinit іде через back-deploy-шим
    /// (`swift_task_deinitOnExecutorMainActorBackDeploy`). Під тест-хостом
    /// цей шлях валить процес (Signal 6, malloc: pointer being freed was
    /// not allocated) — перевірено і на коді ДО цієї правки, тобто до
    /// самого кеша воно стосунку не має. У застосунку кеш живе стільки ж,
    /// скільки панель, і не звільняється ніколи; тут тримаємо його так
    /// само - ціна кілька байтів на прогін
    private func makeEstimator() -> StickyHeightEstimator {
        let estimator = StickyHeightEstimator()
        _ = Unmanaged.passRetained(estimator)
        return estimator
    }

    func testTypingDoesNotGrowTheCache() throws {
        let estimator = makeEstimator()
        let sticker = try makeSticker("")
        // Друк «по символу», як біндинг $sticker.text у розгорнутому стіку
        for character in "думка, яка росте по літері за раз" {
            sticker.text.append(character)
            _ = estimator.height(for: sticker, colWidth: colWidth)
        }
        XCTAssertEqual(estimator.cachedCount, 1,
                       "на стік має лишатись рівно один запис, а не по запису на символ")
    }

    func testResizeDoesNotGrowTheCache() throws {
        let estimator = makeEstimator()
        let sticker = try makeSticker("текст, який доведеться перемірювати")
        // Ресайз панелі 320…480pt — це десяток бакетів по 16pt
        for width in stride(from: CGFloat(150), through: 240, by: 1) {
            _ = estimator.height(for: sticker, colWidth: width)
        }
        XCTAssertEqual(estimator.cachedCount, 1)
    }

    func testCacheIsPerSticker() throws {
        let estimator = makeEstimator()
        let first = try makeSticker("перший")
        let second = try makeSticker("другий")
        _ = estimator.height(for: first, colWidth: colWidth)
        _ = estimator.height(for: second, colWidth: colWidth)
        XCTAssertEqual(estimator.cachedCount, 2)
    }

    /// Свіжість важливіша за економію: змінений текст мусить дати нову
    /// оцінку, інакше колонки роз'їдуться
    func testLongerTextIsTallerAfterEdit() throws {
        let estimator = makeEstimator()
        let sticker = try makeSticker("короткий")
        let short = estimator.height(for: sticker, colWidth: colWidth)
        sticker.text = String(repeating: "довгий текст на багато рядків. ", count: 6)
        let long = estimator.height(for: sticker, colWidth: colWidth)
        XCTAssertGreaterThan(long, short)
    }

    /// Вужча колонка = більше рядків = вища картка (перевірка, що бакет
    /// ширини теж інвалідовує запис)
    func testNarrowerColumnIsTaller() throws {
        let estimator = makeEstimator()
        let sticker = try makeSticker(String(repeating: "слово ", count: 30))
        let wide = estimator.height(for: sticker, colWidth: 240)
        let narrow = estimator.height(for: sticker, colWidth: 120)
        XCTAssertGreaterThan(narrow, wide)
    }

    func testNeverBelowCardMinimum() throws {
        let estimator = makeEstimator()
        XCTAssertGreaterThanOrEqual(
            estimator.height(for: try makeSticker(""), colWidth: colWidth), 80)
    }
}
