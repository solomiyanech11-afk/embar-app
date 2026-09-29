//
//  LazyStateResurrectionTests.swift
//  EmbarTests
//
//  Виконуваний доказ пастки SwiftUI зі SPEC §15.65 (F3, 2026-08-28):
//  лінивий контейнер (LazyVStack) кешує сховище @State рядка за його id
//  і НЕ викидає його, коли рядок зникає з даних. Коли той самий id
//  повертається в той самий контейнер, «новий» рядок народжується з
//  воскреслим старим станом. Саме так стік ставав невидимим: @State
//  fadingOut картки переживав переїзд у «Виконані» і повертався разом
//  зі стіком.
//
//  Два контрольні заміри тримають діагноз точним:
//  · звичайний VStack стан НЕ воскрешає (це кеш саме лінивого контейнера);
//  · інша колонка — окремий контейнер зі своїм кешем (тому F3 ловив
//    лише «частину стіків» — тих, кого greedy-розкладка повертала в ту
//    саму колонку).
//
//  ❗ Якщо testLazyColumnResurrectsRowState упав — Apple змінила
//  поведінку лінивих контейнерів; запобіжники §15.65 (зовнішнє джерело
//  правди для розчинення, скидання ховера в onAppear) можна переглянути.
//

import XCTest
import SwiftUI
import Combine
@testable import Embar

private let setFlagNote = Notification.Name("LazyStateResurrectionTests.setFlag")

/// Журнал появ карток: що лежало в @State на момент onAppear
private final class AppearLog {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    struct Entry: Equatable {
        let id: Int
        let done: Bool
        let flag: Bool
    }
    var entries: [Entry] = []
}

private struct Item: Identifiable, Equatable {
    let id: Int
    var done: Bool
}

private final class ListModel: ObservableObject {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    @Published var items: [Item] = (0..<6).map { Item(id: $0, done: false) }
    /// Крок 3 сценарію вже відбувся (для swapColumnOnReturn)
    var returned = false
}

/// Мінімальний «StickyCard»: власний @State, який стає недефолтним
/// якраз перед тим, як рядок зникає з даних
private struct Card: View {
    let item: Item
    let log: AppearLog
    @State private var flag = false

    var body: some View {
        Text("card \(item.id)")
            .frame(maxWidth: .infinity)
            .padding(12)
            .onAppear {
                log.entries.append(.init(id: item.id, done: item.done, flag: flag))
            }
            .onReceive(NotificationCenter.default.publisher(for: setFlagNote)) { note in
                if note.object as? Int == item.id, !item.done { flag = true }
            }
    }
}

/// Та сама топологія, що стіна стіків: дві секції (активні/виконані),
/// у кожній дві колонки; парні id — ліва колонка, тож повернення
/// «в ту саму колонку» детерміноване
private struct Board: View {
    @ObservedObject var model: ListModel
    let log: AppearLog
    let lazyColumns: Bool
    /// Повернений id 2 їде в ІНШУ колонку (перевірка, що кеш — на колонку)
    let swapColumnOnReturn: Bool

    private func inLeftColumn(_ item: Item) -> Bool {
        if item.id == 2, swapColumnOnReturn, model.returned { return false }
        return item.id % 2 == 0
    }

    @ViewBuilder
    private func grid(_ list: [Item]) -> some View {
        let left = list.filter(inLeftColumn)
        let right = list.filter { !inLeftColumn($0) }
        HStack(alignment: .top, spacing: 10) {
            if lazyColumns {
                LazyVStack(spacing: 10) { ForEach(left) { Card(item: $0, log: log).id($0.id) } }
                LazyVStack(spacing: 10) { ForEach(right) { Card(item: $0, log: log).id($0.id) } }
            } else {
                VStack(spacing: 10) { ForEach(left) { Card(item: $0, log: log).id($0.id) } }
                VStack(spacing: 10) { ForEach(right) { Card(item: $0, log: log).id($0.id) } }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                grid(model.items.filter { !$0.done })
                Divider().padding(.vertical, 12)
                grid(model.items.filter { $0.done })
            }
            .padding(16)
        }
        .frame(width: 380, height: 640)
    }
}

@MainActor
final class LazyStateResurrectionTests: XCTestCase {

    private var window: NSWindow!

    override func tearDown() {
        MainActor.assumeIsolated {
            window?.orderOut(nil)
            window = nil
        }
        super.tearDown()
    }

    private func show(_ view: some View) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 640),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderBack(nil)
    }

    /// Крутити ранлуп, поки умова не справдиться (або таймаут)
    private func pump(timeout: TimeInterval = 3, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// Сценарій F3 у чистому вигляді: виконати картку 2 (@State стає
    /// недефолтним) → рядок зникає з активної секції → повернути.
    /// Повертає запис появи поверненої картки серед активних
    private func runScenario(lazyColumns: Bool,
                             swapColumnOnReturn: Bool = false) -> AppearLog.Entry? {
        let model = ListModel()
        let log = AppearLog()
        show(Board(model: model, log: log, lazyColumns: lazyColumns,
                   swapColumnOnReturn: swapColumnOnReturn))
        pump { log.entries.count >= 6 }
        XCTAssertGreaterThanOrEqual(log.entries.count, 6, "картки не зʼявились")

        // 1. «Виконати»: @State картки 2 стає недефолтним (flag=true)...
        NotificationCenter.default.post(name: setFlagNote, object: 2)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        // 2. ...і рядок зникає з даних активної секції
        model.items[2].done = true
        pump { log.entries.contains { $0.id == 2 && $0.done } }

        // 3. Повернути в активні: той самий id знову в активній секції
        let before = log.entries.filter { $0.id == 2 && !$0.done }.count
        model.returned = true
        model.items[2].done = false
        pump { log.entries.filter { $0.id == 2 && !$0.done }.count > before }
        return log.entries.last { $0.id == 2 && !$0.done }
    }

    /// Сам механізм пастки: лінива колонка воскрешає @State поверненого
    /// id. Падіння цього тесту = Apple полагодила поведінку — можна
    /// переглядати запобіжники §15.65
    func testLazyColumnResurrectsRowState() {
        let entry = runScenario(lazyColumns: true)
        XCTAssertNotNil(entry, "картка 2 не повернулась в активні")
        XCTAssertEqual(entry?.flag, true,
                       "LazyVStack більше не воскрешає @State за id — перевір §15.65")
    }

    /// Контроль 1: звичайний VStack стан не воскрешає — пастка живе
    /// саме в кеші лінивого контейнера
    func testPlainVStackDoesNotResurrectRowState() {
        let entry = runScenario(lazyColumns: false)
        XCTAssertNotNil(entry, "картка 2 не повернулась в активні")
        XCTAssertEqual(entry?.flag, false,
                       "VStack почав воскрешати @State — механізм §15.65 змінився")
    }

    /// Контроль 2: кеш живе окремо в кожній колонці — повернення в іншу
    /// колонку дає чистий стан (тому F3 ловив лише «частину стіків»)
    func testOtherColumnGetsFreshState() {
        let entry = runScenario(lazyColumns: true, swapColumnOnReturn: true)
        XCTAssertNotNil(entry, "картка 2 не повернулась в активні")
        XCTAssertEqual(entry?.flag, false,
                       "кеш @State перестав бути поколонковим — механізм §15.65 змінився")
    }
}
