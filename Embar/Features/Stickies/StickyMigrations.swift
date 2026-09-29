//
//  StickyMigrations.swift
//  Embar
//
//  Одноразові міграції даних стіків. Схему SwiftData ми не версіонуємо
//  (CloudKit-правила: поля лише додаються, все optional/з дефолтом), тож
//  міграція — це разовий прохід по базі під прапорцем у налаштуваннях,
//  як ThemeStore.migrateDisabledMaterialsIfNeeded.
//
//  Викликати при старті ДО AppMaintenance.run — обслуговування вже має
//  бачити приведені до нових правил дані.
//

import Foundation
import SwiftData

@MainActor
enum StickyMigrations {

    static func run(in context: ModelContext) {
        migrateAutoArchiveAlwaysOn(in: context)
        migrateReminderIntoDeadline(in: context)
        // Кеш зрізу на цей момент ще не будувався (старт до UI), але
        // пост тримає інваріант «масова мутація = інвалідація» (план F5)
        StickerMutation.bulkChanged()
    }

    // MARK: - Автоархів завжди ввімкнено (рішення 2026-08-19)

    private static let autoArchiveFlagKey = "migratedAutoArchiveAlwaysOn"

    /// Було: автоархів можна вимкнути глобально («Вимк») і на кожному стіку
    /// окремо (`autoArchiveOff`), плюс індивідуальний строк (`autoDeleteAt`).
    /// Стало: один глобальний строк, вимкнути не можна. Тож індивідуальні
    /// налаштування скидаємо, а збережений «Вимк» (0) стає дефолтом.
    ///
    /// Самі поля лишаються в схемі (CloudKit: не видаляти) і після цієї
    /// міграції їх ніхто не читає — як `hiddenFromWall`.
    static func migrateAutoArchiveAlwaysOn(in context: ModelContext) {
        migrateAutoArchiveAlwaysOn(
            fetch: { try context.fetch(FetchDescriptor<Sticker>()) },
            save: { try context.save() })
    }

    /// Той самий прохід, але з підмінними «прочитати» і «зберегти» — щоб
    /// тест міг зімітувати збій бази. Інакше цей шлях не перевіриш, а він
    /// найдорожчий: прапорець після збою зробив би міграцію «зробленою»
    static func migrateAutoArchiveAlwaysOn(fetch: () throws -> [Sticker],
                                           save: () throws -> Void) {
        let defaults = EmbarDefaults.store
        guard !defaults.bool(forKey: autoArchiveFlagKey) else { return }

        // Стік і його попередні значення — на випадок відкату
        var touched: [(sticker: Sticker, off: Bool, until: Date?)] = []
        do {
            for sticker in try fetch()
            where sticker.autoArchiveOff || sticker.autoDeleteAt != nil {
                touched.append((sticker, sticker.autoArchiveOff, sticker.autoDeleteAt))
                sticker.autoArchiveOff = false
                sticker.autoDeleteAt = nil
            }
            try save()
        } catch {
            // ❗ Прапорця не ставимо — спробуємо ще раз наступного запуску.
            // Але самого прапорця мало: зміни вже лежать у контексті, і
            // автозбереження SwiftData винесло б їх у базу попри збій.
            // `context.rollback()` тут не помічник — він НЕ повертає
            // значення вже змінених обʼєктів (перевірено тестом
            // 2026-08-20), тож відкочуємо власноруч і рівно те, що чіпали
            for item in touched {
                item.sticker.autoArchiveOff = item.off
                item.sticker.autoDeleteAt = item.until
            }
            NSLog("Embar: міграція автоархіву не вдалась — %@",
                  error.localizedDescription)
            return
        }

        // «Вимк» (0) і будь-яке значення поза набором → дефолтний місяць
        let stored = defaults.integer(forKey: StickyAutoArchive.storageKey)
        if !StickyAutoArchive.options.contains(stored) {
            defaults.set(StickyAutoArchive.defaultDays,
                         forKey: StickyAutoArchive.storageKey)
        }
        defaults.set(true, forKey: autoArchiveFlagKey)
        NSLog("Embar: автоархів уніфіковано — скинуто індивідуальних налаштувань: %d",
              touched.count)
    }

    // MARK: - Нагадування стало дедлайном (рішення 2026-08-19)

