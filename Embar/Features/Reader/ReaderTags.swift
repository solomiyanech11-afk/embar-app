//
//  ReaderTags.swift
//  Embar
//
//  #Хештеги рідера (SPEC §4.3; прототип processReaderHashtags/getTagColor).
//  Теги НЕ зберігаються — парсяться з тексту при рендері. Колір тега
//  детермінований: FNV-1a по UTF-16 + murmur-фіналізер — біт-у-біт як у
//  прототипі (перевірено проти JS у тестах).
//
//  ❗ Кольори капсул — З АКТИВНОЇ ПАЛІТРИ (P2.25, відхід від прототипу):
//  фон = один із 5 стік-кольорів (хеш імені → слот), текст = той самий
//  відтінок, насичений і затемнений до контрасту WCAG 4.5:1 — та сама
//  філософія, що адаптивне чорнило стіків (StickyInk, §15.57). Фіксовані
//  10 пастельних пар прототипу (TAG_COLOR_PALETTE) прибрано.
//

import AppKit
import SwiftUI

enum ReaderTags {

    struct Match: Equatable {
        /// Імʼя без «#»
        let name: String
        /// Діапазон разом із «#» (UTF-16, для AttributedString-рендеру)
        let range: NSRange
    }

    /// Той самий клас символів, що в прототипі
    private static let regex = try! NSRegularExpression(
        pattern: "#([\\wа-яіїєґА-ЯІЇЄҐ]+)")

    /// Всі #теги в тексті в порядку появи (з повторами)
    static func matches(in text: String) -> [Match] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { Match(name: ns.substring(with: $0.range(at: 1)), range: $0.range) }
    }

    /// Унікальні теги записів, відсортовані (для «Теги ▾»; прототип
    /// getReaderBookTags)
    static func uniqueTags(in texts: [String]) -> [String] {
        var set = Set<String>()
        for text in texts {
            for match in matches(in: text) { set.insert(match.name) }
        }
        return set.sorted()
    }

    /// Прибирає і пробіл перед тегом — як прототипний /\s*#…/g
    private static let stripRegex = try! NSRegularExpression(
        pattern: "\\s*#([\\wа-яіїєґА-ЯІЇЄҐ]+)")

    /// Текст без тегів (для тіла цитати; прототип strip + trim)
    static func stripped(_ text: String) -> String {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return stripRegex.stringByReplacingMatches(
            in: text, range: full, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Індекс кольору: FNV-1a (UTF-16 code units) + murmur3-фіналізер,
    /// Math.abs від signed int32 — точна копія JS getTagColor. Кошики
    /// параметром: продакшн ділить на 5 стік-кольорів палітри, тести
    /// звіряють хеш із прототипом на його 10 кошиках
    static func colorIndex(for name: String, buckets: Int) -> Int {
        var h: UInt32 = 2166136261
        for unit in name.utf16 {
            h ^= UInt32(unit)
            h = h &* 16777619
        }
        h ^= h >> 16
        h = h &* 0x85ebca6b
        h ^= h >> 13
        h = h &* 0xc2b2ae35
        h ^= h >> 16
        let signed = Int32(bitPattern: h)
        let absolute = signed.magnitude
        return Int(absolute % UInt32(buckets))
    }

    // MARK: - Капсула з активної палітри (P2.25)

    struct Capsule: Equatable {
        let bg: Color
        let fg: Color
    }

    /// Кольори капсули тега під активну палітру: фон — стік-колір за
    /// хешем імені, текст — читабельний тон того ж відтінку
    static func capsule(for name: String, palette: Palette) -> Capsule {
        let index = colorIndex(for: name, buckets: palette.sticky.count)
        let bg = palette.sticky[index]
        return Capsule(bg: bg, fg: capsuleInk(on: bg, cacheKey: "\(palette.slug)#\(index)"))
    }

    /// Текст капсули: той самий відтінок, що фон, насичений і затемнений
    /// до WCAG 4.5:1 (як прототипні пари bg/fg, але виведено з палітри).
    /// Темний стік-слот (нині лише Ponyo-5) перевертає текст у білий —
    /// те саме правило, що в StickyInk. Слотів скінченно — кешуємо
    private static var inkCache: [String: Color] = [:]

    private static func capsuleInk(on background: Color, cacheKey: String) -> Color {
        if let cached = inkCache[cacheKey] { return cached }
        let ink = deriveInk(on: background)
        inkCache[cacheKey] = ink
        return ink
    }

    private static func deriveInk(on background: Color) -> Color {
        guard let bg = NSColor(background).usingColorSpace(.sRGB) else {
            return EmbarColors.ink2
        }
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        bg.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
        // Тон того ж відтінку на КОНКРЕТНУ яскравість: насиченість ~×3
        // від пастелі (як у прототипних пар), а нижче 0.3 гасне разом із
        // яскравістю — інакше майже чорний тон застрягав на кольоровому
        // залишку і середньо-темні слоти (matcha, terracotta) не
        // дотягували до контрасту
        func tone(_ brightness: CGFloat) -> NSColor {
            let s = min(max(sat * 3, 0.4), 0.75)
                * (brightness < 0.3 ? brightness / 0.3 : 1)
            return NSColor(hue: hue, saturation: s,
                           brightness: brightness, alpha: 1)
        }
        // Темний кандидат: від прототипної яскравості 0.52 темнішає,
        // поки не досягне порога StickyInk (4.5) або дна
        var dark = tone(0.52)
        var brightness: CGFloat = 0.52
        while contrast(dark, bg) < 4.5, brightness > 0.08 {
            brightness -= 0.04
            dark = tone(brightness)
        }
        // Темний слот (нині лише Ponyo-5) темним текстом не врятувати —
        // перевертаємо в білий, як StickyInk. Вибір за фактичним
        // контрастом, а не порогом яскравості: поріг відправляв у білий
        // і середньо-темні слоти, де білий програє
        let white = NSColor(white: 1, alpha: 0.92)
        if contrast(dark, bg) < 4.5, contrast(white, bg) > contrast(dark, bg) {
            return .white.opacity(0.92)
        }
        return Color(nsColor: dark)
    }

    /// Відносна яскравість sRGB (WCAG); формула та сама, що в StickyInk
    private static func luminance(_ color: NSColor) -> CGFloat {
        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.redComponent)
            + 0.7152 * channel(color.greenComponent)
            + 0.0722 * channel(color.blueComponent)
    }

    private static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB)
        else { return 0 }
        let l1 = luminance(x), l2 = luminance(y)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
