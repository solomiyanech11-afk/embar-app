//
//  AppMaintenance.swift
//  Embar
//
//  Єдине обслуговування бази (SPEC §5, §8.2, §11.9). Викликається:
//  · при старті застосунку;
//  · при переході доби (`NSCalendarDayChanged` — система шле рівно опівночі
//    локального часу і при зміні таймзони);
//  · при пробудженні зі сну (`NSWorkspace.didWakeNotification`).
//
//  Три задачі:
//  1. Стіки: автоархів прострочених done-стіків + фізична чистка > 30 днів.
//  2. Тудушки: виконані до сьогодні → soft-delete; фізична чистка > 30 днів.
//  3. Стіни: фізична чистка soft-deleted > 30 днів.
//
//  Звички не потребують обслуговування — їхній стан derived від `completions`
//  (немає «скиду»; пропуск днів природно рветь стрік).
//

import Foundation
import SwiftData

enum AppMaintenance {
    private static let purgeDays: Double = 30

    /// `now` — шов для тестів: автоархів інакше не перевіриш, не чекаючи
    /// днями. У застосунку завжди дефолт
    static func run(in context: ModelContext, now: Date = .now) {
        let purgeCutoff = now.addingTimeInterval(-purgeDays * 86400)
        let startOfToday = Calendar.current.startOfDay(for: now)

        maintainStickers(now: now, purgeCutoff: purgeCutoff, in: context)
        maintainWalls(purgeCutoff: purgeCutoff, in: context)
        maintainTodos(startOfToday: startOfToday, purgeCutoff: purgeCutoff, in: context)
        // Purge 30 днів покриває ВСІ soft-deleted сутності Home (review)
        purge(cutoff: purgeCutoff, in: context) { (e: Event) in e.deletedAt }
        purge(cutoff: purgeCutoff, in: context) { (h: Habit) in h.deletedAt }
        purge(cutoff: purgeCutoff, in: context) { (t: HomeTag) in t.deletedAt }
        // Нотатки (M4): фото purge-яться каскадом разом із Note
        purge(cutoff: purgeCutoff, in: context) { (n: Note) in n.deletedAt }
        purge(cutoff: purgeCutoff, in: context) { (f: NoteFolder) in f.deletedAt }
        // Рідер (M5): sources/entries/highlights каскадом з ReaderBook;
        // окремо видалені записи й хайлайти мають власний deletedAt
        purge(cutoff: purgeCutoff, in: context) { (b: ReaderBook) in b.deletedAt }
        purge(cutoff: purgeCutoff, in: context) { (e: ReaderEntry) in e.deletedAt }
        purge(cutoff: purgeCutoff, in: context) { (h: Highlight) in h.deletedAt }
        // Замінені джерела link-bar (soft-delete у setSource, review M5 #8)
        purge(cutoff: purgeCutoff, in: context) { (s: ReaderSource) in s.deletedAt }
        // Теми блокнотів (2026-07-21)
        purge(cutoff: purgeCutoff, in: context) { (t: ReaderTheme) in t.deletedAt }

        try? context.save()
        // Масова зміна стіків (purge/архівація/nullify стін) → повна
        // інвалідація кеша зрізу: кешовані масиви не сміють тримати
        // фізично видалені @Model (план F5)
        StickerMutation.bulkChanged()
        NoteMutation.bulkChanged() // те саме для списку нотаток (F5.4)

        // ПІСЛЯ save: сповіщення планує система, до бази це вже не має стосунку
        relocalizeRemindersIfLanguageChanged(in: context)
        pruneOrphanReminders(in: context)
    }

