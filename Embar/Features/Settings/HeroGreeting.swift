//
//  HeroGreeting.swift
//  Embar
//
//  Імʼя для привітання на першій hero-картці Settings (SPEC §6).
//
//  Було зашито «Solomiia» — залишок часів, коли застосунок будувався
//  для однієї людини. Коротко пробували брати імʼя з macOS-акаунта
//  (NSFullUserName), але від цього відмовились: імʼя облікового запису
//  — не те саме, що імʼя, яким людина хоче, щоб її звали. Питатимемо
//  при онбордингу (окремий крок).
//
//  Поки поля вводу ще немає, значення просто порожнє — і тоді вітаємось
//  БЕЗ імені: «Hey» / «Привіт», а не заглушка «Hey, User».
//

import Foundation

enum HeroGreeting {
    /// Ключ UserDefaults; той самий читає @AppStorage у hero, і його ж
    /// заповнить онбординг
    static let storageKey = "userName"

    /// Стеля довжини. Онбординг обріже при вводі, але кламп тримаємо
    /// і тут: у сховище значення може прийти й іншим шляхом (міграція,
    /// sync), а в hero воно малюється 26-м кеглем — довге просто
    /// нікуди не влізе
    static let maxLength = 30

    /// Імʼя для показу; nil — якщо його не задали
    static func name(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Значення, придатне для збереження: без країв і не довше стелі.
    /// Обрізаємо ПО СИМВОЛАХ (не байтах) — інакше емодзі чи літера
    /// з діакритикою розпалась би навпіл
    static func clamped(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Сховище

    static var stored: String {
        EmbarDefaults.store.string(forKey: storageKey) ?? ""
    }

    static func store(_ raw: String) {
        EmbarDefaults.store.set(clamped(raw), forKey: storageKey)
    }
}
