//
//  Typography.swift
//  Embar
//
//  Шрифти Embar (Embar.md §9.1):
//  · Inter — весь UI (ваги 300/400/500/600)
//  · Fraunces — character-моменти: назви нотаток/книг, hero на Home,
//    empty states, розділові моменти в Рідері (варіативний, opsz 9–144 —
//    оптичний розмір CoreText підбирає автоматично під кегль)
//
//  Файли лежать у Embar/Fonts/ (SIL OFL), реєструються при старті —
//  див. FontRegistrar.registerBundledFonts()
//

import SwiftUI
import CoreText
import AppKit

enum FontRegistrar {
    /// Реєструє шрифти з бандла для цього процесу. Викликати один раз при старті.
    static func registerBundledFonts() {
        let names = [
            "Inter-Light", "Inter-Regular", "Inter-Medium", "Inter-SemiBold",
            "Fraunces-Variable", "Fraunces-Italic-Variable",
        ]
        let urls = names.compactMap { name in
            Bundle.main.url(forResource: name, withExtension: "otf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf")
        }
        guard !urls.isEmpty else {
            NSLog("Embar: у бандлі не знайдено жодного шрифту")
            return
        }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { errors, done in
            let errs = errors as! [CFError]
            if !errs.isEmpty {
                NSLog("Embar: помилки реєстрації шрифтів: \(errs)")
            }
            return true
        }
        #if DEBUG
        // Контроль, що шрифти реально доступні процесу (видно в консолі Xcode)
        let interOK = NSFont(name: "Inter-Regular", size: 12) != nil
        let frauncesOK = NSFont(name: "Fraunces", size: 12) != nil
        NSLog("Embar fonts: Inter=\(interOK ? "ok" : "MISSING"), Fraunces=\(frauncesOK ? "ok" : "MISSING")")
        #endif
    }
}

extension Font {
    /// UI-шрифт (Inter). Ваги 300–600 за Embar.md §9.1
    static func emUI(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // Статичні файли Inter мають окремі PostScript-імена — мапимо вагу напряму,
        // щоб не залежати від системного добору
        let name: String
        switch weight {
        case .light: name = "Inter-Light"
        case .medium: name = "Inter-Medium"
        case .semibold: name = "Inter-SemiBold"
        default: name = "Inter-Regular"
        }
        return .custom(name, size: size)
    }

    /// Display-шрифт (Fraunces) для character-моментів.
    /// ❗ Italic: .custom("Fraunces Italic") тихо падає в системний шрифт —
    /// резолвимо через NSFont з тими ж фолбеками, що NoteTypography (M4)
    static func emDisplay(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        if italic {
            for name in ["Fraunces-Italic", "Fraunces Italic"] {
                if let nsFont = NSFont(name: name, size: size) { return Font(nsFont) }
            }
            let desc = NSFontDescriptor(fontAttributes: [.family: "Fraunces Italic"])
            if let nsFont = NSFont(descriptor: desc, size: size),
               nsFont.familyName?.contains("Fraunces") == true { return Font(nsFont) }
            return .custom("Fraunces Italic", size: size)
        }
        return .custom("Fraunces", size: size).weight(weight)
    }
}
