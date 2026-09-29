//
//  StickyHeightEstimator.swift
//  Embar
//
//  Оцінка висоти картки стіка для розкладання по колонках БЕЗ створення
//  вьюхи (перф-фікс 2026-08-16, пара до LazyTwoColumnMasonry). Міряє
//  текст тим самим шрифтом і міжряддям, що StickyCard, тож оцінка — це
//  фактично реальна висота; решта рядків картки — фіксовані добавки.
//
//  Кеш — ОДИН запис на стік: повторні розкладки (перемикання фільтрів,
//  скрол, ресайз у межах кванта) віддають число з словника. Ширину
//  квантуємо по 16pt: під час ресайзу панелі оцінка не перераховує
//  тисячі текстів на кожен кадр, а баланс колонок від цього не страждає.
//
//  ❗ Ключ — id стіка, а НЕ його текст (ревʼю 2026-08-18, знахідка 6).
//  Спершу ключем був рядок «бакет|повний текст», і виселення не було
//  взагалі: кожне натискання клавіші в розгорнутому стіку, кожен новий
//  бакет ширини додавали ПОСТІЙНИЙ запис. На стрес-стіні сесія
//  накопичувала десятки тисяч записів — другу копію всього корпусу
//  текстів на весь час життя панелі. Тепер новий текст чи інша ширина
//  ПЕРЕЗАПИСУЮТЬ запис стіка, кеш не більший за саму стіну, а повного
//  тексту не тримає взагалі — лише його хеш.
//
//  Референс-клас навмисно: живе у @State вьюхи як контейнер, мутація
//  кеша НЕ інвалідовує SwiftUI (це кеш, а не стан).
//

import AppKit

final class StickyHeightEstimator {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    /// Виміряна висота тексту + за яких умов вона дійсна
    private struct Entry {
        let bucket: CGFloat
        /// Хеш тексту замість самого тексту: копія корпусу нам не потрібна,
        /// а ціна малоймовірної колізії — трохи інша ОЦІНКА висоти, тобто
        /// пікселі в балансі колонок (картки все одно кладуться за
        /// реальною висотою)
        let textHash: Int
        let height: CGFloat
    }

    private var textHeights: [UUID: Entry] = [:]

    /// Скільки записів у кеші (для тестів: він не сміє рости від друку)
    var cachedCount: Int { textHeights.count }

    /// Ті самі значення, що в StickyCard (font .emUI(14), lineSpacing 3,
    /// padding 12, minHeight 80)
    private static let font = NSFont(name: "Inter-Regular", size: 14)
        ?? .systemFont(ofSize: 14)
    private static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        return p
    }()

    func height(for sticker: Sticker, colWidth: CGFloat) -> CGFloat {
        // Ширина тексту = колонка мінус горизонтальний паддінг картки
        let textWidth = max(colWidth - 24, 40)
        // Квант 16pt: ресайз панелі не перемірює всі тексти щокадру
        let bucket = (textWidth / 16).rounded(.down) * 16

        let text = sticker.text.isEmpty ? " " : sticker.text
        let textHash = text.hashValue
        let textHeight: CGFloat
        if let cached = textHeights[sticker.id],
           cached.bucket == bucket, cached.textHash == textHash {
            textHeight = cached.height
        } else {
            let rect = (text as NSString).boundingRect(
                with: NSSize(width: bucket, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: Self.font, .paragraphStyle: Self.paragraph])
            textHeight = rect.height.rounded(.up)
            // Перезапис, не додавання: на стік завжди рівно один запис
            textHeights[sticker.id] = Entry(bucket: bucket, textHash: textHash,
                                            height: textHeight)
        }

        // Фіксовані добавки — рядки картки за StickyCard:
        var h = textHeight + 24                       // паддінг 12×2
        if !sticker.bodyText.isEmpty { h += 17 }      // «…» 11pt + 3
        if sticker.deadline != nil { h += 17 }        // бейдж 10pt + 4
        h += 21                                       // час 10pt + 8
        return max(h, 80)                             // minHeight картки
    }
}
