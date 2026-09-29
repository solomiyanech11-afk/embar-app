//
//  StickyAutoArchive.swift
//  Embar
//
//  Автоархів стіків: виконаний стік тихо йде в архів через заданий строк.
//
//  Рішення 2026-08-19: автоархів УВІМКНЕНИЙ ЗАВЖДИ. Вимкнути його не можна
//  ні глобально, ні на окремому стіку, індивідуальних строків теж немає —
//  на всю поверхню один глобальний строк із налаштувань. Це єдине місце,
//  де він читається, щоб налаштування, обслуговування бази і тексти не
//  розʼїхались.
//

import Foundation

enum StickyAutoArchive {
    /// Ключ у налаштуваннях (історична назва; лишаємо, щоб не втратити
    /// вибір тих, хто вже виставив строк)
    static let storageKey = "globalAutoArchiveDays"

    /// Дефолт — місяць
    static let defaultDays = 30

    /// Строки, які пропонує UI: тиждень / місяць / три місяці
    static let options = [7, 30, 90]

    /// Діючий строк у днях. Будь-яке значення поза набором (зокрема старий
    /// 0 = «Вимк») читається як дефолт — вимкненого стану більше не існує
    static var days: Int {
        let stored = EmbarDefaults.store.integer(forKey: storageKey)
        return options.contains(stored) ? stored : defaultDays
    }

    // MARK: - Зміна строку не діє заднім числом (ревʼю 2026-08-20)

    /// Коли строк востаннє змінили
    static let termChangedKey = "autoArchiveTermChangedAt"

    /// Момент останньої зміни строку. Відлік автоархіву не починається
    /// раніше за нього НІ ДЛЯ ОДНОГО стіка: інакше перемикання «3 місяці
    /// → 1 тиждень» відправило б в архів усе виконане давніше за тиждень
    /// тим самим запуском — пачкою, мовчки і без вороття. Після зміни
    /// строку кожен стік отримує повний новий строк на стіні
    static var termChangedAt: Date? {
        EmbarDefaults.store.object(forKey: termChangedKey) as? Date
    }

    /// Кличе UI одразу після того, як людина вибрала інший строк
    static func noteTermChange(at moment: Date = .now) {
        EmbarDefaults.store.set(moment, forKey: termChangedKey)
    }
}
