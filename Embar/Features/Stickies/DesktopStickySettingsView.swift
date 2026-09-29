//
//  DesktopStickySettingsView.swift
//  Embar
//
//  Попап-острівець налаштувань стіка-віджета (SPEC §2.7, референс
//  2026-07-30): відкривається кнопкою ≡ збоку віджета і вдягнений У ТОЙ
//  САМИЙ стиль, що його стік (спільний DesktopStickyBackdrop). Стиль
//  (колір стіка / темне / світле), розмір тексту S/M/L, «Зробити за
//  замовчуванням» — застосовує стиль+розмір до ВСІХ наявних віджетів
//  і зберігає як дефолт для майбутніх (окремі зміни після — поверх).
//

import SwiftUI
import SwiftData

struct DesktopStickySettingsView: View {
    @Bindable var sticker: Sticker

    @Environment(\.modelContext) private var context

    @AppStorage("desktopStickyDefaultStyle") private var defaultStyle = "color"
    @AppStorage("desktopStickyDefaultSize") private var defaultSize = "m"
    // Колір стіка — ті самі ключі, що у віджета (живе перефарбування)
    @AppStorage("palette") private var paletteSlug = Palette.defaultSlug
    @AppStorage("wallColorMode") private var colorMode = "random"
    @AppStorage("noWallColorSlot") private var noWallSlot = 0

    /// Зворотний звʼязок «Збережено ✓» на кнопці дефолтів
    @State private var savedDefaults = false

    // Liquid Glass скасовано (2026-07-30) — лише ці три
    private let styles: [(key: String, label: LocalizedStringKey)] = [
        ("color", "Колір стіка"),
        ("dark", "Темне скло"),
        ("light", "Світле скло"),
    ]

    // MARK: - Токени в стилі СВОГО стіка — спільні WidgetStyleTokens
    // (знахідка 10 code review: жодних ручних копій альф)

    private var tokens: WidgetStyleTokens {
        WidgetStyleTokens(sticker: sticker, paletteSlug: paletteSlug,
                          colorMode: colorMode, noWallSlot: noWallSlot)
    }
    private var effectiveStyle: String { tokens.style }
    private var color: Color { tokens.color }
    private var ink: Color { tokens.ink }
    private var ink2: Color { tokens.ink2 }
    private var ink3: Color { tokens.ink3 }
    // Заливки — специфіка попапа (у віджета плашок нема), від isDark токенів
    private var fillIdle: Color { tokens.isDark ? .white.opacity(0.1) : .black.opacity(0.06) }
    private var fillSelected: Color { tokens.isDark ? .white.opacity(0.88) : .black.opacity(0.55) }
    private var textOnSelected: Color { tokens.isDark ? .black.opacity(0.8) : .white }
    private var divider: Color { tokens.isDark ? .white.opacity(0.15) : .black.opacity(0.08) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Стиль")
                .font(.emUI(10.5, weight: .medium))
                .foregroundStyle(ink3)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(styles, id: \.key) { style in
                    styleRow(style.key, style.label)
                }
            }

            Rectangle().fill(divider).frame(height: 1)
                .padding(.vertical, 2)

            Text("Розмір тексту")
                .font(.emUI(10.5, weight: .medium))
                .foregroundStyle(ink3)
            HStack(spacing: 4) {
                sizeChip("s", "S")
                sizeChip("m", "M")
                sizeChip("l", "L")
            }

            Rectangle().fill(divider).frame(height: 1)
                .padding(.vertical, 2)

            Button(action: makeDefault) {
                Text(savedDefaults ? "Застосовано ✓" : "Зробити за замовчуванням")
                    .font(.emUI(11, weight: .medium))
                    .foregroundStyle(ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(fillIdle))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 186)
        .background(DesktopStickyBackdrop(style: effectiveStyle, color: color))
    }

    /// Поточний стиль+розмір → усі НАЯВНІ віджети + дефолт для майбутніх
    /// (фідбек 2026-07-30); окрема зміна конкретного віджета після —
    /// поверх, як завжди. Скрізь ЕФЕКТИВНИЙ стиль: спадковий "liquid"
    /// нормалізується в "color", не розповзається дефолтом (знахідка 6)
    private func makeDefault() {
        defaultStyle = effectiveStyle
        defaultSize = sticker.floatTextSize
        let descriptor = FetchDescriptor<Sticker>(
            predicate: #Predicate { $0.isFloating == true })
        for other in (try? context.fetch(descriptor)) ?? [] {
            guard other.floatStyle != effectiveStyle
                || other.floatTextSize != sticker.floatTextSize else { continue }
            other.floatStyle = effectiveStyle
            other.floatTextSize = sticker.floatTextSize
            other.updatedAt = .now
        }
        savedDefaults = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            savedDefaults = false
        }
    }

    // MARK: - Рядки вибору

    private func styleRow(_ key: String, _ label: LocalizedStringKey) -> some View {
        // Порівняння через ЕФЕКТИВНИЙ стиль: спадковий "liquid"
        // рендериться як color — галочка стоїть на «Колір стіка»,
        // а не «ніде» (знахідка 6)
        Button {
            sticker.floatStyle = key
            sticker.updatedAt = .now
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ink)
                    .opacity(effectiveStyle == key ? 1 : 0)
                Text(label)
                    .font(.emUI(11.5))
                    .foregroundStyle(ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(effectiveStyle == key ? fillIdle : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func sizeChip(_ key: String, _ label: LocalizedStringKey) -> some View {
        Button {
            sticker.floatTextSize = key
            sticker.updatedAt = .now
        } label: {
            Text(label)
                .font(.emUI(11, weight: .medium))
                .foregroundStyle(sticker.floatTextSize == key ? textOnSelected : ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Capsule().fill(sticker.floatTextSize == key
                                           ? fillSelected : fillIdle))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
