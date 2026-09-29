//
//  PaywallOfflineTests.swift
//  EmbarTests
//
//  Краш у пісочниці (2026-09-17): «Відновити покупки» ішло в
//  Purchases.shared без configure - fatalError. Тут RC теж НЕ
//  сконфігурований (AppDelegate під XCTest бейлиться), тож ці тести
//  живуть у тих самих умовах, що пісочниця: кожне звернення до
//  RevenueCat мусить бути за Purchases.isConfigured і давати офлайн-
//  стан, а не падіння.
//
//  Модель отримує in-memory контекст: sharedModelContainer під тестами -
//  це РЕАЛЬНА база користувача, її не торкаємось.
//

import RevenueCat
import SwiftData
import XCTest
@testable import Embar

final class PaywallOfflineTests: XCTestCase {

    private func makeModel() throws -> PaywallModel {
        let container = try ModelContainer(
            for: EmbarApp.schema,
            configurations: ModelConfiguration(schema: EmbarApp.schema,
                                               isStoredInMemoryOnly: true))
        return PaywallModel(context: container.mainContext)
    }

    func testPreconditionRevenueCatIsNotConfiguredInTests() {
        XCTAssertFalse(Purchases.isConfigured,
                       "тести мають бігати без RC - інакше вони нічого не доводять")
    }

    func testLoadWithoutRevenueCatIsOffline() async throws {
        let model = try makeModel()
        await model.load()
        XCTAssertEqual(model.phase, .offline)
    }

    /// Саме цей шлях крашив пісочницю
    func testRestoreWithoutRevenueCatIsOfflineNotCrash() async throws {
        let model = try makeModel()
        await model.load()
        await model.restore()
        XCTAssertEqual(model.phase, .offline, "restore без RC - офлайн-стан, не fatalError")
        XCTAssertFalse(model.waitIsSlow)
    }

    /// Restore доступний і поки ціни ще їдуть (рецензія 2026-09-17,
    /// правка 5): без load() фаза .loading, і restore не має мовчати
    func testRestoreIsAllowedWhileLoading() async throws {
        let model = try makeModel()
        XCTAssertEqual(model.phase, .loading)
        await model.restore()
        XCTAssertEqual(model.phase, .offline,
                       "restore у .loading пройшов до RC-гарда, а не впав у guard фази")
    }

    /// Текст тосту «нічого відновлювати» - обома мовами в каталозі
    func testNothingToRestoreTextIsLocalized() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Embar/Localizable.xcstrings")
        let text = try String(contentsOf: catalog, encoding: .utf8)
        XCTAssertTrue(text.contains("\"Покупок для цього Apple ID не знайдено\""))
        XCTAssertTrue(text.contains("No purchases found for this Apple ID"))
    }

    // MARK: - Source-scan: кожен файл із Purchases.shared має перевірку

    private var monetizationSources: [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Embar")
        return [root.appendingPathComponent("Features/Paywall"),
                root.appendingPathComponent("Monetization")].flatMap { folder in
            (FileManager.default.enumerator(at: folder,
                                            includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }) ?? []
        }
    }

    /// Файлова гранулярність, як у DebugGuardTests: звернення до
    /// Purchases.shared без Purchases.isConfigured у тому ж файлі -
    /// кандидат на той самий краш
    func testEveryPurchasesSharedUseIsGuarded() throws {
        var offenders: [String] = []
        for file in monetizationSources {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains("Purchases.shared") else { continue }
            if !text.contains("Purchases.isConfigured") {
                offenders.append(file.lastPathComponent)
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Purchases.shared без перевірки Purchases.isConfigured у файлі: \
            \(offenders). Без configure це fatalError (пісочниця, тести).
            """)
    }
}
