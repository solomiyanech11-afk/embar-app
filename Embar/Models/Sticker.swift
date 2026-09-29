//
//  Sticker.swift
//  Embar
//
//  Стік — швидка думка (fleeting note). SPEC.md §11.1
//

import Foundation
import SwiftData

@Model
final class Sticker {
    // Спільні поля (CloudKit-правила: все з default, без @Attribute(.unique))
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Soft-delete: не видаляємо одразу, ставимо дату (фізична чистка через 30 днів)
    var deletedAt: Date? = nil

    /// Основний текст (заголовок на картці й у expanded-редакторі)
    var text: String = ""
    /// Додаткові нотатки з expanded-редактора (`.expanded-textarea` у прототипі).
    /// Наявність показується бейджем «…» на картці
    var bodyText: String = ""
    /// 0–4 → один з 5 кольорів активної палітри (--sticky-1..5)
    var colorIndex: Int = 0
    var done: Bool = false
    var pinned: Bool = false
    var archived: Bool = false
    var deadline: Date? = nil
    /// За скільки хвилин ДО дедлайну прийде сповіщення: 0 — у момент,
    /// 5/30/60/1440 — за 5 хв / 30 хв / годину / день. nil — дедлайн без
    /// сповіщення (рішення 2026-08-19: нагадування злилося з дедлайном).
    /// CloudKit-safe: optional, additive
    var notifyOffsetMinutes: Int? = nil
    /// ⚰️ DEPRECATED (2026-08-19): нагадування більше не окрема сутність —
    /// воно стало дедлайном плюс `notifyOffsetMinutes`. Поле лишається в
    /// схемі за CloudKit-правилами; читає його лише міграція
    var reminder: Date? = nil
    /// ⚰️ DEPRECATED (2026-08-19): автоархів тепер завжди ввімкнений і має
    /// один глобальний строк (StickyAutoArchive). Обидва поля лишаються в
    /// схемі за CloudKit-правилами і НІДЕ не використовуються
    var autoArchiveOff: Bool = false
    var autoDeleteAt: Date? = nil
    /// Коли стік потрапив в архів — старт відліку «30 днів і видалення»
    /// (рішення 2026-07-21). CloudKit-safe: optional, additive
    var archivedAt: Date? = nil
    /// Коли почався відлік автоархіву — тобто момент, коли стік СТАВ
    /// кандидатом (його виконали; або правила змінились так, що він ним
    /// став). Ніколи не заднім числом.
    ///
    /// ❗ Раніше відлік ішов від `updatedAt`, і будь-яка зміна правил
    /// відправляла в архів усе давно виконане тим самим запуском, мовчки
    /// і без вороття (ревʼю 2026-08-20). Головний біль тут не в тому, що
    /// стік поїде в архів, а в тому, що поїде ОДРАЗУ і пачкою.
    /// CloudKit-safe: optional, additive
    var archiveCountdownAt: Date? = nil
    /// Емоджі-тег стіка (фідбек 2026-07-19): видно на картці, фільтр у
    /// налаштуваннях стіни. CloudKit-safe: optional, additive
    var emojiTag: String? = nil

    // Стік-віджет на робочому столі (SPEC §2.7, 2026-07-30).
    // CloudKit-safe: усі з default, additive
    /// Стік відкріплено на робочий стіл (вікно-віджет).
    /// Інваріант: вікно існує ⇔ isFloating && deletedAt == nil && !archived
    var isFloating: Bool = false
    /// Позиція і розмір вікна-віджета (екранні координати). floatY —
    /// ВЕРХНІЙ край (maxY): якір авто-висоти; збереження за нижнім
    /// зсувало віджет після перезапуску (ревʼю 2026-07-30, Б2).
    /// nil розміру = авто; ручний ресайз фіксує floatW/floatH
    var floatX: Double? = nil
    var floatY: Double? = nil
    var floatW: Double? = nil
    var floatH: Double? = nil
    /// Режим відображення віджета: "title" (лише заголовок) | "full" (+bodyText)
    var floatDisplayMode: String = "title"
    /// Стиль скла віджета: "color" (тінт кольору стіка) | "dark" | "light" |
    /// "liquid" (нативний Liquid Glass, лише macOS 26+; нижче — fallback color)
    var floatStyle: String = "color"
    /// Розмір тексту віджета: "s" | "m" | "l"
    var floatTextSize: String = "m"
    /// ⚰️ DEPRECATED (рішення §15.50, 2026-07-30): «прибрати лише з
    /// панелі» скасовано — стан «стік-невидимка» був коренем класу багів
    /// втрати даних (code review). Поле лишається в схемі за CloudKit-
    /// правилами (additive, не видаляти), НІДЕ не використовувати
    var hiddenFromWall: Bool = false

    // Зв'язки (CloudKit: усі optional; inverse оголошено на протилежному боці)
    /// Стіна, на якій живе стік (nil = «Всі»)
    var wall: Wall? = nil
    /// Нотатка, що виросла з цього стіка (matureSticky). Зворотний бік — Note.sourceSticker
    var note: Note? = nil

    init(text: String = "", colorIndex: Int = 0) {
        self.text = text
        self.colorIndex = colorIndex
    }
}
