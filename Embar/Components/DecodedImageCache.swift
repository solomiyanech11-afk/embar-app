//
//  DecodedImageCache.swift
//  Embar
//
//  Кеш декодованих NSImage (фікс «заїдання» 2026-07-22): перемикання
//  папки/фільтра перебудовує полицю і стрічку, а NSImage(data:) на
//  кожен ре-рендер змушує macOS декодувати JPEG заново на головному
//  потоці — з фото-обкладинками і фото-записами це заморожувало UI на
//  секунди. Один раз декодували — далі та сама картинка з кеша.
//  Ключ — id власника + розмір даних: заміна фото міняє розмір, тож
//  свіжі дані декодуються заново, а стара картинка випадає сама
//  (NSCache чистить під тиском памʼяті).
//

import AppKit

enum DecodedImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    static func image(id: UUID, data: Data?) -> NSImage? {
        guard let data else { return nil }
        // + хеш хвоста (code review 2026-07-23): сам розмір міг би
        // зіткнутися при заміні фото на інше такого ж розміру; хвіст
        // JPEG — ентропійні дані, збіг практично неможливий. hashValue
        // стабільний лише в межах запуску — кешу цього досить
        let key = "\(id.uuidString)-\(data.count)-\(data.suffix(256).hashValue)"
            as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let decoded = NSImage(data: data) else { return nil }
        cache.setObject(decoded, forKey: key)
        return decoded
    }
}
