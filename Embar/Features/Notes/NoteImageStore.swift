//
//  NoteImageStore.swift
//  Embar
//
//  Імпорт/зберігання/резолв інлайн-зображень нотатки (SPEC §11.3-b). Фото
//  беруться через NSOpenPanel (sandbox: user-selected read-only), даунскейлять-
//  ся й КОПІЯ живе в контейнері як NoteImage.data (externalStorage) — оригінал
//  більше не потрібен, security-scoped bookmark не тримаємо.
//

import AppKit
import SwiftData
import UniformTypeIdentifiers

extension Notification.Name {
    /// Файл-пікер відкрито/закрито: PanelController тримає панель
    /// відкритою і не auto-hide-ить її, поки триває вибір (2026-07-29)
    static let embarFilePickerWillShow = Notification.Name("embarFilePickerWillShow")
    static let embarFilePickerDidClose = Notification.Name("embarFilePickerDidClose")
}

enum NoteImageStore {
    private static let maxDimension: CGFloat = 1600

    // MARK: - Вибір файлів (лінивий дозвіл на файли — SPEC §12)

    /// Панель вибору до `count` зображень. Дозвіл user-selected read-only
    /// запитується системою при першому відкритті панелі.
    /// ❗ Наш застосунок — нонактивуюча панель на рівні .statusBar: без явної
    /// активації діалог відкривався БЕЗ фокуса і НИЖЧЕ панелі (невидимий) —
    /// звідси «фотографії не додаються» (фідбек 2026-07-05)
    /// Системний вибір файлів — НЕБЛОКУЮЧИЙ (стоп-баг 2026-07-29).
    /// ❗ Було runModal: панель Embar — nonactivating, тож над чужою
    /// програмою застосунок НЕактивний; модальний цикл блокував увесь
    /// event loop панелі й чекав вводу у діалог, який без активації не
    /// ставав key і відкривався ПОЗАДУ чужих вікон (а runModal ще й
    /// скидає рівень) — панель «замерзала намертво». begin() нічого не
    /// блокує, а рівень + orderFrontRegardless (ПІСЛЯ begin, щоб показ
    /// не перескинув) виводять діалог над усім незалежно від активації.
    /// PanelController слухає нотифікації й тримає панель відкритою.
    static func pickImages(count: Int, completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = count > 1
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.jpeg, .png, .heic, .image]
        panel.prompt = String(localized: "Додати", comment: "Кнопка підтвердження у системному вікні вибору фото")
        NotificationCenter.default.post(name: .embarFilePickerWillShow, object: nil)
        let wasInactive = !NSApp.isActive
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            NotificationCenter.default.post(name: .embarFilePickerDidClose,
                                            object: nil)
            completion(response == .OK ? Array(panel.urls.prefix(count)) : [])
        }
        // Діалог приходить на ПОТОЧНИЙ Space (включно з fullscreen-
        // програмами) — інакше відкривався на робочому столі поза очима
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        bringToFront(panel)
        // Вікно діалога — remote-сервіс (sandbox), створюється асинхронно:
        // перший orderFront може впасти на ще порожнє вікно, а показ
        // перескидає рівень — повторюємо, поки діалог відкритий
        for delay in [0.05, 0.3, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if panel.isVisible { bringToFront(panel) }
            }
        }
        // Панель — nonactivating, активація може бути відхилена; якщо
        // діалог усе ж лишився поза очима — мʼяка підказка (фідбек
        // 2026-07-29: «нічого не відбувається»)
        if wasInactive {
            NotificationCenter.default.post(
                name: .embarMiniToast, object: nil,
                userInfo: ["text": LocalizedStringResource(
                                "Не бачиш вікна вибору фото? Воно чекає на робочому екрані"),
                           "seconds": 4.0])
        }
    }

    private static func bringToFront(_ panel: NSOpenPanel) {
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    // MARK: - Імпорт (даунскейл + копія в контейнер)

    /// Створити NoteImage-и з файлів; повертає їхні UUID (для attachment)
    static func importImages(from urls: [URL], note: Note, in context: ModelContext) -> [UUID] {
        urls.compactMap { url in
            guard let image = NSImage(contentsOf: url),
                  let data = downscaledJPEG(image) else { return nil }
            let record = NoteImage()
            record.data = data
            record.note = note // встановлює обидва боки (Note.images)
            context.insert(record)
            return record.id
        }
    }

    /// Резолв UUID → NSImage для рендеру attachment (декодує JPEG з контейнера)
    static func resolve(_ id: UUID, in context: ModelContext) -> NSImage? {
        var d = FetchDescriptor<NoteImage>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let data = (try? context.fetch(d))?.first?.data else { return nil }
        return NSImage(data: data)
    }

    /// Перезаписати байти зображення (кроп) у той самий NoteImage
    static func updateData(_ id: UUID, data: Data, in context: ModelContext) {
        var d = FetchDescriptor<NoteImage>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        (try? context.fetch(d))?.first?.data = data
    }

    // MARK: - Даунскейл

    /// Зменшити до maxDimension по довшій стороні і закодувати JPEG 0.8
    static func downscaledJPEG(_ image: NSImage, quality: CGFloat = 0.8) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let src = NSBitmapImageRep(data: tiff) else { return nil }
        let pw = CGFloat(src.pixelsWide), ph = CGFloat(src.pixelsHigh)
        guard pw > 0, ph > 0 else { return nil }
        let scale = min(1, maxDimension / max(pw, ph))
        let tw = Int((pw * scale).rounded()), th = Int((ph * scale).rounded())

        guard let dst = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        dst.size = NSSize(width: tw, height: th)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: dst)
        NSGraphicsContext.current?.imageInterpolation = .high
        src.draw(in: NSRect(x: 0, y: 0, width: tw, height: th))
        NSGraphicsContext.restoreGraphicsState()

        return dst.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
