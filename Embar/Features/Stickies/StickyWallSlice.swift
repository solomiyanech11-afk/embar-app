//
//  StickyWallSlice.swift
//  Embar
//
//  Зріз стіни з інкрементним оновленням (F5, план 2026-08-28).
//
//  Проблема: будь-яка мутація одного стіка інвалідувала @Query, і body
//  перераховував фільтр + сортування + лічильники по ВСІХ стіках, причому
//  по «холодних» обʼєктах SwiftData (faulting) — ~390 мс на 5000 проти
//  ~30 мс на 50. Тут той самий результат тримається в кеші, а зміна
//  одного стіка правиться точковим патчем за O(log n) БЕЗ дотику до
//  властивостей чужих обʼєктів.
//
//  Три опори механізму:
//  · СНАПШОТИ — зліпок полів, від яких залежить зріз, на кожен відомий
//    стік, ключ — ідентичність обʼєкта (ObjectIdentifier). Патч знає
//    старий стан без читання моделі, компаратор порівнює сусідів без
//    faulting-у, а фізично видалений @Model обробляється взагалі без
//    дотику до властивостей (дотик — краш; прецедент guard-а —
//    DesktopStickyManager.reconcile).
//  · КАНОНІЧНИЙ ТОТАЛЬНИЙ ПОРЯДОК — усі сорти мають тайбрейк
//    createdAt desc → id. Раніше done/filtered успадковували порядок
//    @Query (невизначений на однакових createdAt), а сорти були
//    нестабільні — звірити патч із перерахунком було б неможливо.
//    Для ока різниця нульова (SPEC §15, рішення 2026-08-28).
//  · ЄДИНА ТОЧКА СПОВІЩЕННЯ — StickerMutation: кожен шлях мутації
//    з переліку в плані F5 постить «стік змінився» (точковий патч) або
//    «мінялось багато» (повна інвалідація). Пропущений шлях ловить
//    запобіжник у StickiesModel (пісочниця звіряє кеш із перерахунком
//    і падає з поясненням).
//

import Foundation
import SwiftData

// MARK: - Сповіщення про мутації стіків

extension Notification.Name {
    /// Один стік змінився (object = Sticker) → точковий патч кеша
    static let embarStickerMutated = Notification.Name("embarStickerMutated")
    /// Масова зміна (maintenance, міграції, сідери) → повна інвалідація
    static let embarStickersBulkChanged = Notification.Name("embarStickersBulkChanged")
}

/// Єдина точка посту — щоб жоден сайт мутації не писав нотифікацію
/// руками і не розійшовся в імені/пейлоаді
enum StickerMutation {
    static func changed(_ sticker: Sticker) {
        NotificationCenter.default.post(name: .embarStickerMutated, object: sticker)
    }

    static func bulkChanged() {
        NotificationCenter.default.post(name: .embarStickersBulkChanged, object: nil)
    }
}

// MARK: - Снапшот залежностей зрізу

/// Поля стіка, від яких залежить членство/порядок/лічильники. Значення,
/// не посилання: порівняння і сортування не торкаються @Model
struct StickySnapshot: Equatable {
    var id: UUID
    var wallID: UUID?
    var deleted: Bool
    var archived: Bool
    var done: Bool
    var pinned: Bool
    var createdAt: Date
    var deadline: Date?
    var emojiTag: String?

    init(_ s: Sticker) {
        id = s.id
        wallID = s.wall?.id
        deleted = s.deletedAt != nil
        archived = s.archived
        done = s.done
        pinned = s.pinned
        createdAt = s.createdAt
        deadline = s.deadline
        emojiTag = s.emojiTag
    }

    /// Та сама логіка, що StickyFilter.matches, але над зліпком —
    /// membership патча і повного перерахунку не можуть розійтись
    func matches(kind: StickyFilterKind, wallID selectedWallID: UUID?, emoji: String?) -> Bool {
        guard !deleted else { return false }
        if let selectedWallID { guard wallID == selectedWallID else { return false } }
        if let emoji { guard emojiTag == emoji else { return false } }
        if kind == .archive { return archived }
        guard !archived else { return false }
        switch kind {
        case .all: return true
        case .today: return Calendar.current.isDateInToday(createdAt)
        case .deadline: return deadline != nil
        case .done: return done
        case .archive: return true // недосяжно
        }
    }

    /// Лічильники бару стін рахують живі неархівні стіки незалежно від фільтра
    var countable: Bool { !deleted && !archived }

    // MARK: Канонічний порядок

