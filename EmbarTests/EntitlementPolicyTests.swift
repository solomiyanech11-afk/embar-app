//
//  EntitlementPolicyTests.swift
//  EmbarTests
//
//  Політика доступу (SPEC §15.77): межі 14 днів, fail-open при збоях,
//  режим читання лише при явному «не pro», тристановий оверайд
//  пісочниці, мапінг відповідей RC (без мокання SDK - через
//  applyProStatus, куди зводиться і restore).
//

import XCTest
@testable import Embar

final class EntitlementPolicyTests: XCTestCase {

    private typealias Access = EntitlementStore.Access

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var day14: Date { start.addingTimeInterval(14 * 86_400) }

    private func access(afterDays days: Double,
                        cachedPro: Bool?) -> Access {
        EntitlementStore.computeAccess(
            trialStart: start, cachedPro: cachedPro,
            now: start.addingTimeInterval(days * 86_400))
    }

    override func setUp() {
        super.setUp()
        cleanKeys()
    }

    override func tearDown() {
        cleanKeys()
        super.tearDown()
    }

    private func cleanKeys() {
        let d = EmbarDefaults.store
        d.removeObject(forKey: EntitlementStore.cacheKey)
        d.removeObject(forKey: EntitlementStore.cacheSubscriptionKey)
        d.removeObject(forKey: EntitlementStore.sandboxOverrideKey)
        d.removeObject(forKey: TrialAnchor.fallbackKey)
    }

    // MARK: Межі trial

    func testTrialBoundaries() {
        XCTAssertEqual(access(afterDays: 0, cachedPro: nil), .trial(daysLeft: 14))
        XCTAssertEqual(access(afterDays: 0.5, cachedPro: nil), .trial(daysLeft: 14))
        XCTAssertEqual(access(afterDays: 13, cachedPro: nil), .trial(daysLeft: 1),
                       "13-й день - останній повний, лишився 1")
        XCTAssertEqual(access(afterDays: 13.9, cachedPro: nil), .trial(daysLeft: 1))
    }

    func testExpiryIsExactlyFourteenTimes86400Seconds() {
        // За секунду до межі - ще trial; рівно на межі - вже ні
        XCTAssertEqual(EntitlementStore.computeAccess(
            trialStart: start, cachedPro: false,
            now: day14.addingTimeInterval(-1)), .trial(daysLeft: 1))
        XCTAssertEqual(EntitlementStore.computeAccess(
            trialStart: start, cachedPro: false, now: day14), .readOnly)
        XCTAssertEqual(access(afterDays: 15, cachedPro: false), .readOnly)
    }

    // MARK: Fail-open

    func testNoAnchorAnywhereMeansOpen() {
        // Обидва рівні якоря мертві - не блокуємо, навіть якщо кеш
        // колись сказав «не pro»
        XCTAssertEqual(EntitlementStore.computeAccess(
            trialStart: nil, cachedPro: false, now: start), .open)
        XCTAssertEqual(EntitlementStore.computeAccess(
            trialStart: nil, cachedPro: nil, now: start), .open)
    }

    func testExpiredWithoutCacheIsOpen() {
        XCTAssertEqual(access(afterDays: 15, cachedPro: nil), .open,
                       "RC ще ніколи не відповідав - не замикаємо")
        XCTAssertEqual(access(afterDays: 400, cachedPro: nil), .open)
    }

    func testCachedProWinsAlways() {
        XCTAssertEqual(access(afterDays: 400, cachedPro: true), .pro)
        XCTAssertEqual(EntitlementStore.computeAccess(
            trialStart: nil, cachedPro: true, now: start), .pro)
    }

    func testClockRollbackClampsToFourteen() {
        let before = start.addingTimeInterval(-40 * 86_400)
        XCTAssertEqual(EntitlementStore.computeAccess(
            trialStart: start, cachedPro: nil, now: before),
            .trial(daysLeft: 14), "відкат годинника trial не подовжує")
    }

    // MARK: Оверайд пісочниці (тристановий)