    /// Зняти сповіщення без живого стіка. Головне джерело сиріт — тестові
    /// прогони: до запобіжника isTestRun вони встигали поставити системі
    /// справжні банери про фікстури («Старий стік», знахідка 2026-08-20).
    ///
    /// ❗ Дозволених рахуємо через `canRemind`, а не через `job(for:)`:
    /// той вимагає майбутнього тригера, і ВІДКЛАДЕНЕ сповіщення (стік із
    /// минулим дедлайном) не потрапляло в дозволені ніколи — ми зносили
    /// його власноруч (ревʼю 2026-08-20)
    private static func pruneOrphanReminders(in context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<Sticker>()) else { return }
        let valid = Set(all.filter(ReminderScheduler.canRemind).map(\.id))
        Task { await ReminderScheduler.pruneOrphans(keeping: valid) }
    }

    // MARK: - Мова вже запланованих нагадувань (i18n 2026-08-03)

    private static let remindersLanguageKey = "remindersLanguage"

    /// Текст сповіщення запікається в момент планування, а не показу — тож
    /// після зміни мови нагадування, заплановані раніше, спливли б старою.
    /// Перепланувати їх можна лише тут, на старті: у момент вибору мови
    /// новий переклад ще не завантажений (він приходить із перезапуском).
    private static func relocalizeRemindersIfLanguageChanged(in context: ModelContext) {
        let defaults = EmbarDefaults.store
        let active = LanguageStore.activeCode
        guard defaults.string(forKey: remindersLanguageKey) != active else { return }
        defaults.set(active, forKey: remindersLanguageKey)

        guard let all = try? context.fetch(FetchDescriptor<Sticker>()) else { return }
        // Знімок значень: далі йдемо в async, а моделі SwiftData звʼязані
        // з контекстом і за його межі їх не тягнемо
        let jobs = all.compactMap(ReminderScheduler.job(for:))
        guard !jobs.isEmpty else { return }
        Task {
            for job in jobs {
                ReminderScheduler.cancel(id: job.id)
                await ReminderScheduler.schedule(job)
            }
        }
    }

    /// Фізична чистка давно soft-deleted записів моделі з deletedAt
    private static func purge<T: PersistentModel>(cutoff: Date, in context: ModelContext,
                                                  deletedAt: (T) -> Date?) {
        guard let all = try? context.fetch(FetchDescriptor<T>()) else { return }
        for item in all where (deletedAt(item) ?? .distantFuture) < cutoff {
            context.delete(item)
        }
    }

    // MARK: - Стіки

    private static func maintainStickers(now: Date, purgeCutoff: Date, in context: ModelContext) {
        // Один строк на всі стіки (рішення 2026-08-19: автоархів завжди
        // ввімкнений, індивідуальних строків і вимикачів більше немає)
        let globalDays = StickyAutoArchive.days
        // Раніше за цей момент не починається жоден відлік (ревʼю
        // 2026-08-20): зміна строку в налаштуваннях не діє заднім числом
        let termFloor = StickyAutoArchive.termChangedAt ?? .distantPast
        guard let all = try? context.fetch(FetchDescriptor<Sticker>()) else { return }
        for sticker in all {
            if let deletedAt = sticker.deletedAt, deletedAt < purgeCutoff {
                ReminderScheduler.cancel(id: sticker.id)
                context.delete(sticker)
                continue
            }
            guard sticker.deletedAt == nil else { continue }

            // Архів — проміжна зупинка на 30 днів, потім soft-delete
            // (рішення 2026-07-21; далі спрацює звичайна фізична чистка
            // ще через 30 — правило «never hard-delete» не порушено).
            // Відлік тут БЕЗУМОВНИЙ свідомо (рішення 2026-07-23): архів —
            // вітрина без дій
            if sticker.archived {
                if let archivedAt = sticker.archivedAt {
                    if archivedAt.addingTimeInterval(purgeDays * 86400) < now {
                        sticker.deletedAt = now
                        // Як у StickerService.softDelete: сповіщення не має
                        // пережити стік (code review 2026-07-23)
                        ReminderScheduler.cancel(id: sticker.id)
                    }
                } else {
                    // Заархівовані до появи archivedAt — відлік від сьогодні
                    sticker.archivedAt = now
                }
                continue
            }

            guard sticker.done else {
                // Зняли «зроблено» — цикл починається наново (§15.44б)
                if sticker.archiveCountdownAt != nil {
                    sticker.archiveCountdownAt = nil
                }
                continue
            }

            // Відліку ще немає: стік щойно став кандидатом — його виконали
            // до появи цього поля, або правила змінились так, що він ним
            // став. Починаємо рахувати ЗАРАЗ і цього разу нічого не
            // архівуємо: людина мусить побачити стік на стіні хоча б повний
            // строк, перш ніж він поїде (ревʼю 2026-08-20)
            guard let startedAt = sticker.archiveCountdownAt else {
                sticker.archiveCountdownAt = now
                continue
            }

            let archiveAt = max(startedAt, termFloor)
                .addingTimeInterval(Double(globalDays) * 86400)
            if archiveAt < now {
                sticker.archived = true
                sticker.archivedAt = now
            }
        }
    }

    // MARK: - Стіни (nullify відвʼязує стіки → лишаються під «Всі»)

    private static func maintainWalls(purgeCutoff: Date, in context: ModelContext) {
        guard let walls = try? context.fetch(FetchDescriptor<Wall>()) else { return }
        for wall in walls where (wall.deletedAt ?? .distantFuture) < purgeCutoff {
            context.delete(wall)
        }
    }

    // MARK: - Тудушки

    private static func maintainTodos(startOfToday: Date, purgeCutoff: Date, in context: ModelContext) {
        guard let todos = try? context.fetch(FetchDescriptor<Todo>()) else { return }
        for todo in todos {
            // Фізична чистка давно soft-deleted
            if let deletedAt = todo.deletedAt, deletedAt < purgeCutoff {
                context.delete(todo)
                continue
            }
            // Виконані раніше за сьогодні → soft-delete (покриває багатоденні пропуски)
            if todo.deletedAt == nil, todo.done,
               let completedAt = todo.completedAt, completedAt < startOfToday {
                todo.deletedAt = .now
            }
        }
    }
}
