//
//  ReaderBookCard.swift
//  Embar
//
//  Картка блокнота на полиці (SPEC §4.1; прототип .reader-book).
//  Два варіанти: фото-обкладинка з градієнтом під назвою і plain-біла.
//  Hover-lift — жива анімація прототипу (дозволена §7.2-A).
//

import SwiftUI

struct ReaderBookCard: View {
    enum CardShape { case tall, square }

    let book: ReaderBook
    let shape: CardShape
    let onOpen: () -> Void

    @State private var hovering = false
    /// Декодована обкладинка — через DecodedImageCache (2026-07-22):
    /// .id(selectedFolder) на полиці перебудовує ВСІ картки при кожному
    /// перемиканні папки, і повторний декод JPEG заморожував UI
    @State private var cover: NSImage?

    private var height: CGFloat { shape == .tall ? 270 : 131 }
    private var sourceLabel: String { book.activeSource?.label ?? "" }
    private var title: String { book.title.isEmpty ? "Без назви" : book.title }

    var body: some View {
        Group {
            if let image = cover {
                photoCard(image)
            } else {
                plainCard
            }
        }
        .onAppear { cover = DecodedImageCache.image(id: book.id, data: book.photoData) }
        .onChange(of: book.photoData) { _, data in
            cover = DecodedImageCache.image(id: book.id, data: data)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // ❗ contentShape ПІСЛЯ clipShape: без нього хітбокс fill-фото
        // вилазить за межі картки на сусідів
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(hovering ? 0.12 : 0.08),
                radius: hovering ? 11 : 3, y: hovering ? 6 : 1)
        .scaleEffect(hovering ? 1.025 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
    }

    // MARK: - Plain (без фото): білий фон, назва внизу

    private var plainCard: some View {
        ZStack(alignment: .bottomLeading) {
            EmbarColors.card
            Text(title)
                .font(.emUI(19))
                .tracking(-0.1)
                .foregroundStyle(EmbarColors.ink)
                .lineLimit(3)
                .padding(12)
        }
        .overlay(alignment: .topLeading) { label(onPhoto: false) }
        .overlay(alignment: .topTrailing) { arrowBadge(onPhoto: false) }
    }

    // MARK: - Фото-обкладинка: назва на градієнті

    private func photoCard(_ image: NSImage) -> some View {
        // ❗ Фото — БЕКГРАУНД порожнього вʼю, не учасник лейауту: інакше
        // жадібний ideal-розмір scaledToFill розширює картку понад 50%
        // і стискає сусідів у групі (фідбек після кроку 3)
        Color.clear
            .background(
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            )
            .overlay(alignment: .bottom) {
                Text(title)
                    .font(.emUI(19))
                    .tracking(-0.1)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 32, leading: 12, bottom: 13, trailing: 12))
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.52)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }
            .overlay(alignment: .topLeading) { label(onPhoto: true) }
            .overlay(alignment: .topTrailing) { arrowBadge(onPhoto: true) }
    }

    // MARK: - Лейбл джерела і стрілка

    @ViewBuilder private func label(onPhoto: Bool) -> some View {
        if !sourceLabel.isEmpty {
            Text(sourceLabel)
                .font(.emUI(10, weight: .medium))
                .foregroundStyle(onPhoto ? .white.opacity(0.72) : .black.opacity(0.35))
                .lineLimit(2)
                .padding(.top, 10)
                .padding(.leading, 12)
                .padding(.trailing, 40)
        }
    }

    private func arrowBadge(onPhoto: Bool) -> some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(onPhoto ? .white.opacity(hovering ? 0.95 : 0.7)
                                     : .black.opacity(hovering ? 0.4 : 0.22))
            .padding(.top, 10)
            .padding(.trailing, 11)
            .allowsHitTesting(false)
    }
}

// MARK: - Рядок «+ Новий блокнот» (P2.34, SPEC §15.73)
// Відхід від прототипу (.reader-new-book - пунктирна плитка в кінці
// сітки): тихий рядок-кнопка вгорі під табами, у тій самій оболонці,
// що композери стіків і нотаток (ComposerRowChrome - висота і
// геометрія спільним кодом). Клік одразу створює блокнот із
// назвою-заповнювачем і відкриває його з курсором у compose (P2.24).
// БЕЗ інлайн-поля назви: воно повернуло б програмний фокус у назву,
// який вирізано в P2.24

struct ReaderNewBookRow: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text("+ Новий блокнот")
                    .font(.emUI(14))
                    // Тихий, як плейсхолдер композера; ховер трохи темнішає
                    // (та сама пара тонів, що була на плитці)
                    .foregroundStyle(hovering ? EmbarColors.ink3
                                              : EmbarColors.placeholder)
                Spacer(minLength: 0)
            }
            .padding(.leading, 18)
            .padding(.trailing, 18)
            .padding(.vertical, 11)
            .frame(minHeight: 46)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // Мʼякша тінь, ніж у композерів: це кнопка, а не поле вводу -
        // повна тінь читалась як «надто піднята» (фідбек 2026-09-04)
        .modifier(ComposerRowChrome(shadowOpacity: 0.11,
                                    shadowRadius: 7,
                                    shadowOffsetY: 3))
    }
}
