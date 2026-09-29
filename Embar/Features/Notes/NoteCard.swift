//
//  NoteCard.swift
//  Embar
//
//  Картка нотатки у списку (SPEC §3.1): дата + провенанс, 📌, заголовок
//  Inter 14/500, прев'ю 2 рядки, кольорова смужка зліва = акцент.
//  Hover: смітник + пін. Закріплена — піднята картка surface r14.
//

import SwiftUI

struct NoteCard: View {
    @Environment(\.embarMaterial) private var material
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let note: Note
    let palette: Palette
    var onOpen: () -> Void
    var onTogglePin: () -> Void
    var onDelete: () -> Void
    /// Поки список їде на нові місця після видалення, ховер вимкнено
    /// (P2.12): сусідня картка підпливала під нерухомий курсор і її
    /// свіжовставлені кнопки їхали разом з нею — читалось, ніби кнопки
    /// видаленої картки «переїжджають» на наступну. Вікно тримає NotesView
    var hoverEnabled = true

    @State private var hovering = false

    /// Колір акценту (смужка/тінт) — зі слотів палітри
    private var accent: Color? {
        guard let i = note.accentColorIndex, i >= 0, i < palette.sticky.count else { return nil }
        return palette.sticky[i]
    }

    private var preview: String {
        let text = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        return text.count > 110 ? String(text.prefix(110)) + "…" : text
    }

    private var radius: CGFloat { note.pinned ? 14 : 10 }
    /// Ширина кольорового канта зліва (прототип: border-left 3px)
    private let accentEdge: CGFloat = 3.5

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                dateLine
                titleLine
                if !preview.isEmpty {
                    Text(preview)
                        .font(.emUI(12))
                        .foregroundStyle(EmbarColors.ink2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 3)
                }
            }
            .padding(.leading, accent == nil ? 10 : 10 + accentEdge)
            .padding(.vertical, 9)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(alignment: .bottomTrailing) { if hovering { hoverActions } }
            .contentShape(RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(.plain)
        // Ховер — памʼять рядка, яку LazyVStack воскрешає за id навіть
        // після видалення з даних (пастка F3, SPEC §15.65): «видалити під
        // курсором → undo» повертало картку з фантомними кнопками і
        // тінню. Свіжій появі — чистий стан
        .onAppear { hovering = false }
        .onHover { hovering = hoverEnabled ? $0 : false }
    }

    private var dateLine: some View {
        HStack(spacing: 4) {
            Text(dateText)
                .font(.emUI(10, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(EmbarColors.ink4)
        }
    }

    private var dateText: String {
        var s = NoteDateFormat.relative(note.updatedAt).uppercased()
        if let prov = NoteDateFormat.provenance(note.bornType) {
            s += " · \(prov.uppercased())"
        }
        return s
    }

    private var titleLine: some View {
        HStack(spacing: 5) {
            if note.pinned {
                // Червоний пін як у прототипі (.pin-icon: 📌 11px, op .75) —
                // сірий SF-символ читався як «ще одна іконка» (фідбек)
                Text("📌")
                    .font(.system(size: 11))
                    .opacity(0.75)
                    // Пін — мікро-масштабом ПІСЛЯ того, як картка
                    // проявилась на новому місці (P2.11: перескладка
                    // тепер миттєва + ArrivalReveal; таймінг = пін-кулька
                    // стіка)
                    .transition(reduceMotion ? .identity : .asymmetric(
                        insertion: .scale(scale: 0.2).combined(with: .opacity)
                            .animation(.easeOut(duration: 0.18).delay(0.4)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))))
            }
            Text(note.title.isEmpty ? "Без назви" : note.title)
                .font(.emUI(14, weight: .medium))
                .foregroundStyle(EmbarColors.ink)
                .opacity(note.title.isEmpty ? 0.35 : 1)
                .lineLimit(1)
        }
        .padding(.top, 6)
    }

    /// Фон картки. Кольоровий кант — НИЖНІЙ шар, що видніється зліва з-під
    /// поверхні картки: кант іде ПО ЗАОКРУГЛЕННЮ (прототип border-left на
    /// rounded-картці), а не окремою прямою смужкою збоку (фідбек 2026-07-06)
    private var cardBackground: some View {
        ZStack {
            if let accent {
                RoundedRectangle(cornerRadius: radius).fill(accent)
                    // Лише видима смужка зліва, а не вся підкладка (P2.13):
                    // каскадна поява застосовує прозорість пошарово, і
                    // акцент на мить просвічував крізь поверхню всім
                    // прямокутником — картка «блимала» кольором при
                    // перемиканні папок. Ширина маски з запасом покриває
                    // кант і заокруглений кут; правіше акцент однаково
                    // ніколи не видно
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: accentEdge + radius)
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: .leading)
                    }
            }
            // Скло: .thinMaterial під surface@islandAlpha — картка морозна
            if material.theme != .opaque {
                RoundedRectangle(cornerRadius: radius)
                    .fill(.thinMaterial)
                    .padding(.leading, accent == nil ? 0 : accentEdge)
            }
            RoundedRectangle(cornerRadius: radius)
                .fill(EmbarColors.surface.opacity(material.islandAlpha))
                .padding(.leading, accent == nil ? 0 : accentEdge)
            if hovering, !note.pinned {
                RoundedRectangle(cornerRadius: radius)
                    .fill(hoverTint)
                    .padding(.leading, accent == nil ? 0 : accentEdge)
            }
        }
        .shadow(color: .black.opacity(note.pinned ? 0.05 : 0),
                radius: note.pinned ? (hovering ? 7 : 5) : 0,
                y: note.pinned ? 2 : 0)
    }

    /// Hover-тінт: 10% акценту (як прототип) або нейтральний
    private var hoverTint: Color {
        accent?.opacity(0.14) ?? Color.black.opacity(0.025)
    }

    private var hoverActions: some View {
        HStack(spacing: 11) {
            Button(action: onTogglePin) {
                // 📌 як у прототипі: сірий (grayscale) поки не закріплено
                Text("📌")
                    .font(.system(size: 11))
                    .grayscale(note.pinned ? 0 : 1)
                    .opacity(note.pinned ? 1 : 0.55)
            }
            .buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(EmbarColors.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }
}
