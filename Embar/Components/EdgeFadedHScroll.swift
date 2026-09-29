//
//  EdgeFadedHScroll.swift
//  Embar
//
//  Горизонтальний ряд чіпів без різкого вертикального зрізу (фідбек
//  2026-09-05; те саме правило, що fade під шапками). Розчиняється ЛИШЕ
//  край, за яким справді є ще контент; догорнутий край чистий - чіп у
//  спокої не стоїть напівпрозорим.
//
//  ❗ Чому AppKit-спостерігач, а не GeometryReader+PreferenceKey: на
//  macOS ScrollView їде шаром NSScrollView, і onPreferenceChange НЕ
//  доставляє оновлення рамки при гортанні (перевірено зондом: preference
//  прилітає один раз нульовим і мовчить; сам GeometryReader при цьому
//  переобчислюється - губиться саме доставка). Плюс у named-просторі
//  SwiftUI рамка вмісту в спокої має фантомний зсув ~2pt. Тож слухаємо
//  першоджерело: boundsDidChange кліпа NSScrollView.
//

import SwiftUI
import AppKit

struct EdgeFadedHScroll<Content: View>: View {
    /// Ширина зони розчинення з кожного краю
    var fadeWidth: CGFloat = 18
    @ViewBuilder let content: () -> Content

    /// Ліворуч/праворуч є ще контент за краєм → той бік розчиняється
    @State private var fadeLeading = false
    @State private var fadeTrailing = false

    var body: some View {
        ScrollView(.horizontal) {
            content()
                .background {
                    ScrollEdgeWatcher { leading, trailing in
                        if fadeLeading != leading { fadeLeading = leading }
                        if fadeTrailing != trailing { fadeTrailing = trailing }
                    }
                }
        }
        .scrollIndicators(.hidden) // правило проєкту
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: fadeLeading ? fadeWidth : 0)
                Rectangle()
                LinearGradient(colors: [.black, .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: fadeTrailing ? fadeWidth : 0)
            }
        }
    }
}

/// Невидимий NSView у вмісті скролу: знаходить свій NSScrollView і
/// доповідає, чи є невидимий контент за лівим/правим краєм - на кожен
/// рух кліпа і на кожну зміну розміру вмісту
private struct ScrollEdgeWatcher: NSViewRepresentable {
    var onChange: (_ leading: Bool, _ trailing: Bool) -> Void

    func makeNSView(context: Context) -> WatcherView {
        WatcherView(onChange: onChange)
    }

    func updateNSView(_ nsView: WatcherView, context: Context) {
        nsView.onChange = onChange
    }

    final class WatcherView: NSView {
        nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
        var onChange: (Bool, Bool) -> Void
        private var tokens: [NSObjectProtocol] = []

        init(onChange: @escaping (Bool, Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens = []
            guard window != nil, let scroll = enclosingScrollView else { return }
            let clip = scroll.contentView
            clip.postsBoundsChangedNotifications = true
            let center = NotificationCenter.default
            tokens.append(center.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clip, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.report() }
            })
            // Вміст росте/меншає (додали чіп, зʼявилась пігулка) - краї
            // могли зʼявитись без жодного гортання
            if let doc = scroll.documentView {
                doc.postsFrameChangedNotifications = true
                tokens.append(center.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: doc, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.report() }
                })
            }
            // Стартовий стан - наступним тіком, після розкладки
            Task { @MainActor [weak self] in self?.report() }
        }

        private func report() {
            guard let scroll = enclosingScrollView,
                  let doc = scroll.documentView else { return }
            let visible = scroll.contentView.bounds
            // Допуск 1pt: субпіксельні координати не мають блимати fade-ом
            let leading = visible.minX > 1
            let trailing = doc.frame.width - visible.maxX > 1
            onChange(leading, trailing)
        }
    }
}
