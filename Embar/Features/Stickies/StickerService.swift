//
//  StickerService.swift
//  Embar
//
//  Операції над стіками (SPEC §2, §8.2, §12). Чисті дата-операції над
//  ModelContext; тости показує View. Видалення = soft-delete (deletedAt),
//  фізична чистка > 30 днів у runMaintenance().
//

import Foundation
import SwiftData

enum StickerService {

    // MARK: - Створення

    /// Створити стік. Зберігаємо round-robin colorIndex (колір режиму
    /// «Різнокольорові»). У режимі byWall колір виводиться зі стіни на показі
    /// (StickyColorMode), тож тут його не фіксуємо.
    @discardableResult
    static func add(text: String, wall: Wall?, in context: ModelContext) -> Sticker {
        let sticker = Sticker(text: text, colorIndex: nextColorIndex())
        sticker.wall = wall
        context.insert(sticker)
        StickerMutation.changed(sticker) // кеш зрізу (F5)
        return sticker
    }

    private static let colorRotationKey = "stickyColorRotation"

    private static func nextColorIndex() -> Int {
        let current = EmbarDefaults.store.integer(forKey: colorRotationKey) % 5
        EmbarDefaults.store.set((current + 1) % 5, forKey: colorRotationKey)
        return current
    }

    // MARK: - Стан

    /// Виконано ↔ активно. Виконання знімає пін і сповіщення про дедлайн
    /// (сам дедлайн лишається — він частина змісту стіка). Зняли «зроблено»
    /// (рішення 2026-07-23) — сповіщення повертається, а цикл архівації
    /// починається з нуля.
    ///
    /// Відлік автоархіву стартує САМЕ ТУТ, у момент виконання, а не від
    /// `updatedAt`: інакше правка вже виконаного стіка безкінечно
    /// відсувала б архів, а зміна правил — навпаки, змітала все старе
    /// одним махом (ревʼю 2026-08-20)
    static func toggleDone(_ sticker: Sticker) {
        sticker.done.toggle()
        if sticker.done { sticker.pinned = false }
        sticker.archiveCountdownAt = sticker.done ? .now : nil
        sticker.updatedAt = .now
        ReminderScheduler.replan(for: sticker)
        StickerMutation.changed(sticker) // кеш зрізу (F5)
    }

    static func togglePin(_ sticker: Sticker) {
        sticker.pinned.toggle()
        sticker.updatedAt = .now
        StickerMutation.changed(sticker) // кеш зрізу (F5)
    }

    // MARK: - Видалення (soft-delete + undo)

    static func softDelete(_ sticker: Sticker) {
        sticker.deletedAt = .now
        sticker.updatedAt = .now
        ReminderScheduler.cancel(id: sticker.id)
        StickerMutation.changed(sticker) // кеш зрізу (F5)
    }

    static func undoDelete(_ sticker: Sticker) {
        sticker.deletedAt = nil
        sticker.updatedAt = .now
        // Відновити сповіщення про дедлайн, якщо воно ще попереду
        ReminderScheduler.replan(for: sticker)
        StickerMutation.changed(sticker) // кеш зрізу (F5)
    }

    // MARK: - Крос-поверхневі зв'язки

    enum MatureResult {
        case created(Note)
        case alreadyExists(Note)
    }

    /// Стік → Нотатка (matureSticky, SPEC §12). Двобічний зв'язок; стік лишається.
    /// Відкриття існуючої/нової нотатки — у M4 (редактор нотаток).
    static func matureSticky(_ sticker: Sticker, in context: ModelContext) -> MatureResult {
        if let existing = sticker.note {
            // Якщо повʼязана нотатка ще жива — просто повідомляємо; якщо її
            // soft-видалили — знімаємо лінк і створюємо нову (як прототип)
            if existing.deletedAt == nil {
                return .alreadyExists(existing)
            }
            sticker.note = nil
        }
        let note = Note(title: sticker.text, content: sticker.bodyText)
        note.bornType = "sticky"
        note.bornDate = sticker.createdAt
        context.insert(note)
        sticker.note = note // встановлює обидва боки через inverse
        sticker.updatedAt = .now
        // Лінк на нотатку зріз не чіпає, але дія рідкісна — страховка
        // повною інвалідацією дешевша за помилку класифікації (план F5)
        StickerMutation.bulkChanged()
        NoteMutation.changed(note) // нова нотатка в списку (F5.4)
        return .created(note)
    }

    /// Стік → Тудушка (SPEC §12): копія тексту, без зворотного лінка.
    /// Повертає false, якщо текст порожній.
    @discardableResult
    static func addToTodos(_ sticker: Sticker, in context: ModelContext) -> Bool {
        // Мертвий код до повернення Home, але гейт режиму читання вже
        // тут - тихий, як у HomeService (SPEC §15.77ґ)
        guard EntitlementStore.shared.canCreate else { return false }
        let text = sticker.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        context.insert(Todo(text: text))
        return true
    }

    // Обслуговування стіків (автоархів + purge) переїхало в AppMaintenance.run,
    // яке викликається при старті / переході доби / пробудженні.
}