    /// Порядок @Query, зроблений тотальним: createdAt desc → id
    static func queryOrder(_ a: Self, _ b: Self) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    /// Активна секція: pinned наверх, далі queryOrder
    static func activeOrder(_ a: Self, _ b: Self) -> Bool {
        if a.pinned != b.pinned { return a.pinned }
        return queryOrder(a, b)
    }

    /// Фільтр «Дедлайн»: найближчий дедлайн перший, nil у кінець, далі queryOrder
    static func deadlineOrder(_ a: Self, _ b: Self) -> Bool {
        let da = a.deadline ?? .distantFuture
        let db = b.deadline ?? .distantFuture
        if da != db { return da < db }
        return queryOrder(a, b)
    }
}

// MARK: - Зріз

/// Все, що body стіни рахував по всіх стіках: секції + лічильники.
/// (Раніше — WallSections у StickiesView + wallCounts + isTrulyEmpty.)
struct WallSlice {
    var filtered: [Sticker] = []
    var active: [Sticker] = []
    var done: [Sticker] = []
    /// Лічильники бару стін: «Всі» + по стінах (незалежно від фільтра/стіни)
    var countAll: Int = 0
    var countByWall: [UUID: Int] = [:]
}

// MARK: - Двигун: повний перерахунок + точковий патч

@MainActor
final class WallSliceEngine {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md

    struct Fingerprint: Equatable {
        var wallID: UUID?
        var kind: StickyFilterKind
        var emoji: String?
    }

    private(set) var slice = WallSlice()
    private(set) var fingerprint: Fingerprint?
    private var snapshots: [ObjectIdentifier: StickySnapshot] = [:]

    private func order(for kind: StickyFilterKind)
        -> (StickySnapshot, StickySnapshot) -> Bool {
        kind == .deadline ? StickySnapshot.deadlineOrder : StickySnapshot.activeOrder
    }

    // MARK: Повний перерахунок

    /// Один прохід по всіх стіках: снапшоти + фільтр + лічильники, далі
    /// сортування секцій. Єдине місце, що читає властивості ВСІХ обʼєктів
    func rebuild(all: [Sticker], fingerprint fp: Fingerprint) {
        var snaps: [ObjectIdentifier: StickySnapshot] = [:]
        snaps.reserveCapacity(all.count)
        var matched: [(Sticker, StickySnapshot)] = []
        var countAll = 0
        var countByWall: [UUID: Int] = [:]
        for sticker in all {
            let snap = StickySnapshot(sticker)
            snaps[ObjectIdentifier(sticker)] = snap
            if snap.countable {
                countAll += 1
                if let wallID = snap.wallID { countByWall[wallID, default: 0] += 1 }
            }
            if snap.matches(kind: fp.kind, wallID: fp.wallID, emoji: fp.emoji) {
                matched.append((sticker, snap))
            }
        }
        matched.sort { StickySnapshot.queryOrder($0.1, $1.1) }
        let activeOrder = order(for: fp.kind)
        var out = WallSlice(countAll: countAll, countByWall: countByWall)
        out.filtered = matched.map(\.0)
        out.active = matched.filter { !$0.1.done }
            .sorted { activeOrder($0.1, $1.1) }.map(\.0)
        out.done = matched.filter { $0.1.done }.map(\.0)
        slice = out
        snapshots = snaps
        fingerprint = fp
    }

    // MARK: Точковий патч

