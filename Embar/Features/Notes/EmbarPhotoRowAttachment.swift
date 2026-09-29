//
//  EmbarPhotoRowAttachment.swift
//  Embar
//
//  Ряд інлайн-фото як ОДИН NSTextAttachment на 1–3 слоти (SPEC §3.2). Один
//  символ-attachment = один ряд: видалення (Backspace) прибирає ряд цілком.
//  В архіві тіла — лише uuid-и й кількість колонок; самі зображення живуть у
//  NoteImage й підставляються resolver-ом (не архівуються з тілом).
//
//  ❗ Рендер — через NSTextAttachmentCell: AppKit-овий TextKit 1 малює
//  attachment-и ВИКЛЮЧНО через cell. Перевизначення attachmentBounds/
//  image(forBounds:) — API світу iOS/TextKit 2, NSLayoutManager їх не
//  викликає взагалі (доведено probe-ом 2026-07-05: 0 викликів, гліф 1×1 —
//  саме тому «фотографії не додавались»).
//

import AppKit

final class EmbarPhotoRowAttachment: NSTextAttachment {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    /// UUID-и зображень (по одному на слот)
    var imageIDs: [String] = []
    /// Кількість колонок 1–3
    var columns: Int = 1
    /// Резолв uuid → NSImage (транзієнтний, НЕ архівується)
    var resolver: ((UUID) -> NSImage?)?
    private var cache: [String: NSImage] = [:]

    private let gutter: CGFloat = 6
    /// Висота слота = ширина слота × aspect (використовує і кроп-редактор)
    static let slotAspect: CGFloat = 0.72
    private var slotAspect: CGFloat { Self.slotAspect }
    private let cornerRadius: CGFloat = 8

    init(imageIDs: [String], columns: Int) {
        self.imageIDs = imageIDs
        self.columns = max(1, min(columns, 3))
        super.init(data: nil, ofType: nil)
        attachmentCell = EmbarPhotoRowCell()
    }

    /// ❗ ОБОВ'ЯЗКОВИЙ override: NSTextAttachment.initWithCoder внутрішньо
    /// делегує в initWithData:ofType: на self. Наш власний designated init
    /// вимикає успадкування — без цього override'а ДЕКОДУВАННЯ нотатки з фото
    /// трапилось у runtime («вічне зависання» під дебагером, 2026-07-05)
    override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        attachmentCell = EmbarPhotoRowCell()
    }

    // MARK: - Secure coding (лише метадані; cell створюється заново)

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        imageIDs = coder.decodeObject(of: [NSArray.self, NSString.self],
                                      forKey: "embarImageIDs") as? [String] ?? []
        columns = max(1, coder.decodeInteger(forKey: "embarColumns"))
        attachmentCell = EmbarPhotoRowCell()
    }

    override func encode(with coder: NSCoder) {
        // ❗ Cell — транзієнтний UI-об'єкт: NSTextAttachmentCell не проходить
        // secure coding, і super.encode з cell-ом валив УВЕСЬ архів тіла
        // (encode → nil). Знімаємо на час кодування; після декодування cell
        // однаково створюється заново в init?(coder:)
        let cell = attachmentCell
        attachmentCell = nil
        super.encode(with: coder)
        attachmentCell = cell
        coder.encode(imageIDs as NSArray, forKey: "embarImageIDs")
        coder.encode(columns, forKey: "embarColumns")
    }

    override class var supportsSecureCoding: Bool { true }

    // MARK: - Розміри й малювання (використовує cell)

    /// Висота ряду для заданої ширини (слоти 1–3 з проміжками)
    func rowHeight(width: CGFloat) -> CGFloat {
        let cols = CGFloat(max(1, min(columns, 3)))
        let slotW = (width - gutter * (cols - 1)) / cols
        return (slotW * slotAspect).rounded()
    }

    /// Прямокутники слотів у межах ряду — спільна геометрія для малювання
    /// і hover-хіт-тесту (видалити/замінити/обітнути)
    func slotRects(in rect: NSRect) -> [NSRect] {
        let cols = max(1, min(columns, 3))
        let slotW = (rect.width - gutter * CGFloat(cols - 1)) / CGFloat(cols)
        return (0..<cols).map { i in
            NSRect(x: rect.minX + CGFloat(i) * (slotW + gutter),
                   y: rect.minY, width: slotW, height: rect.height)
        }
    }

    /// Намалювати композит слотів прямо в поточний graphics context
    /// (координати flipped text view — respectFlipped при draw)
    func drawRow(in rect: NSRect) {
        for (i, slot) in slotRects(in: rect).enumerated() {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: slot, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
            if i < imageIDs.count, let uuid = UUID(uuidString: imageIDs[i]),
               let image = resolved(uuid) {
                drawAspectFill(image, in: slot)
            } else {
                NSColor(embarHex: "#e3ded7").setFill()
                slot.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func resolved(_ uuid: UUID) -> NSImage? {
        if let cached = cache[uuid.uuidString] { return cached }
        guard let image = resolver?(uuid) else { return nil }
        cache[uuid.uuidString] = image
        return image
    }

    /// Center-crop заповнення слота (respectFlipped: text view — flipped,
    /// інакше фото малювалося б догори дриґом)
    private func drawAspectFill(_ image: NSImage, in rect: NSRect) {
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return }
        let scale = max(rect.width / iw, rect.height / ih)
        let dw = iw * scale, dh = ih * scale
        let dest = NSRect(x: rect.midX - dw / 2, y: rect.midY - dh / 2, width: dw, height: dh)
        image.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }
}

// MARK: - Cell (єдиний шлях верстки/малювання attachment-ів у AppKit TextKit 1)

final class EmbarPhotoRowCell: NSTextAttachmentCell {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    private var row: EmbarPhotoRowAttachment? { attachment as? EmbarPhotoRowAttachment }

    // Успадковані методи NSTextAttachmentCell — nonisolated; викликаються
    // layout-менеджером на main → assumeIsolated (як dayChanged в HomeModel)

    /// Розмір ряду під ширину рядка верстки (адаптується при ресайзі панелі)
    nonisolated override func cellFrame(for textContainer: NSTextContainer,
                                        proposedLineFragment lineFrag: NSRect,
                                        glyphPosition position: NSPoint,
                                        characterIndex charIndex: Int) -> NSRect {
        MainActor.assumeIsolated {
            let pad = textContainer.lineFragmentPadding
            let width = max(lineFrag.width - pad * 2, 40)
            let height = row?.rowHeight(width: width) ?? 60
            return NSRect(x: 0, y: -4, width: width, height: height + 8)
        }
    }

    nonisolated override func cellSize() -> NSSize {
        MainActor.assumeIsolated {
            let width: CGFloat = 320
            return NSSize(width: width, height: (row?.rowHeight(width: width) ?? 60) + 8)
        }
    }

    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        MainActor.assumeIsolated {
            // 4pt вертикальних відступів усередині фрейма (див. cellFrame)
            row?.drawRow(in: cellFrame.insetBy(dx: 0, dy: 4))
        }
    }
}
