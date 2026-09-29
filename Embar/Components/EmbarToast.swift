//
//  EmbarToast.swift
//  Embar
//
//  Візуальні тости + модифікатор .toastLayer(), що накладає їх поверх панелі.
//  Значення з прототипу (SPEC §7.2).
//

import SwiftUI

// MARK: - Mini toast (чорна пігулка)

private struct MiniToastView: View {
    let text: LocalizedStringResource
    var style: ToastCenter.Style = .neutral

    /// danger — токен EmbarColors.danger (функціональний червоний)
    private var fill: Color {
        switch style {
        case .neutral: Color(hex: "#1a1a1a").opacity(0.92)
        case .danger: EmbarColors.danger.opacity(0.95)
        }
    }

    var body: some View {
        Text(text)
            .font(.emUI(13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(fill))
            .shadow(color: .black.opacity(0.2), radius: 15, y: 8)
    }
}

// MARK: - Drain ring (кільце-таймер, що спорожняється)

private struct DrainRing: View {
    let shownAt: Date
    let duration: Double

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(shownAt)
            let remaining = max(0, duration - elapsed)
            let progress = duration > 0 ? remaining / duration : 0
            ZStack {
                Circle().stroke(Color.black.opacity(0.08), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(EmbarColors.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90)) // старт зверху
                Text("\(Int(ceil(remaining)))")
                    .font(.emUI(9, weight: .medium).monospacedDigit())
                    .foregroundStyle(EmbarColors.ink2)
            }
            .frame(width: 18, height: 18)
        }
    }
}

// MARK: - Undo toast (світла пігулка з дією + таймером)

private struct UndoToastView: View {
    let toast: ToastCenter.Undo
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            DrainRing(shownAt: toast.shownAt, duration: toast.duration)
            Text(toast.message)
                .font(.emUI(11.5))
                .foregroundStyle(EmbarColors.ink2)
            Button(action: onAction) {
                Text(toast.actionLabel)
                    .font(.emUI(10.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(EmbarColors.ink))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 13)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(EmbarColors.surface)
                .overlay(Capsule().stroke(Color.black.opacity(0.05)))
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}

// MARK: - Шар тостів

private struct ToastLayer: ViewModifier {
    @ObservedObject var toasts: ToastCenter
    /// Відступ mini-тосту від низу: у панелі 40, у вікні пейвола -
    /// над футером із лінками (2026-09-17)
    var miniBottomPadding: CGFloat = 40

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                if let undo = toasts.undo {
                    // 100: футер (~56) + чіпи walls bar (~32) + зазор 12 —
                    // тост НЕ налазить на чіпи папок (фідбек 2026-07-19)
                    UndoToastView(toast: undo) { toasts.performUndo() }
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let mini = toasts.mini {
                    MiniToastView(text: mini.text, style: mini.style)
                        .padding(.bottom, miniBottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: toasts.mini)
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: toasts.undo?.id)
        }
    }
}

extension View {
    /// Накладає шар тостів поверх вмісту. Застосувати на кореневий вигляд
    /// панелі (або окремого вікна - тоді з власним відступом mini-тосту)
    func toastLayer(_ toasts: ToastCenter,
                    miniBottomPadding: CGFloat = 40) -> some View {
        modifier(ToastLayer(toasts: toasts, miniBottomPadding: miniBottomPadding))
    }
}
