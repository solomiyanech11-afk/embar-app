//
//  MaterialTokensTests.swift
//  EmbarTests
//
//  Токени матеріальності (DESIGN-DIRECTIONS §1). Найважливіше —
//  Opaque повертає СЬОГОДНІШНІ літерали байт-у-байт: ці тести
//  прибивають їх цвяхами.
//

import XCTest
@testable import Embar

final class MaterialTokensTests: XCTestCase {

    func testOpaqueReturnsTodaysConstants() {
        let tokens = MaterialTokens.resolve(theme: .opaque, glassOpacity: 0.3,
                                            reduceTransparency: false)
        XCTAssertEqual(tokens.theme, .opaque)
        XCTAssertEqual(tokens.panelBackingOpacity, 1.0)
        XCTAssertEqual(tokens.islandAlpha, 1.0)
        XCTAssertEqual(tokens.fadeMaxOpacity, 0.92)
        XCTAssertFalse(tokens.wantsBlurBacking)
        XCTAssertNil(tokens.islandShadow)
    }

    func testGlassRespectsSlider() {
        let tokens = MaterialTokens.resolve(theme: .glass, glassOpacity: 0.6,
                                            reduceTransparency: false)
        XCTAssertEqual(tokens.theme, .glass)
        XCTAssertEqual(tokens.panelBackingOpacity, 0.6)
        XCTAssertEqual(tokens.islandAlpha, 0.4)
        XCTAssertEqual(tokens.fadeMaxOpacity, 0.92 * 0.6, accuracy: 0.0001)
        XCTAssertTrue(tokens.wantsBlurBacking)
        XCTAssertNil(tokens.islandShadow)
    }

    func testGlassClampsSlider() {
        XCTAssertEqual(MaterialTokens.resolve(theme: .glass, glassOpacity: 1.7,
                                              reduceTransparency: false)
            .panelBackingOpacity, 1.0)
        XCTAssertEqual(MaterialTokens.resolve(theme: .glass, glassOpacity: -0.2,
                                              reduceTransparency: false)
            .panelBackingOpacity, 0)
    }

    func testLevitationForcesZeroBackingAndShadow() {
        let tokens = MaterialTokens.resolve(theme: .levitation, glassOpacity: 0.8,
                                            reduceTransparency: false)
        XCTAssertEqual(tokens.theme, .levitation)
        XCTAssertEqual(tokens.panelBackingOpacity, 0) // слайдер ігнорується
        XCTAssertEqual(tokens.islandAlpha, 0.4)
        XCTAssertEqual(tokens.fadeMaxOpacity, 0)
        XCTAssertFalse(tokens.wantsBlurBacking) // blur не потрібен: 0% молока
        XCTAssertEqual(tokens.islandShadow, .levitation)
    }

    func testReduceTransparencyForcesOpaqueFromAnyTheme() {
        for theme in MaterialTheme.allCases {
            let tokens = MaterialTokens.resolve(theme: theme, glassOpacity: 0.5,
                                                reduceTransparency: true)
            XCTAssertEqual(tokens, MaterialTokens.resolve(
                theme: .opaque, glassOpacity: 0.5, reduceTransparency: false),
                "\(theme) має опакнути під Reduce Transparency")
        }
    }
}

// MARK: - Палітра за замовчуванням

/// Новий користувач має отримати Cream (рішення 2026-08-09). Дефолт
/// тримався на тому, що літерал "cream" збігся в чотирьох файлах —
/// тепер це одна константа, і тест стереже саме її
final class DefaultPaletteTests: XCTestCase {

    func testDefaultPaletteIsCream() {
        XCTAssertEqual(Palette.defaultSlug, "cream")
        XCTAssertEqual(Palette.byDefault.slug, "cream")
        XCTAssertEqual(Palette.byDefault.name, "Cream")
    }

    /// Невідомий або порожній вибір теж падає в Cream, а не в те, що
    /// випадково стоїть першим у меню
    func testUnknownSlugFallsBackToDefault() {
        XCTAssertEqual(Palette.bySlug("").slug, Palette.defaultSlug)
        XCTAssertEqual(Palette.bySlug("no-such-palette").slug, Palette.defaultSlug)
    }
}

// MARK: - Міграція з вимкнених матеріалів (ревʼю 2026-08-12 №3)

final class MaterialMigrationTests: XCTestCase {

    private var saved: String?
    private let key = "materialTheme"

    override func setUp() {
        super.setUp()
        saved = EmbarDefaults.store.string(forKey: key)
    }

    override func tearDown() {
        if let saved { EmbarDefaults.store.set(saved, forKey: key) }
        else { EmbarDefaults.store.removeObject(forKey: key) }
        super.tearDown()
    }

    @MainActor func testGlassMigratesToOpaque() {
        EmbarDefaults.store.set(MaterialTheme.glass.rawValue, forKey: key)
        ThemeStore.migrateDisabledMaterialsIfNeeded()
        XCTAssertEqual(EmbarDefaults.store.string(forKey: key),
                       MaterialTheme.opaque.rawValue)
    }

    @MainActor func testLevitationMigratesToOpaque() {
        EmbarDefaults.store.set(MaterialTheme.levitation.rawValue, forKey: key)
        ThemeStore.migrateDisabledMaterialsIfNeeded()
        XCTAssertEqual(EmbarDefaults.store.string(forKey: key),
                       MaterialTheme.opaque.rawValue)
    }

    @MainActor func testOpaqueAndUnsetUntouched() {
        EmbarDefaults.store.set(MaterialTheme.opaque.rawValue, forKey: key)
        ThemeStore.migrateDisabledMaterialsIfNeeded()
        XCTAssertEqual(EmbarDefaults.store.string(forKey: key),
                       MaterialTheme.opaque.rawValue)

        EmbarDefaults.store.removeObject(forKey: key)
        ThemeStore.migrateDisabledMaterialsIfNeeded()
        XCTAssertNil(EmbarDefaults.store.string(forKey: key),
                     "відсутній ключ не мусить матеріалізуватись")
    }
}
