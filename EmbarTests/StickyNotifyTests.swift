//
//  StickyNotifyTests.swift
//  EmbarTests
//
//  Зсув «нагадати за N хв до дедлайну». Округлення вниз використовує
//  міграція старих нагадувань — тихо промахнутись означало б відправити
//  сповіщення не тоді, коли людина просила.
//

import XCTest
@testable import Embar

final class StickyNotifyTests: XCTestCase {

    func testExactPresetsSurvive() {
        for preset in StickyNotify.presets {
            XCTAssertEqual(StickyNotify.snapDown(preset), preset)
        }
    }

    func testSnapsDownToNearestPreset() {
        XCTAssertEqual(StickyNotify.snapDown(45), 30, "45 хв → за 30 хв, не за годину")
        XCTAssertEqual(StickyNotify.snapDown(3), 0, "менше 5 хв → у момент")
        XCTAssertEqual(StickyNotify.snapDown(2000), 1440, "більше доби → за день")
        XCTAssertEqual(StickyNotify.snapDown(59), 30)
    }

    func testNonPositiveMeansAtTheMoment() {
        XCTAssertEqual(StickyNotify.snapDown(0), 0)
        XCTAssertEqual(StickyNotify.snapDown(-90), 0,
                       "нагадування пізніше за дедлайн — у момент дедлайну")
    }

    func testTriggerDateIsDeadlineMinusOffset() {
        let deadline = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(StickyNotify.triggerDate(deadline: deadline, offsetMinutes: 0),
                       deadline)
        XCTAssertEqual(StickyNotify.triggerDate(deadline: deadline, offsetMinutes: 30),
                       deadline.addingTimeInterval(-1800))
        XCTAssertEqual(StickyNotify.triggerDate(deadline: deadline, offsetMinutes: 1440),
                       deadline.addingTimeInterval(-86400))
    }

    // MARK: - Степер

    func testStepWalksThroughAllOptions() {
        var value: Int? = nil
        var seen: [Int?] = [value]
        for _ in 1...StickyNotify.presets.count {
            value = StickyNotify.step(from: value, by: 1)
            seen.append(value)
        }
        XCTAssertEqual(seen.map { $0 ?? -1 },
                       StickyNotify.ordered.map { $0 ?? -1 })
    }

    /// На краях степер стоїть на місці: «за день» не має ставати
    /// «не нагадувати» через перебір по колу
    func testStepStopsAtEdges() {
        XCTAssertNil(StickyNotify.step(from: nil, by: -1))
        XCTAssertEqual(StickyNotify.step(from: 1440, by: 1), 1440)
    }

    func testEveryPresetHasItsOwnLabel() {
        let labels = Set(StickyNotify.presets.map(StickyNotify.label(for:)))
        XCTAssertEqual(labels.count, StickyNotify.presets.count)
    }

    // MARK: - Недосяжні зсуви (ревʼю 2026-08-20)

    /// Дедлайн через дві години: «за день» — це вчора, такого варіанта
    /// просто нема
    func testUnreachableOffsetIsNotReachable() {
        let now = Date.now
        let deadline = now.addingTimeInterval(2 * 3600)

        XCTAssertTrue(StickyNotify.isReachable(60, deadline: deadline, now: now))
        XCTAssertFalse(StickyNotify.isReachable(1440, deadline: deadline, now: now))
        XCTAssertTrue(StickyNotify.isReachable(nil, deadline: deadline, now: now),
                      "«не нагадувати» доступне завжди")
        XCTAssertTrue(StickyNotify.isReachable(1440, deadline: nil, now: now),
                      "без дедлайну обмежувати нема від чого")
    }

    /// ❗ Сценарій зі скарги: «Сьогодні» о десятій ранку. Степер має
    /// зупинитись на останньому досяжному, а не дійти до «за день»
    func testStepStopsBeforeUnreachableOffset() {
        let now = Date.now
        let deadline = now.addingTimeInterval(2 * 3600) // за дві години

        // 60 хв ще попереду, 1440 — ні: далі ходу немає
        XCTAssertEqual(StickyNotify.step(from: 60, by: 1,
                                         deadline: deadline, now: now), 60)
        // а вниз завжди можна
        XCTAssertEqual(StickyNotify.step(from: 60, by: -1,
                                         deadline: deadline, now: now), 30)
    }

    /// Дедлайн через 10 хвилин: «за 5 хв» іще встигає, «за 30» вже ні —
    /// степер перестрибує недосяжне, а не спиняється мертво
    func testStepSkipsUnreachableAndKeepsWalking() {
        let now = Date.now
        let deadline = now.addingTimeInterval(10 * 60)

        XCTAssertEqual(StickyNotify.step(from: 0, by: 1,
                                         deadline: deadline, now: now), 5)
        XCTAssertEqual(StickyNotify.step(from: 5, by: 1,
                                         deadline: deadline, now: now), 5,
                       "далі все в минулому")
    }

    /// Дедлайн переїхав ближче — наявний зсув опускається до найближчого,
    /// що ще попереду
    func testNearestReachablePullsOffsetDown() {
        let now = Date.now
        let deadline = now.addingTimeInterval(2 * 3600)

        XCTAssertEqual(StickyNotify.nearestReachable(1440, deadline: deadline, now: now), 60)
        XCTAssertEqual(StickyNotify.nearestReachable(30, deadline: deadline, now: now), 30,
                       "досяжний зсув не чіпаємо")
        XCTAssertNil(StickyNotify.nearestReachable(nil, deadline: deadline, now: now))
    }

    /// Дедлайн уже минув — не буде навіть «у момент». Дзвіночка теж не
    /// має бути: краще без обіцянки, ніж із брехливою
    func testNearestReachableGivesUpWhenDeadlineIsPast() {
        let now = Date.now
        let deadline = now.addingTimeInterval(-60)

        XCTAssertNil(StickyNotify.nearestReachable(1440, deadline: deadline, now: now))
        XCTAssertNil(StickyNotify.nearestReachable(0, deadline: deadline, now: now))
    }
}
