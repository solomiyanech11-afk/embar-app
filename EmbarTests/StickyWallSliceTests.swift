//
//  StickyWallSliceTests.swift
//  EmbarTests
//
//  Кеш зрізу стіни (F5, план 2026-08-28). Головний тест — еквівалентність:
//  точковий патч після КОЖНОЇ мутації мусить давати рівно той самий зріз,
//  що повний перерахунок (та сама звірка, що запобіжник пісочниці в
//  StickiesModel; під -SandboxPerfProbe запобіжник вимкнено — чесність
//  зонда тримає саме цей файл).
//

import XCTest
import SwiftData
@testable import Embar

final class StickyWallSliceTests: XCTestCase {

    /// Контейнер у властивості: локальний звільнився б, і mainContext
    /// повалив би SwiftData на першому ж fetch (патерн StickyAutoArchiveTests)
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: EmbarApp.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        return container.mainContext
    }

    /// Відтворюваний генератор (LCG): падіння відтворюється тим самим сідом
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    /// Живі стіки з бази у порядку @Query (createdAt desc)
    private func fetchAll(_ context: ModelContext) throws -> [Sticker] {
        try context.fetch(FetchDescriptor<Sticker>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    private func seed(_ context: ModelContext, walls: [Wall], count: Int,
                      rng: inout SeededRNG) -> [Sticker] {
        let base = Date.now
        var out: [Sticker] = []
        for i in 0..<count {
            let s = Sticker(text: "Стік #\(i)", colorIndex: i % 5)
            // Половина «сьогоднішні», половина старі (фільтр «Сьогодні»)
            s.createdAt = Bool.random(using: &rng)
                ? base.addingTimeInterval(-Double(i))
                : base.addingTimeInterval(-Double(86_400 * 3 + i))
            s.updatedAt = s.createdAt
            s.done = Int.random(in: 0..<5, using: &rng) == 0
            s.pinned = Int.random(in: 0..<7, using: &rng) == 0
            s.archived = Int.random(in: 0..<9, using: &rng) == 0
            if Int.random(in: 0..<10, using: &rng) == 0 { s.deletedAt = base }
            if Int.random(in: 0..<4, using: &rng) == 0 {
                s.deadline = base.addingTimeInterval(Double(Int.random(in: 1...9, using: &rng)) * 3600)
            }
            if Int.random(in: 0..<3, using: &rng) == 0 {
                s.emojiTag = ["🔥", "💡"].randomElement(using: &rng)
            }
            if Int.random(in: 0..<3, using: &rng) == 0 {
                s.wall = walls.randomElement(using: &rng)
            }
            context.insert(s)
            out.append(s)
        }
        return out
    }

    /// Набір fingerprint-ів, що покриває всі види фільтра + стіну + емоджі
    private func fingerprints(walls: [Wall]) -> [WallSliceEngine.Fingerprint] {
        var out: [WallSliceEngine.Fingerprint] = []
        for kind in StickyFilterKind.allCases {
            out.append(.init(wallID: nil, kind: kind, emoji: nil))
        }
        out.append(.init(wallID: walls[0].id, kind: .all, emoji: nil))
        out.append(.init(wallID: walls[0].id, kind: .done, emoji: nil))
        out.append(.init(wallID: nil, kind: .all, emoji: "🔥"))
        return out
    }

    // MARK: - Головний тест: патч ↔ перерахунок

    /// Рандомізовані послідовності всіх одиночних дій з плану F5, під
    /// кожним fingerprint-ом: після кожної мутації патч == еталон
    func testRandomizedPatchMatchesFullRecompute() throws {
        let context = try makeContext()
        var rng = SeededRNG(state: 20260828)
        let walls = [Wall(name: "Робота"), Wall(name: "Дім")]
        walls.forEach(context.insert)
        let stickers = seed(context, walls: walls, count: 120, rng: &rng)

        for fp in fingerprints(walls: walls) {
            let engine = WallSliceEngine()
            engine.rebuild(all: try fetchAll(context), fingerprint: fp)

            for step in 0..<200 {
                let sticker = stickers.randomElement(using: &rng)!
                guard !sticker.isDeleted else { continue }
                // Усі одиночні дії з переліку в плані F5
                switch Int.random(in: 0..<8, using: &rng) {
                case 0: // виконано (логіка StickerService.toggleDone)
                    sticker.done.toggle()
                    if sticker.done { sticker.pinned = false }
                case 1: sticker.pinned.toggle()
                case 2: sticker.deletedAt = sticker.deletedAt == nil ? .now : nil
                case 3: sticker.emojiTag = sticker.emojiTag == nil ? "🔥" : nil
                case 4: sticker.deadline = sticker.deadline == nil
                    ? .now.addingTimeInterval(3600) : nil
                case 5: sticker.wall = walls.randomElement(using: &rng)
                case 6: sticker.wall = nil
                default: sticker.archived.toggle()
                }
                engine.update(sticker)
                let reference = WallSliceEngine.computeReference(
                    all: try fetchAll(context), fingerprint: fp)
                if let divergence = engine.divergence(from: reference) {
                    XCTFail("Крок \(step), фільтр \(fp.kind.rawValue), " +
                            "стіна \(fp.wallID != nil), емоджі \(fp.emoji ?? "-"): \(divergence)")
                    return
                }
            }
        }
    }

    /// Новий стік, невідомий кешу (StickerService.add) — вставка патчем
    func testInsertOfUnknownStickerPatches() throws {
        let context = try makeContext()
        var rng = SeededRNG(state: 7)
        let walls = [Wall(name: "Робота")]
        walls.forEach(context.insert)
        _ = seed(context, walls: walls, count: 30, rng: &rng)

        let fp = WallSliceEngine.Fingerprint(wallID: nil, kind: .all, emoji: nil)
        let engine = WallSliceEngine()
        engine.rebuild(all: try fetchAll(context), fingerprint: fp)

        let fresh = Sticker(text: "щойно з композера")
        context.insert(fresh)
        engine.update(fresh)

        let reference = WallSliceEngine.computeReference(
            all: try fetchAll(context), fingerprint: fp)
        XCTAssertNil(engine.divergence(from: reference))
        // Нагору серед НЕзакріплених: пін сидить вище за правилами сортування
        XCTAssertTrue(engine.slice.active.first { !$0.pinned } === fresh,
                      "новий стік мусить сісти нагору серед незакріплених")
    }

    /// Фізично видалений @Model: патч не сміє торкнутись властивостей
    /// (краш) — стік просто зникає звідусіль
    func testPurgedStickerIsRemovedWithoutTouchingProperties() throws {
        let context = try makeContext()
        var rng = SeededRNG(state: 42)
        let walls = [Wall(name: "Робота")]
        walls.forEach(context.insert)
        let stickers = seed(context, walls: walls, count: 20, rng: &rng)

        let fp = WallSliceEngine.Fingerprint(wallID: nil, kind: .all, emoji: nil)
        let engine = WallSliceEngine()
        engine.rebuild(all: try fetchAll(context), fingerprint: fp)

        let victim = stickers.first { $0.deletedAt == nil && !$0.archived }!
        context.delete(victim)
        try context.save()
        engine.update(victim) // не мусить крашитись

        let reference = WallSliceEngine.computeReference(
            all: try fetchAll(context), fingerprint: fp)
        XCTAssertNil(engine.divergence(from: reference))
        XCTAssertFalse(engine.slice.filtered.contains { $0 === victim })
    }

    /// Тотальний порядок: два перерахунки поспіль ідентичні
    func testRecomputeIsDeterministic() throws {
        let context = try makeContext()
        var rng = SeededRNG(state: 99)
        let walls = [Wall(name: "Робота")]
        walls.forEach(context.insert)
        // Кілька стіків з ОДНАКОВИМ createdAt — головний ворог детермінізму
        let base = Date.now
        for i in 0..<12 {
            let s = Sticker(text: "тай #\(i)")
            s.createdAt = base
            context.insert(s)
        }
        _ = seed(context, walls: walls, count: 20, rng: &rng)

        let fp = WallSliceEngine.Fingerprint(wallID: nil, kind: .all, emoji: nil)
        let a = WallSliceEngine()
        a.rebuild(all: try fetchAll(context), fingerprint: fp)
        let b = WallSliceEngine.computeReference(all: try fetchAll(context), fingerprint: fp)
        XCTAssertNil(a.divergence(from: b))
    }

    // MARK: - Семантика зрізу (спадок makeSections)

    /// Закріплені над рештою; всередині груп — новіші вище
    func testActivePinOrder() throws {
        let context = try makeContext()
        let base = Date.now
        let plain = Sticker(text: "звичайний новий")
        plain.createdAt = base
        let pinnedOld = Sticker(text: "закріплений старий")
        pinnedOld.createdAt = base.addingTimeInterval(-100)
        pinnedOld.pinned = true
        [plain, pinnedOld].forEach(context.insert)

        let fp = WallSliceEngine.Fingerprint(wallID: nil, kind: .all, emoji: nil)
        let engine = WallSliceEngine()
        engine.rebuild(all: try fetchAll(context), fingerprint: fp)
        XCTAssertTrue(engine.slice.active.first === pinnedOld,
                      "пін над новішим незакріпленим")
    }

    /// Фільтр «Дедлайн»: найближчий перший, done окремо, лічильники живих
    func testDeadlineFilterAndCounts() throws {
        let context = try makeContext()
        let wall = Wall(name: "Робота")
        context.insert(wall)
        let base = Date.now
        let soon = Sticker(text: "скоро"); soon.deadline = base.addingTimeInterval(600)
        let late = Sticker(text: "пізно"); late.deadline = base.addingTimeInterval(9600)
        late.createdAt = base.addingTimeInterval(-1)
        let none = Sticker(text: "без дедлайну"); none.createdAt = base.addingTimeInterval(-2)
        let onWall = Sticker(text: "на стіні"); onWall.wall = wall
        onWall.createdAt = base.addingTimeInterval(-3)
        let gone = Sticker(text: "видалений"); gone.deletedAt = base
        gone.createdAt = base.addingTimeInterval(-4)
        [soon, late, none, onWall, gone].forEach(context.insert)

        let engine = WallSliceEngine()
        engine.rebuild(all: try fetchAll(context),
                       fingerprint: .init(wallID: nil, kind: .deadline, emoji: nil))
        XCTAssertTrue(engine.slice.active.elementsEqual([soon, late], by: ===))
        XCTAssertEqual(engine.slice.countAll, 4, "живі неархівні, незалежно від фільтра")
        XCTAssertEqual(engine.slice.countByWall, [wall.id: 1])
    }

    // MARK: - Шлях сповіщень (StickiesModel + StickerService)

    /// Наскрізно: мутації через StickerService доходять до кеша моделі
    /// нотифікаціями, і зріз після них — рівно як перерахунок
    func testModelSliceStaysFreshThroughServiceMutations() throws {
        let context = try makeContext()
        var rng = SeededRNG(state: 5)
        let walls = [Wall(name: "Робота")]
        walls.forEach(context.insert)
        let stickers = seed(context, walls: walls, count: 40, rng: &rng)

        let model = StickiesModel()
        model.filterKind = .all
        var snapshot = try fetchAll(context)
        _ = model.slice(all: snapshot, wall: nil) // збудувати кеш

        let victim = stickers.first { $0.deletedAt == nil && !$0.archived && !$0.done }!
        StickerService.toggleDone(victim)
        StickerService.togglePin(stickers.first { $0.deletedAt == nil && !$0.done }!)
        StickerService.softDelete(stickers.last!)
        StickerService.undoDelete(stickers.last!)
        _ = StickerService.add(text: "новий з композера", wall: nil, in: context)

        snapshot = try fetchAll(context)
        let slice = model.slice(all: snapshot, wall: nil)
        let reference = WallSliceEngine.computeReference(
            all: snapshot,
            fingerprint: .init(wallID: nil, kind: .all, emoji: nil))
        // Той самий предикат, що в запобіжника: звіряємо через еталон
        XCTAssertTrue(slice.filtered.elementsEqual(reference.filtered, by: ===))
        XCTAssertTrue(slice.active.elementsEqual(reference.active, by: ===))
        XCTAssertTrue(slice.done.elementsEqual(reference.done, by: ===))
        XCTAssertEqual(slice.countAll, reference.countAll)
        XCTAssertTrue(slice.done.contains { $0 === victim })
    }

    /// bulkChanged → наступний slice чесно перераховує (ловить зміни,
    /// зроблені повз нотифікації)
    func testBulkChangedInvalidatesModelCache() throws {
        let context = try makeContext()
        var rng = SeededRNG(state: 11)
        let walls = [Wall(name: "Робота")]
        walls.forEach(context.insert)
        let stickers = seed(context, walls: walls, count: 20, rng: &rng)

        let model = StickiesModel()
        var snapshot = try fetchAll(context)
        _ = model.slice(all: snapshot, wall: nil)

        // Мутація ПОВЗ StickerMutation.changed — як maintenance
        let victim = stickers.first { $0.deletedAt == nil && !$0.archived }!
        victim.archived = true
        StickerMutation.bulkChanged()

        snapshot = try fetchAll(context)
        let slice = model.slice(all: snapshot, wall: nil)
        XCTAssertFalse(slice.filtered.contains { $0 === victim },
                       "після bulkChanged кеш мусить перечитати базу")
    }
}
