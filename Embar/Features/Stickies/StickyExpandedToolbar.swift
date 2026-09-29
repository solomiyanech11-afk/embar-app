//
//  StickyExpandedToolbar.swift
//  Embar
//
//  Тулбар розгорнутого стіка — ОКРЕМИЙ острівець під карткою, того самого
//  кольору, що сам стік (редизайн 2026-08-19).
//
//  У згорнутому стані це ряд іконок: у нотатку, пін, емоджі, видалити, а
//  справа — хрестик. Дії з вмістом (дедлайн, емоджі, стіна) не відкривають
//  попапів: тулбар плавно розширюється вниз, іконки згасають, а на їхньому
//  місці зʼявляється вміст. Одна анімація на все — швидка, без пружності.
//

import SwiftUI

/// Що зараз показує тулбар
enum StickyToolbarMode: Equatable {
    case bar
    case deadline
    case emoji
    case wall

    /// Одна анімація на весь морф: швидка, без пружності (Motion §7.2-A).
    /// Її ж бере підйом картки, щоб рух читався як один жест
    static let morph = Animation.easeOut(duration: 0.2)
}

struct StickyExpandedToolbar<Content: View>: View {
    @Binding var mode: StickyToolbarMode
    /// Чорнила, добрані під колір стіка (адаптивні, SPEC §15.57) —
    /// тулбар лежить на тій самій заливці, що й картка
    let inks: StickyInk.Tokens
    let pinned: Bool
    let emojiTag: String?
    /// Виконаний стік не редагується (P2.4): пін та емоджі прибрано,
    /// лишаються «у нотатку», смітник і хрестик
    var locked = false

    var onMature: () -> Void
    var onTogglePin: () -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    /// Вміст розкритого тулбара — його дає сам редактор стіка
    @ViewBuilder var content: (StickyToolbarMode) -> Content

    private var ink: Color { inks.ink }
    private var ink2: Color { inks.ink2 }

    var body: some View {
        // Обидва стани малюються з ВЕРХНЬОГО краю, тож тулбар росте вниз.
        // Те, що йде геть, зникає МИТТЄВО (removal: .identity) — інакше
        // воно тримало б висоту й згортання спізнювалось; нове проступає
        // за той самий час, що міняється висота
        ZStack(alignment: .topLeading) {
            if mode == .bar {
                iconRow.transition(.asymmetric(insertion: .opacity, removal: .identity))
            } else {
                content(mode)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .fixedSize(horizontal: false, vertical: true)
        // Вміст не вилазить за краї, поки висота ще їде
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(StickyToolbarMode.morph, value: mode)
    }

    // MARK: - Ряд іконок

    private var iconRow: some View {
        // Порядок за частотою: пін, емоджі, у нотатку, видалити
        // (фідбек 2026-08-19)
        HStack(spacing: 6) {
            if !locked {
                iconButton(pinned ? "pin.fill" : "pin", action: onTogglePin)
                emojiButton
            }
            iconButton("doc", action: onMature)
            iconButton("trash", action: onDelete)
            Spacer(minLength: 8)
            closeButton
        }
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 14))
                .foregroundStyle(ink)
                .frame(width: 30, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverDarken(Circle())
    }

    /// Емоджі-тег: коли він є, кнопка показує сам емоджі замість смайлика
    private var emojiButton: some View {
        Button { mode = .emoji } label: {
            Group {
                if let emojiTag {
                    Text(emojiTag).font(.system(size: 15))
                } else {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 14))
                        .foregroundStyle(ink)
                }
            }
            .frame(width: 30, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverDarken(Circle())
    }

    /// Хрестик — така сама гола іконка, як решта (фідбек 2026-08-19:
    /// кружечок під ним муляв око); від дій його відділяє тільки відстань
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ink2)
                .frame(width: 30, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverDarken(Circle())
    }
}
