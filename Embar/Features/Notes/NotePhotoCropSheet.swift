//
//  NotePhotoCropSheet.swift
//  Embar
//
//  Кроп фото у слоті ряду (фідбек 2026-07-05): прев'ю з пропорцією слота,
//  drag — панорамування, слайдер — масштаб. «Зберегти» рендерить видиму
//  область у JPEG і перезаписує NoteImage. Аспект зафіксований аспектом
//  слота — «обітнути» = вибрати, ЩО саме видно у слоті.
//

import SwiftUI
import AppKit

struct NotePhotoCropSheet: View {
    let image: NSImage
    /// Пропорція бокса (height/width). Дефолт — слот нотаток; рідер
    /// передає пропорцію самого фото (2026-07-22, кроп фото записів)
    var aspect: CGFloat = EmbarPhotoRowAttachment.slotAspect
    /// P2.27: дозволити зум-аут до ЦІЛОГО фото. Пропорція бокса в рідері
    /// капається (0.45…1.4), і вузька смужка чи високий скріншот у
    /// капнутому боксі показували лише середину — і зберігали саме так.
    /// true (рідер): старт із цілого фото в боксі (пусті поля по краях),
    /// зум обирає область; збереження обрізає рамку по межах фото.
    /// false (нотатки): як було — бокс = слот, фото завжди покриває його
    var allowsWholePhoto = false
    var onCancel: () -> Void
    var onSave: (NSImage) -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero      // зсув у координатах бокса
    @State private var dragStart: CGSize = .zero
    @State private var previewBox = CGSize(width: 300, height: 300 * EmbarPhotoRowAttachment.slotAspect)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Обітнути фото")
                .font(.emUI(16, weight: .semibold))
                .foregroundStyle(EmbarColors.ink)

            GeometryReader { geo in
                let boxW = geo.size.width
                let boxH = boxW * aspect
                cropBox(boxW: boxW, boxH: boxH)
            }
            .aspectRatio(1 / aspect, contentMode: .fit)

            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 11)).foregroundStyle(EmbarColors.ink3)
                Slider(value: $zoom, in: minZoom...3)
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 11)).foregroundStyle(EmbarColors.ink3)
            }

            HStack {
                Button("Скасувати", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.emUI(13)).foregroundStyle(EmbarColors.ink3)
                Spacer()
                Button(action: save) {
                    Text("Зберегти")
                        .font(.emUI(12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(EmbarColors.ink))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    private func cropBox(boxW: CGFloat, boxH: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: boxW, height: boxH)
            .scaleEffect(zoom)
            .offset(clampedOffset(boxW: boxW, boxH: boxH))
            .frame(width: boxW, height: boxH)
            // Легка підкладка: при зум-ауті (P2.27) фото менше за бокс,
            // і поля мають читатись як «полотно», а не діра. Під повністю
            // покритим боксом (нотатки) її не видно взагалі
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.05)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            // Зсув зберігається в пікселях прев'ю — save рахує в тому ж боксі
            .onAppear {
                previewBox = CGSize(width: boxW, height: boxH)
                // Старт із цілого фото (P2.27): «показує лише середину»
                // лікується стартовою позицією, а не памʼяттю користувача
                if allowsWholePhoto { zoom = minZoom }
            }
            .onChange(of: boxW) { _, w in previewBox = CGSize(width: w, height: w * aspect) }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(width: dragStart.width + value.translation.width,
                                        height: dragStart.height + value.translation.height)
                    }
                    .onEnded { _ in
                        offset = clampedOffset(boxW: boxW, boxH: boxH)
                        dragStart = offset
                    }
            )
    }

    /// Нижня межа зуму: 1 — фото покриває бокс (як було); з
    /// allowsWholePhoto — аж до «ціле фото в боксі» (contain/cover).
    /// Від розмірів бокса не залежить — лише від пропорцій фото і бокса
    private var minZoom: CGFloat {
        guard allowsWholePhoto else { return 1 }
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return 1 }
        let ratio = ih / (aspect * iw)
        return min(ratio, 1 / ratio)
    }

    /// Не дати «виїхати» за край: зсув обмежений залишком масштабованого фото
    private func clampedOffset(boxW: CGFloat, boxH: CGFloat) -> CGSize {
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return .zero }
        let cover = max(boxW / iw, boxH / ih)
        let s = cover * zoom
        let maxX = max((iw * s - boxW) / 2, 0)
        let maxY = max((ih * s - boxH) / 2, 0)
        return CGSize(width: min(max(offset.width, -maxX), maxX),
                      height: min(max(offset.height, -maxY), maxY))
    }

    /// Область фото, яку вирізає поточний стан превʼю. Чиста функція —
    /// під тести (P2.27: на мінімальному зумі мусить віддати ЦІЛЕ фото).
    /// Рамка бокса, ширша за фото (зум-аут), обрізається по межах фото
    static func cropRect(imageSize: CGSize, box: CGSize,
                         zoom: CGFloat, offset: CGSize) -> CGRect {
        let iw = imageSize.width, ih = imageSize.height
        guard iw > 0, ih > 0, box.width > 0, box.height > 0 else { return .zero }
        let cover = max(box.width / iw, box.height / ih)
        let s = cover * zoom
        let cw = min(box.width / s, iw)
        let ch = min(box.height / s, ih)
        var ox = iw / 2 - offset.width / s - cw / 2
        var oy = ih / 2 - offset.height / s - ch / 2
        ox = min(max(ox, 0), iw - cw)
        oy = min(max(oy, 0), ih - ch)
        return CGRect(x: ox, y: oy, width: cw, height: ch)
    }

    /// Рендер видимої області (дзеркало прев'ю) у нове зображення
    private func save() {
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return onCancel() }
        let rect = Self.cropRect(imageSize: image.size, box: previewBox,
                                 zoom: zoom,
                                 offset: clampedOffset(boxW: previewBox.width,
                                                       boxH: previewBox.height))
        guard rect.width > 0, rect.height > 0 else { return onCancel() }

        let out = NSImage(size: NSSize(width: rect.width, height: rect.height))
        out.lockFocus()
        // from-rect у координатах зображення (початок знизу зліва)
        image.draw(in: NSRect(x: 0, y: 0, width: rect.width, height: rect.height),
                   from: NSRect(x: rect.origin.x,
                                y: ih - rect.origin.y - rect.height,
                                width: rect.width, height: rect.height),
                   operation: .copy, fraction: 1)
        out.unlockFocus()
        onSave(out)
    }
}
