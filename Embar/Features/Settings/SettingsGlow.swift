//
//  SettingsGlow.swift
//  Embar
//
//  Разова підказка на шестерні в хедері панелі: поки людина жодного
//  разу не відкривала загальні налаштування, сама іконка тихо блимає
//  з сірої на брендову червону. За нею живе вся кастомізація - палітри,
//  фон панелі, Hidden Gems, - а сама вона маленька й приглушена, і її
//  просто не помічали (фідбек 2026-08-11).
//
//  Спочатку це був мʼякий ореол-пляма ПІД іконкою - виглядав як бруд;
//  замінено на блимання кольору самого гліфа (фідбек 2026-08-12).
//
//  Гасне НАЗАВЖДИ при першому ж відкритті: це підказка, а не прикраса.
//  Прапорець - у тому самому сховищі, що решта (EmbarDefaults), тож у
//  пісочниці він скидається разом з онбордингом.
//
//  Свідомий виняток із правила руху (§7.2-A): дихання тут і є
//  повідомленням - як світіння на краю екрана в онбордингу.
//

import SwiftUI

enum SettingsGlow {
    static let storageKey = "appSettingsOpened"
}

/// Іконка налаштувань для хедера. Коли `blinking` - гліф дихає
/// сірий ↔ червоний; інакше це звичайна приглушена іконка,
/// байт-у-байт як інші headerIcon (ink + opacity 0.5).
struct SettingsBlinkIcon: View {
    let blinking: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    /// Брендовий червоний, а НЕ акцент палітри: у Cream акцент - теплий
    /// вохристий (#c97a3a), і підказка читалася як помаранчева пляма
    /// (фідбек 2026-08-11)
    private var accent: Color { EmbarColors.brandRed }

    var body: some View {
        // Два гліфи один над одним: анімується лише opacity верхнього
        // (червоного) - на відміну від кольору в foregroundStyle,
        // opacity гарантовано інтерполюється
        ZStack {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15))
                .foregroundStyle(EmbarColors.ink)
                .opacity(0.5)
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15))
                .foregroundStyle(accent)
                .opacity(accentOpacity)
                .animation(blinking && !reduceMotion
                           ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                           : nil,
                           value: pulsing)
        }
        .onAppear { pulsing = true }
    }

    private var accentOpacity: Double {
        guard blinking else { return 0 }
        // Reduce Motion: без блимання, просто спокійний червоний -
        // підказка лишається, рух зникає
        if reduceMotion { return 1 }
        return pulsing ? 1 : 0
    }
}
