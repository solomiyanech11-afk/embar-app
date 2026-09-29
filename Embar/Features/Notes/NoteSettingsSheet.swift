//
//  NoteSettingsSheet.swift
//  Embar
//
//  Шит налаштувань нотатки (SPEC §3.3, прототип .note-settings-overlay):
//  розмір тексту · шрифт · інтервал · тумблери редагування.
//  Розмір/шрифт/інтервал — ПЕР-НОТАТКОВІ (зберігаються в Note);
//  тумблери — глобальні (AppStorage). Editorial/Cursive відкладено —
//  сім'ї не бандлимо (§15.2); Serif = Fraunces, Mono = системний.
//

import SwiftUI

struct NoteSettingsSheet: View {
    @ObservedObject var editor: NoteEditorModel

    @AppStorage("noteFocusMode") private var focusMode = false
    @AppStorage("noteMetaLine") private var metaLine = true
    @AppStorage("noteSpellcheck") private var spellcheck = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Налаштування")
                .font(.emUI(18, weight: .semibold))
                .foregroundStyle(EmbarColors.ink)
            Text("Текст, вигляд і режим редагування")
                .font(.emUI(12))
                .foregroundStyle(EmbarColors.ink3)
                .padding(.top, 2)

            sectionLabel("Розмір тексту")
            HStack(spacing: 8) {
                sizeCard(.large, "Великий", sample: 20)
                sizeCard(.medium, "Середній", sample: 17)
                sizeCard(.normal, "Звичайний", sample: 15)
                sizeCard(.small, "Маленький", sample: 13)
            }

            sectionLabel("Шрифт")
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    fontCard(.inter, "Inter · default", sampleFont: .emUI(15, weight: .medium))
                    fontCard(.serif, "Serif · warm", sampleFont: .emDisplay(15, weight: .medium))
                }
                HStack(spacing: 8) {
                    fontCard(.mono, "Mono · code",
                             sampleFont: Font.system(size: 14, weight: .medium, design: .monospaced))
                    Spacer().frame(maxWidth: .infinity)
                }
            }

            sectionLabel("Інтервал між рядками")
            spacingSegments

            sectionLabel("Редагування")
            VStack(spacing: 0) {
                toggleRow("Фокус-режим", subtitle: "Сховати тулбар, лише текст", isOn: $focusMode)
                Divider().overlay(EmbarColors.line)
                toggleRow("Мета-рядок", subtitle: "Показувати «Оновлено · дата · папка»", isOn: $metaLine)
                Divider().overlay(EmbarColors.line)
                toggleRow("Перевірка орфографії", subtitle: "Підкреслювати помилки під час набору", isOn: $spellcheck)
            }
        }
        // 14, не 20 — синхронно з ReaderSettingsSheet (фідбек 2026-07-07:
        // широкі білі поля з боків; консистентність шитів)
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

    // MARK: - Розмір тексту (картки Аа)

    private func sizeCard(_ size: BodySizeClass, _ label: LocalizedStringKey, sample: CGFloat) -> some View {
        let active = editor.settings.sizeClass == size
        return Button { editor.applySettings(size: size) } label: {
            VStack(spacing: 4) {
                Text("Аа")
                    .font(.emUI(sample, weight: .semibold))
                    .foregroundStyle(EmbarColors.ink)
                Text(label)
                    .font(.emUI(10.5))
                    .foregroundStyle(EmbarColors.ink3)
                    // Довга назва («Звичайний» у вузькій картці) ховається
                    // за трикрапкою, а не стрибає на другий рядок (P2.31)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(active ? EmbarColors.ink : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Шрифт

    private func fontCard(_ font: NoteBodyFont, _ label: LocalizedStringKey, sampleFont: Font) -> some View {
        let active = editor.settings.font == font
        return Button { editor.applySettings(font: font) } label: {
            HStack(spacing: 8) {
                Text("Аа").font(sampleFont).foregroundStyle(EmbarColors.ink)
                Text(label).font(.emUI(12)).foregroundStyle(EmbarColors.ink3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(active ? EmbarColors.ink : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Інтервал (сегменти-пігулка)

    private var spacingSegments: some View {
        HStack(spacing: 0) {
            spacingSegment(.tight, "Щільний")
            spacingSegment(.normal, "Звичайний")
            spacingSegment(.loose, "Просторий")
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.05)))
    }

    private func spacingSegment(_ spacing: NoteLineHeight, _ label: LocalizedStringKey) -> some View {
        let active = editor.settings.lineHeight == spacing
        return Button { editor.applySettings(spacing: spacing) } label: {
            Text(label)
                .font(.emUI(12.5, weight: active ? .medium : .regular))
                .foregroundStyle(active ? EmbarColors.ink : EmbarColors.ink3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if active {
                        Capsule().fill(.white)
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Тумблери

    private func toggleRow(_ title: LocalizedStringKey, subtitle: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
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
