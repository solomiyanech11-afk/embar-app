//
//  StickyFilter.swift
//  Embar
//
//  Фільтри стіків (SPEC §2.3). Ортогонально: вибрана СТІНА (walls bar) +
//  вид ФІЛЬТРА (з налаштувань). Тут — види фільтра і функція відбору.
//

import Foundation

enum StickyFilterKind: String, CaseIterable, Identifiable {
    // «Закріплені» видалено зовсім (фідбек 2026-07-19 — звільнити місце
    // під емоджі-чіпи); .archive лишився як стан, але з чіпів прибраний —
    // вхід через рядок «Архів →» внизу листа налаштувань
    // «Нагадування» видалено (2026-08-19): нагадування злилося з дедлайном,
    // окремого стану більше немає
    case all, today, deadline, done, archive
    var id: String { rawValue }

    /// Не View, тому переклад тягнемо явно через String(localized:)
    var label: String {
        switch self {
        case .all: String(localized: "Всі", comment: "Чіп фільтра стіків")
        case .today: String(localized: "Сьогодні", comment: "Чіп фільтра стіків")
        case .deadline: String(localized: "Дедлайн", comment: "Чіп фільтра стіків")
        case .done: String(localized: "Виконані", comment: "Чіп фільтра стіків")
        case .archive: String(localized: "Архів", comment: "Чіп фільтра стіків")
        }
    }
}

enum StickyFilter {
    /// Чи проходить стік крізь фільтр (стіна + вид + емоджі-тег).
    /// Видалені — ніколи. Інваріант крос-поверхневих лінків: будь-який
    /// НЕ видалений стік досяжний через «Всі»+all (рішення §15.50 —
    /// hiddenFromWall скасовано, «невидимих» станів не існує)
    /// ❗ Логіка живе в StickySnapshot.matches (F5, 2026-08-28): фільтр
    /// мусить давати той самий вердикт і по живому обʼєкту, і по зліпку
    /// в кеші зрізу — інакше патч і перерахунок розійшлись би
    static func matches(_ sticker: Sticker, kind: StickyFilterKind,
                        wall: Wall?, emoji: String? = nil) -> Bool {
        StickySnapshot(sticker).matches(kind: kind, wallID: wall?.id, emoji: emoji)
    }
}
