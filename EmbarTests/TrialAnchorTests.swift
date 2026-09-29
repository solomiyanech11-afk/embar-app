//
//  TrialAnchorTests.swift
//  EmbarTests
//
//  Якір trial (SPEC §15.77в): два рівні зберігання, порядок читання
//  Keychain → defaults → nil, self-heal і поведінка при збоях.
//
//  Справжній Keychain у тестах НЕ чіпаємо ніколи: хост-застосунок - це
//  Embar, і його data-protection keychain спільний з реальним профілем.
//  Уся спинка тут - мок із керованими збоями.
//

import XCTest
@testable import Embar

/// Keychain у памʼяті з вимикачами збоїв (спільний для тестів монетизації)
final class MockKeychain: KeychainBacking {
    // Правило CLAUDE.md: явний deinit, інакше синтезований ІЗОЛЬОВАНИЙ
    // deinit псує купу при звільненні в Task (у тестах теж - краш
    // «pointer being freed was not allocated» відтворився тут 2026-09-16)
    nonisolated deinit {}

    var storage: [String: Data] = [:]
    var failReads = false
    var failWrites = false

    private func key(_ service: String, _ account: String) -> String {
        service + "|" + account
    }

    func read(service: String, account: String) -> (data: Data?, status: OSStatus) {
        if failReads { return (nil, errSecInternalComponent) }
        guard let data = storage[key(service, account)] else {
            return (nil, errSecItemNotFound)
        }
        return (data, errSecSuccess)
    }

    func write(_ data: Data, service: String, account: String) -> OSStatus {
        if failWrites { return errSecInternalComponent }
        storage[key(service, account)] = data
        return errSecSuccess
    }

    func delete(service: String, account: String) -> OSStatus {
        guard storage.removeValue(forKey: key(service, account)) != nil else {
            return errSecItemNotFound
        }
        return errSecSuccess
    }

    /// Дата, що реально лежить у моку (для звірки)
    var storedDate: Date? {
        guard let data = storage.values.first,
              let text = String(data: data, encoding: .utf8),
              let interval = Double(text) else { return nil }
        return Date(timeIntervalSinceReferenceDate: interval)
    }
}

final class TrialAnchorTests: XCTestCase {

    private var keychain = MockKeychain()
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUp() {
        super.setUp()
        keychain = MockKeychain()
        EmbarDefaults.store.removeObject(forKey: TrialAnchor.fallbackKey)
    }

    override func tearDown() {
        EmbarDefaults.store.removeObject(forKey: TrialAnchor.fallbackKey)
        super.tearDown()
    }

    private func readAnchor(now: Date? = nil) -> Date? {
        TrialAnchor.readOrEstablish(now: now ?? self.now, backing: keychain)
    }

    // MARK: Перший запуск

    func testFirstReadEstablishesNowInBothLevels() {
        XCTAssertEqual(readAnchor(), now, "перше читання має повернути «зараз»")
        XCTAssertEqual(keychain.storedDate, now, "дата має лягти в Keychain")
        XCTAssertEqual(EmbarDefaults.store.object(forKey: TrialAnchor.fallbackKey) as? Double,
                       now.timeIntervalSinceReferenceDate,
                       "дата має лягти і в резерв")
    }

    func testSecondReadReturnsSameDate() {
        _ = readAnchor()
        let later = now.addingTimeInterval(3 * 86_400)
        XCTAssertEqual(readAnchor(now: later), now,
                       "повторне читання не пересуває якір")
    }

    // MARK: Збої Keychain

    func testKeychainWriteFailureStillEstablishesViaFallback() {
        keychain.failWrites = true
        XCTAssertEqual(readAnchor(), now,
                       "збій запису в Keychain не блокує: резерв тримає дату")
        XCTAssertNil(keychain.storedDate)
        // І наступне читання бачить ту саму дату через резерв
        keychain.failWrites = false
        XCTAssertEqual(readAnchor(now: now.addingTimeInterval(86_400)), now)
    }

    func testKeychainDownFallbackAliveReturnsFallbackAndHeals() {
        _ = readAnchor()                      // якір у двох рівнях
        keychain.storage.removeAll()          // Keychain «загубив» item
        keychain.failReads = true
        let later = now.addingTimeInterval(86_400)
        XCTAssertEqual(readAnchor(now: later), now,
                       "резерв рятує дату, а не починає trial заново")
        XCTAssertEqual(keychain.storedDate, now,
                       "self-heal: дата долита назад у Keychain")
    }

    func testKeychainAliveFallbackLostHealsFallback() {
        _ = readAnchor()
        EmbarDefaults.store.removeObject(forKey: TrialAnchor.fallbackKey)
        XCTAssertEqual(readAnchor(now: now.addingTimeInterval(86_400)), now,
                       "Keychain - головне джерело")
        XCTAssertEqual(EmbarDefaults.store.object(forKey: TrialAnchor.fallbackKey) as? Double,
                       now.timeIntervalSinceReferenceDate,
                       "self-heal: резерв долито з Keychain")
    }

    // MARK: Дебаг-команди поза пісочницею - no-op

    func testDebugCommandsRefuseOutsideSandbox() {
        _ = readAnchor()
        XCTAssertFalse(TrialAnchor.shift(byDays: 15, backing: keychain),
                       "shift поза пісочницею має відмовити")
        XCTAssertFalse(TrialAnchor.reset(backing: keychain),
                       "reset поза пісочницею має відмовити")
        XCTAssertEqual(keychain.storedDate, now, "дата неторкана")
    }
}
