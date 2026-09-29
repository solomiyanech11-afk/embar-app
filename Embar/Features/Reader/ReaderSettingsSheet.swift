//
//  ReaderSettingsSheet.swift
//  Embar
//
//  Глобальні налаштування рідера (SPEC §4.4, крок 15): сторінки ·
//  хештеги · додаткові типи (Питання/Інсайт) · шрифт записів.
//  Живуть в AppStorage (прототип readerSettings + reader-font-класи).
//  Анатомія 1:1 з NoteSettingsSheet (консистентність). Шрифти —
//  Inter / Fraunces / системний Mono (рішення §15.25: Lora й Source
//  Serif зі старої специфікації не бандлимо).
//

import SwiftUI

/// Шрифт тіла записів (цитати завжди Fraunces italic — не залежать).
/// 4 опції без нових бандлів (§15.25: Lora/Source Serif не бандлимо):
/// warm-сериф — Fraunces, академічний — системний Charter
enum ReaderBodyFont: String {
    case inter, serif, charter, mono

    /// Обраний шрифт застосовується по всьому блокноту — тіло, назва,
    /// лінк, кнопки типів (фідбек 2026-07-07)
    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .inter: return .emUI(size, weight: weight)
        case .serif: return .emDisplay(size, weight: weight)
        case .charter: return .custom("Charter", size: size).weight(weight)
        case .mono: return .system(size: size - 0.5, weight: weight,
                                   design: .monospaced)
        }
    }

    /// Fraunces italic для цитат — той самий NSFont у SwiftUI-показі і в
    /// NSTextView, щоб розмір не «стрибав» (фідбек 2026-07-13)
    static func quoteNSFont(_ size: CGFloat = 14.5) -> NSFont {
        NSFont(name: "Fraunces-Italic", size: size)
            ?? NSFont(name: "Fraunces Italic", size: size)
            ?? .systemFont(ofSize: size)
    }

    func nsFont(_ size: CGFloat) -> NSFont {
        switch self {
        case .inter:
            return NSFont(name: "Inter-Regular", size: size)
                ?? .systemFont(ofSize: size)
        case .serif:
            return NSFont(name: "Fraunces", size: size)
                ?? .systemFont(ofSize: size)
        case .charter:
            return NSFont(name: "Charter-Roman", size: size)
                ?? NSFont(name: "Charter", size: size)
                ?? .systemFont(ofSize: size)
        case .mono:
            return .monospacedSystemFont(ofSize: size - 0.5, weight: .regular)
        }
    }
}

struct ReaderSettingsSheet: View {
    @AppStorage("readerHashtags") private var hashtags = true
    @AppStorage("readerShowSourceLink") private var showSourceLink = true
    @AppStorage("readerExtraTypes") private var extraTypes = false
    @AppStorage("readerFont") private var fontRaw = ReaderBodyFont.inter.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Налаштування")
                .font(.emUI(18, weight: .semibold))
                .foregroundStyle(EmbarColors.ink)
            Text("Тонкі налаштування записів рідера")
                .font(.emUI(12))
                .foregroundStyle(EmbarColors.ink3)
                .padding(.top, 2)

            sectionLabel("Шрифт записів")
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    fontCard(.inter, name: "Inter", sub: "Sans · default",
                             sampleFont: .emUI(14.5))
                    fontCard(.serif, name: "Fraunces", sub: "Serif · warm",
                             sampleFont: .emDisplay(14.5))
                }
                HStack(spacing: 8) {
                    fontCard(.charter, name: "Charter", sub: "Serif · academic",
                             sampleFont: .custom("Charter", size: 14.5))
                    fontCard(.mono, name: "Mono", sub: "Mono · typewriter",
                             sampleFont: .system(size: 13.5, design: .monospaced))
                }
            }

            sectionLabel("Записи")
            VStack(spacing: 0) {
                toggleRow("Рядок джерела", subtitle: "Посилання і зміна фото під шапкою",
                          isOn: $showSourceLink)
                Divider().overlay(EmbarColors.line)
                toggleRow("Хештеги", subtitle: "#теги стають кольоровими чіпами",
                          isOn: $hashtags)
                Divider().overlay(EmbarColors.line)
                toggleRow("Додаткові типи", subtitle: "Питання та Інсайт у типах запису",
                          isOn: $extraTypes)
            }

            sectionLabel("Теми")
            VStack(alignment: .leading, spacing: 7) {
                hintRow("bookmark",
                        "Кнопка «Тема» починає нове русло - все, що пишеш, лягає під його заголовок. Повторне натискання завершує тему.")
                hintRow("arrowtriangle.down.fill",
                        "Клік по трикутнику згортає записи теми, подвійний клік - усі теми блокнота разом.")
                hintRow("character.cursor.ibeam",
                        "Клік по назві теми продовжує її - нові записи знову йдуть у це русло, поки не зупиниш. Подвійний клік - перейменувати.")
            }
        }
        // 14, не 20: широкі білі поля з боків муляли (фідбек 2026-07-07)
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 24)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        // .textCase, а не .uppercased(): регістр — уже до перекладу (i18n)
        Text(text)
            .textCase(.uppercase)
            .font(.emUI(10, weight: .medium)).tracking(1.4)
            .foregroundStyle(EmbarColors.ink3)
            .padding(.top, 18).padding(.bottom, 8)
    }

    /// Картка як у прототипі: назва шрифту НИМ САМИМ + маленький
    /// трекнутий підпис; активна — темна рамка на легкому фоні
    private func fontCard(_ font: ReaderBodyFont, name: String, sub: String,
                          sampleFont: Font) -> some View {
        let active = fontRaw == font.rawValue
        return Button {
            fontRaw = font.rawValue // шрифт — миттєво (§7.2-A)
        } label: {
            // Компактно й тонко, як у прототипі (фідбек: «надто громіздке»)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(sampleFont).foregroundStyle(EmbarColors.ink)
                Text(sub.uppercased())
                    .font(.emUI(8.5, weight: .medium))
                    .tracking(1.0)
                    .foregroundStyle(EmbarColors.ink3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11)
                .fill(active ? Color.black.opacity(0.04) : .white))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .stroke(active ? EmbarColors.ink : EmbarColors.line,
                        lineWidth: active ? 1.4 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    /// Рядок-підказка про теми: маленька іконка + тихий текст
    private func hintRow(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(EmbarColors.ink3)
                .frame(width: 14)
            Text(text)
                .font(.emUI(11))
                .foregroundStyle(EmbarColors.ink3)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleRow(_ title: LocalizedStringKey, subtitle: LocalizedStringKey,
                           isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.emUI(13, weight: .medium)).foregroundStyle(EmbarColors.ink)
                Text(subtitle).font(.emUI(11)).foregroundStyle(EmbarColors.ink3)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(EmbarToggleStyle.sheet)
                .labelsHidden()
        }
        .padding(.vertical, 10)
    }
}
