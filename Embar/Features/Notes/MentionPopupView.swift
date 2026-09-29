//
//  MentionPopupView.swift
//  Embar
//
//  Попап `[[`-згадок (SPEC §3.4, прототип .mention-pop) — in-panel острівець
//  біля курсора (НЕ дочірнє вікно: те билося б із hover/автоховуванням
//  панелі). Клавіатура ↑/↓/Enter/Esc — з text view, фокус не мігрує.
//  Тут же — поповер «Тут згадується» (backlinks).
//

import SwiftUI

struct MentionPopupView: View {
    @Environment(\.embarMaterial) private var material
    let query: String
    let candidates: [Note]
    let selection: Int
    var onPick: (Int) -> Void
    /// Хрестик (P2.23): закрити попап для ЦЬОГО «[[» назавжди (як Escape)
    var onClose: () -> Void = {}

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text("ЗГАДАТИ НОТАТКУ")
                    .font(.emUI(9.5, weight: .medium)).tracking(1.2)
                    .foregroundStyle(EmbarColors.ink3)
                Spacer(minLength: 0)
                // Хрестик = Escape: цей «[[» більше не пропонується (P2.23)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(EmbarColors.ink3)
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .hoverDarken(Circle())
                .help("Закрити - для цього [[ більше не пропонувати")
            }
            .padding(.leading, 6).padding(.top, 2)

            if candidates.isEmpty && trimmedQuery.isEmpty {
                Text("почни писати назву…")
                    .font(.emDisplay(12, italic: true))
                    .foregroundStyle(EmbarColors.ink3)
                    .padding(.horizontal, 6).padding(.vertical, 4)
            }

            ForEach(Array(candidates.enumerated()), id: \.element.id) { pair in
                row(index: pair.offset) {
                    Text(pair.element.title.isEmpty ? "Без назви" : pair.element.title)
                        .font(.emUI(12.5))
                        .foregroundStyle(EmbarColors.ink)
                        .lineLimit(1)
                }
            }

            if !trimmedQuery.isEmpty {
                row(index: candidates.count) {
                    Text("＋ Створити «\(trimmedQuery.truncatedChip())»")
                        .font(.emDisplay(12, italic: true))
                        .foregroundStyle(EmbarColors.ink2)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .frame(width: 224, alignment: .leading)
        .background(
            ZStack {
                // Скло: .thinMaterial сам дає frost — над ним лише тінт
                if material.theme != .opaque {
                    RoundedRectangle(cornerRadius: 12).fill(.thinMaterial)
                }
                RoundedRectangle(cornerRadius: 12)
                    .fill(EmbarColors.surface.opacity(material.islandAlpha))
            }
            .shadow(color: .black.opacity(0.18), radius: 15, y: 5)
        )
        .onContinuousHover { phase in
            if case .active = phase { NSCursor.arrow.set() }
        }
    }

    private func row(index: Int, @ViewBuilder content: () -> some View) -> some View {
        Button { onPick(index) } label: {
            HStack { content(); Spacer(minLength: 0) }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(index == selection ? Color.black.opacity(0.06) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - «Тут згадується» (backlinks, SPEC §3.4)

struct BacklinksPopover: View {
    let note: Note
    var onOpen: (Note) -> Void

    private var backlinks: [Note] {
        (note.mentionedBy ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ТУТ ЗГАДУЄТЬСЯ")
                .font(.emUI(10, weight: .medium)).tracking(1.4)
                .foregroundStyle(EmbarColors.ink3)

            if backlinks.isEmpty {
                Text("Ця нотатка ніде не згадується. (Напиши [[ в нотатці, щоб зробити звʼязок.)")
                    .font(.emUI(11.5))
                    .foregroundStyle(EmbarColors.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(backlinks) { source in
                    Button { onOpen(source) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title.isEmpty ? "Без назви" : source.title)
                                .font(.emUI(13, weight: .medium))
                                .foregroundStyle(EmbarColors.ink)
                                .lineLimit(1)
                            Text(snippet(from: source))
                                .font(.emUI(11.5))
                                .foregroundStyle(EmbarColors.ink3)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.025)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 236)
    }

    /// Сніпет — вікно навколо першого входження титулу цієї нотатки у
    /// плейн-дзеркалі згадувача (без декодування архівів)
    private func snippet(from source: Note) -> String {
        let mirror = source.content
        let target = note.title
        guard !target.isEmpty, let r = mirror.range(of: target) else {
            return String(mirror.prefix(80))
        }
        let start = mirror.index(r.lowerBound, offsetBy: -30, limitedBy: mirror.startIndex)
            ?? mirror.startIndex
        let end = mirror.index(r.upperBound, offsetBy: 50, limitedBy: mirror.endIndex)
            ?? mirror.endIndex
        return (start > mirror.startIndex ? "…" : "") + mirror[start..<end]
    }
}
