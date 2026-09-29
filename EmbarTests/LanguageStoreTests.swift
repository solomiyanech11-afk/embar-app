//
//  LanguageStoreTests.swift
//  EmbarTests
//
//  Перемикач мови в Settings (SPEC §6.4).
//
//  Тести чіпають реальний UserDefaults (іншого джерела для AppleLanguages
//  не існує), тому setUp запамʼятовує вихідний стан, а tearDown повертає
//  його точно — інакше прогін тестів змінив би мову застосунку авторці.
//

import XCTest
@testable import Embar

final class LanguageStoreTests: XCTestCase {

    private let appleLanguages = "AppleLanguages"
    private let choiceKey = "appLanguage"

    private var savedChoice: String?
    private var savedLanguages: Any?

    override func setUp() {
        super.setUp()
        // Під тестами store - окремий суїт (ревʼю №6), тож і знімок,
        // і прибирання ходять у нього ж
        let domain = UserDefaults.standard
            .persistentDomain(forName: EmbarDefaults.testSuiteName) ?? [:]
        savedChoice = domain[choiceKey] as? String
        savedLanguages = domain[appleLanguages]
    }

    override func tearDown() {
        let defaults = EmbarDefaults.store
        if let savedChoice { defaults.set(savedChoice, forKey: choiceKey) }
        else { defaults.removeObject(forKey: choiceKey) }
        if let savedLanguages { defaults.set(savedLanguages, forKey: appleLanguages) }
        else { defaults.removeObject(forKey: appleLanguages) }
        super.tearDown()
    }

    private var bundleID: String { Bundle.main.bundleIdentifier ?? "nechai.Embar" }

    /// Що реально лежить у ВЛАСНОМУ домені (object(forKey:) зливає всі
    /// домени й завжди щось повертає, тож override з нього не видно)
    private var overrideInAppDomain: [String]? {
        UserDefaults.standard
            .persistentDomain(forName: EmbarDefaults.testSuiteName)?[appleLanguages] as? [String]
    }

    // MARK: - Вибір

    func testExplicitLanguageWritesOverride() {
        LanguageStore.selected = .en
        XCTAssertEqual(LanguageStore.selected, .en)
        XCTAssertEqual(overrideInAppDomain, ["en"])

        LanguageStore.selected = .uk
        XCTAssertEqual(LanguageStore.selected, .uk)
        XCTAssertEqual(overrideInAppDomain, ["uk"])
    }

    /// «Як у системі» ПРИБИРАЄ override, а не копіює поточну мову —
    /// інакше застосунок застряг би на ній назавжди
    func testSystemRemovesOverride() {
        LanguageStore.selected = .en
        XCTAssertNotNil(overrideInAppDomain)

        LanguageStore.selected = .system
        XCTAssertEqual(LanguageStore.selected, .system)
        XCTAssertNil(overrideInAppDomain)
    }

    /// Туди-назад-туди не лишає сміття і не плутає стан
    func testRoundTripIsStable() {
        for language in [AppLanguage.en, .uk, .system, .uk, .en, .system] {
            LanguageStore.selected = language
            XCTAssertEqual(LanguageStore.selected, language)
            XCTAssertEqual(overrideInAppDomain, language.code.map { [$0] })
        }
    }

    /// Без жодного запису — дефолт «як у системі»
    func testDefaultIsSystem() {
        EmbarDefaults.store.removeObject(forKey: choiceKey)
        XCTAssertEqual(LanguageStore.selected, .system)
    }

    // MARK: - Код мови

    func testCodeMapping() {
        XCTAssertNil(AppLanguage.system.code)
        XCTAssertEqual(AppLanguage.uk.code, "uk")
        XCTAssertEqual(AppLanguage.en.code, "en")
    }

    func testResolvedCodeForExplicitLanguages() {
        XCTAssertEqual(LanguageStore.resolvedCode(for: .uk), "uk")
        XCTAssertEqual(LanguageStore.resolvedCode(for: .en), "en")
    }

    /// «Як у системі» завжди дає одну з мов, які застосунок реально містить
    func testResolvedSystemCodeIsSupported() {
        XCTAssertTrue(LanguageStore.supported.contains(
            LanguageStore.resolvedCode(for: .system)))
    }

    /// Вибір мови, якою застосунок уже працює, перезапуску не потребує
    func testSameLanguageNeedsNoRestart() {
        let active = LanguageStore.activeCode
        let sameLanguage = AppLanguage(rawValue: active) ?? .uk
        XCTAssertFalse(LanguageStore.changesLanguage(to: sameLanguage))
    }

    func testOtherLanguageNeedsRestart() {
        let active = LanguageStore.activeCode
        let other: AppLanguage = active == "uk" ? .en : .uk
        XCTAssertTrue(LanguageStore.changesLanguage(to: other))
    }
}
