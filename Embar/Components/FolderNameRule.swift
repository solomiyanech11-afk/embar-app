//
//  FolderNameRule.swift
//  Embar
//
//  Єдиний ліміт довжини назв контейнерів - папок нотаток/рідера і стін
//  стіків (R4 тест-плану). Перевіряється у полях створення (NewChipField,
//  FolderPickerList): понад ліміт - червона пігулка з поясненням, Enter
//  не спрацьовує. Наявні довші назви не ламаються - рендер скрізь
//  обрізається трикрапкою (truncatedChip).
//

import Foundation

enum FolderNameRule {
    /// Орієнтир із тест-плану - 50-100; беремо нижню межу: назва живе
    /// в чіпах і пігулках, де довше однаково не видно
    static let maxLength = 50

    /// Жорсткий блок (рішення Mia 04.09): понад ліміт написати НЕ можна -
    /// зайве зрізається одразу при вводі/вставці, а пігулка пояснює чому.
    /// prefix по Character, тож емоджі/кластери не ріжуться посередині
    static func clamped(_ name: String) -> String {
        String(name.prefix(maxLength))
    }

    static func exceeds(_ name: String) -> Bool {
        name.count > maxLength
    }

    /// Текст пігулки - один для всіх полів
    static var message: String {
        String(localized: "Максимум 50 символів",
               comment: "Пігулка при спробі ввести довшу назву папки/стіни")
    }
}