    func testSandboxOverrideTriState() {
        let d = EmbarDefaults.store
        XCTAssertNil(EntitlementStore.effectiveCachedPro(defaults: d,
                                                         isSandbox: true),
                     "ключа немає = оверайду немає")
        d.set(1, forKey: EntitlementStore.sandboxOverrideKey)
        XCTAssertEqual(EntitlementStore.effectiveCachedPro(defaults: d,
                                                           isSandbox: true), true)
        d.set(0, forKey: EntitlementStore.sandboxOverrideKey)
        XCTAssertEqual(EntitlementStore.effectiveCachedPro(defaults: d,
                                                           isSandbox: true), false,
                       "0 = «кеш каже не pro» - єдиний шлях до readOnly в пісочниці")
    }

    func testOutsideSandboxOverrideIsIgnored() {
        let d = EmbarDefaults.store
        d.set(1, forKey: EntitlementStore.sandboxOverrideKey)
        XCTAssertNil(EntitlementStore.effectiveCachedPro(defaults: d,
                                                         isSandbox: false),
                     "поза пісочницею оверайд не читається взагалі")
    }

    // MARK: Мапінг відповідей RC (сюди зводиться і покупка, і restore)

    func testApplyProStatusUnlocksAndCaches() {
        let store = EntitlementStore()
        let keychain = MockKeychain()
        store.bootstrap(now: start, backing: keychain)
        let later = start.addingTimeInterval(20 * 86_400)

        store.applyProStatus(true, isSubscription: false, now: later)
        XCTAssertEqual(store.access, .pro)
        XCTAssertFalse(store.proIsSubscription, "lifetime - не підписка")
        XCTAssertEqual(EmbarDefaults.store.object(
            forKey: EntitlementStore.cacheKey) as? Bool, true,
            "статус закешовано - переживе офлайн")

        store.applyProStatus(true, isSubscription: true, now: later)
        XCTAssertTrue(store.proIsSubscription,
                      "місячна - показувати «Керувати підпискою»")

        // Підписка згасла: RC каже «не pro», trial давно минув
        store.applyProStatus(false, isSubscription: false, now: later)
        XCTAssertEqual(store.access, .readOnly)
        XCTAssertFalse(store.proIsSubscription)
        XCTAssertFalse(store.canCreate)
    }

    func testBootstrapWithDeadKeychainStillWorks() {
        let keychain = MockKeychain()
        keychain.failReads = true
        keychain.failWrites = true
        let store = EntitlementStore()
        store.bootstrap(now: start, backing: keychain)
        // Резерв у defaults урятував дату - trial іде, доступ є
        XCTAssertEqual(store.access, .trial(daysLeft: 14))
    }

    // MARK: Trial минає, поки програма живе (рецензія 2026-09-17, правка 1)

    func testTrialExpiresWhileAppLives() {
        let store = EntitlementStore()
        store.bootstrap(now: start, backing: MockKeychain())
        XCTAssertEqual(store.access, .trial(daysLeft: 14))
        // RC колись відповів «не pro» - без перезапуску це ніде не
        // перечитувалось, і людина сиділа в trial до релаунчу
        EmbarDefaults.store.set(false, forKey: EntitlementStore.cacheKey)

        store.recompute(now: start.addingTimeInterval(13 * 86_400))
        XCTAssertEqual(store.access, .trial(daysLeft: 1),
                       "пігулка «Лишилось 1 дн.» оновлюється без перезапуску")
        store.recompute(now: day14)
        XCTAssertEqual(store.access, .readOnly,
                       "рівно на межі, у живій сесії - режим читання")
    }

    func testClockTicksRecomputeAccess() {
        let store = EntitlementStore()
        store.bootstrap(now: .now, backing: MockKeychain())
        store.startClock()
        defer { store.stopClock() }
        XCTAssertEqual(store.access, .trial(daysLeft: 14))

        // Статус змінився «під ногами» (кеш RC каже pro) - кожен тик
        // часу мусить це підхопити без перезапуску
        EmbarDefaults.store.set(true, forKey: EntitlementStore.cacheKey)
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        XCTAssertEqual(store.access, .pro, "перехід доби перераховує стан")

        EmbarDefaults.store.set(false, forKey: EntitlementStore.cacheKey)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(store.access, .trial(daysLeft: 14),
                       "пробудження перераховує стан (trial ще йде)")

        EmbarDefaults.store.set(true, forKey: EntitlementStore.cacheKey)
        NotificationCenter.default.post(
            name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(store.access, .pro, "активація застосунку перераховує стан")

        XCTAssertEqual(EntitlementStore.clockInterval, 3_600,
                       "таймер - раз на годину")
    }
}