    // Прапорця «migratedReminderIntoDeadline» більше немає (ревʼю
    // 2026-08-20) — див. коментар до migrateReminderIntoDeadline. У тих,
    // хто вже оновився, він лишиться в налаштуваннях мертвим ключем; це
    // нікому не заважає, а видаляти чуже сміття зі старту не варто

    /// Було: окреме нагадування (своя дата) поруч із дедлайном.
    /// Стало: один дедлайн і зсув «нагадати за N хв до».
    ///
    /// · нагадування без дедлайну → саме воно стає дедлайном, нагадати
    ///   в момент;
    /// · нагадування разом із дедлайном → дедлайн лишається як є, а зсув
    ///   рахуємо з різниці й округлюємо вниз до пресету (StickyNotify);
    /// · нагадування пізніше за дедлайн → нагадати в момент.
    ///
    /// Дедлайн без нагадування лишається БЕЗ сповіщення: людина його не
    /// просила, і після оновлення воно було б несподіванкою.
    static func migrateReminderIntoDeadline(in context: ModelContext) {
        migrateReminderIntoDeadline(
            fetch: { try context.fetch(FetchDescriptor<Sticker>()) },
            save: { try context.save() })
    }

    /// Зі швом для тесту — як і сусідня міграція (див. коментар вище).
    ///
    /// ❗ На відміну від сусідньої, ця міграція НЕ під прапорцем: вона
    /// щоразу шукає стіки з живим `reminder`. Прапорець лишився б пасткою
    /// — поле вже ніхто не читає, а стік із ним може приїхати й ПІСЛЯ
    /// міграції (CloudKit у M6), і нагадування зникло б мовчки
    /// (ревʼю 2026-08-20). Ціна — один прохід по вибірці, яку
    /// обслуговування бази робить наступним кроком усе одно
    static func migrateReminderIntoDeadline(fetch: () throws -> [Sticker],
                                            save: () throws -> Void) {
        let migrated: [Sticker]
        // Стік і його попередні значення — на випадок відкату
        var touched: [(sticker: Sticker, reminder: Date?,
                       deadline: Date?, offset: Int?)] = []
        do {
            migrated = try fetch().filter { $0.reminder != nil }
            guard !migrated.isEmpty else { return }
            for sticker in migrated {
                guard let reminder = sticker.reminder else { continue }
                touched.append((sticker, reminder, sticker.deadline,
                                sticker.notifyOffsetMinutes))
                sticker.reminder = nil
                if let deadline = sticker.deadline {
                    let minutes = (deadline.timeIntervalSince(reminder) / 60).rounded()
                    sticker.notifyOffsetMinutes = StickyNotify.snapDown(Int(minutes))
                } else {
                    sticker.deadline = reminder
                    sticker.notifyOffsetMinutes = 0
                }
            }
            try save()
        } catch {
            // ❗ Тут ціна помилки найвища: `reminder` уже занулений, і
            // автозбереження SwiftData винесло б це в базу попри збій —
            // наступний запуск не знайшов би чого переносити, а
            // нагадування зникло б назавжди. Відкочуємо власноруч:
            // `context.rollback()` значень уже змінених обʼєктів не
            // повертає (перевірено тестом 2026-08-20)
            for item in touched {
                item.sticker.reminder = item.reminder
                item.sticker.deadline = item.deadline
                item.sticker.notifyOffsetMinutes = item.offset
            }
            NSLog("Embar: міграція нагадувань не вдалась — %@",
                  error.localizedDescription)
            return
        }

        // Заплановані сповіщення стояли на старий час — переставляємо ті,
        // яких це торкнулось (інші під старими правилами й не планувались).
        // Дозволу тут не питаємо: якщо його не було, то й планувати не було
        // чого, а прохання просто так, на старті, було б грубим
        for sticker in migrated { ReminderScheduler.replan(for: sticker) }
        NSLog("Embar: нагадування злито в дедлайн — перенесено стіків: %d",
              migrated.count)
    }

    // MARK: - Тести

    /// Скидання прапорців — лише для юніт-тестів (у них EmbarDefaults.store
    /// це окремий суїт, реальних налаштувань не торкаємось)
    static func resetFlagsForTesting() {
        EmbarDefaults.store.removeObject(forKey: autoArchiveFlagKey)
    }
}