    /// Один стік змінився: прибрати зі старих позицій, вставити в нові.
    /// Універсальний — покриває done/pin/emoji/deadline/wall/insert/
    /// soft-delete/undo/purge; O(log n) порівнянь, нуль faulting-у чужих
    func update(_ sticker: Sticker) {
        guard let fp = fingerprint else { return } // кеш ще не будувався
        let key = ObjectIdentifier(sticker)
        let old = snapshots[key]

        // Фізично видалений @Model: властивостей не торкатися (краш) —
        // ідентичності вистачає, щоб прибрати його звідусіль. Дві ознаки:
        // isDeleted живе лише ДО save, після save обʼєкт просто випадає
        // з контексту (modelContext == nil) — перевірено тестом
        let purged = sticker.isDeleted || sticker.modelContext == nil
        let new: StickySnapshot? = purged ? nil : StickySnapshot(sticker)

        // Лічильники — за різницею старого і нового зліпків
        if old?.countable == true {
            slice.countAll -= 1
            if let wallID = old?.wallID {
                // Нульові записи прибираємо — еталон їх не має, і звірка
                // словників не мусить спотикатись об [wall: 0]
                let left = (slice.countByWall[wallID] ?? 0) - 1
                slice.countByWall[wallID] = left > 0 ? left : nil
            }
        }
        if let new, new.countable {
            slice.countAll += 1
            if let wallID = new.wallID { slice.countByWall[wallID, default: 0] += 1 }
        }

        // Секції: старі позиції геть (пошук за ідентичністю — порівняння
        // вказівників, без властивостей)...
        if old?.matches(kind: fp.kind, wallID: fp.wallID, emoji: fp.emoji) == true {
            removeByIdentity(sticker, from: &slice.filtered)
            removeByIdentity(sticker, from: &slice.active)
            removeByIdentity(sticker, from: &slice.done)
        }
        // ...нове місце — бінарною вставкою за канонічним порядком
        if let new {
            snapshots[key] = new
            if new.matches(kind: fp.kind, wallID: fp.wallID, emoji: fp.emoji) {
                insert(sticker, snap: new, into: &slice.filtered,
                       by: StickySnapshot.queryOrder)
                if new.done {
                    insert(sticker, snap: new, into: &slice.done,
                           by: StickySnapshot.queryOrder)
                } else {
                    insert(sticker, snap: new, into: &slice.active,
                           by: order(for: fp.kind))
                }
            }
        } else {
            snapshots.removeValue(forKey: key)
        }
    }

    private func removeByIdentity(_ sticker: Sticker, from array: inout [Sticker]) {
        if let i = array.firstIndex(where: { $0 === sticker }) {
            array.remove(at: i)
        }
    }

    /// Бінарна вставка; ключі сусідів — зі снапшотів (без faulting-у).
    /// Сусід без снапшота означає зламаний інваріант «масиви ⊆ снапшоти» —
    /// чесно перебудуватись при наступному перерахунку не вийде тихо,
    /// тож ставимо в кінець і лишаємо запобіжнику піймати
    private func insert(_ sticker: Sticker, snap: StickySnapshot,
                        into array: inout [Sticker],
                        by areInOrder: (StickySnapshot, StickySnapshot) -> Bool) {
        var lo = 0, hi = array.count
        while lo < hi {
            let mid = (lo + hi) / 2
            guard let midSnap = snapshots[ObjectIdentifier(array[mid])] else {
                lo = array.count
                break
            }
            if areInOrder(midSnap, snap) { lo = mid + 1 } else { hi = mid }
        }
        array.insert(sticker, at: lo)
    }

    // MARK: Звірка (запобіжник пісочниці + тести)

    /// Опис першої розбіжності кеша з еталоном; nil = збіг. Порівняння за
    /// ідентичністю обʼєктів + лічильники
    func divergence(from reference: WallSlice) -> String? {
        func diff(_ name: String, _ ours: [Sticker], _ theirs: [Sticker]) -> String? {
            if ours.count != theirs.count {
                return "\(name): у кеші \(ours.count), в еталоні \(theirs.count)"
            }
            for i in ours.indices where ours[i] !== theirs[i] {
                return "\(name)[\(i)]: у кеші «\(preview(ours[i]))», в еталоні «\(preview(theirs[i]))»"
            }
            return nil
        }
        if let d = diff("filtered", slice.filtered, reference.filtered) { return d }
        if let d = diff("active", slice.active, reference.active) { return d }
        if let d = diff("done", slice.done, reference.done) { return d }
        if slice.countAll != reference.countAll {
            return "countAll: у кеші \(slice.countAll), в еталоні \(reference.countAll)"
        }
        if slice.countByWall != reference.countByWall {
            return "countByWall розійшовся: кеш \(slice.countByWall), еталон \(reference.countByWall)"
        }
        return nil
    }

    private func preview(_ sticker: Sticker) -> String {
        // Обидві ознаки, як в `update()`: `isDeleted` живе лише ДО save,
        // після нього обʼєкт просто випадає з контексту. Одного
        // `isDeleted` мало — діагностика падала б на дотику до
        // властивостей замість того, щоб назвати розбіжність
        guard !sticker.isDeleted, sticker.modelContext != nil else {
            return "purged @Model"
        }
        return "\(sticker.id.uuidString.prefix(8))·\(sticker.text.prefix(16))"
    }

    /// Еталонний перерахунок БЕЗ мутації стану двигуна (для звірки)
    static func computeReference(all: [Sticker], fingerprint fp: Fingerprint) -> WallSlice {
        let scratch = WallSliceEngine()
        scratch.rebuild(all: all, fingerprint: fp)
        return scratch.slice
    }
}
