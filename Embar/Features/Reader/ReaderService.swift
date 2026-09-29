//
//  ReaderService.swift
//  Embar
//
//  Операції над блокнотами й записами рідера (SPEC §4, §11.5–11.8).
//  Чисті дата-операції над ModelContext; тости показує View. Видалення =
//  soft-delete (deletedAt), фізична чистка > 30 днів в AppMaintenance.
//  Кожна мутація вмісту бампає book.updatedAt — полиця сортується за ним.
//

import Foundation
import AppKit
import SwiftData

enum ReaderService {

    // MARK: - Блокноти

    /// Створити блокнот у поточній папці (плитка «+ Новий блокнот»).
    /// coverColorIndex — за кількістю наявних, як у прототипі (createReaderBook).
    /// ❗ Фокус і заповнювач нового блокнота (фідбек 2026-09-04,
    /// SPEC §15.72в): назва створюється ПОРОЖНЬОЮ, «Новий блокнот» - це
    /// плейсхолдер поля; каретка одразу мигає в назві, людина продовжує
    /// писати. Заповнювач стає СПРАВЖНЬОЮ назвою лише коли людина пішла
    /// з поля, нічого не набравши (див. ReaderNotebookView,
    /// materializePlaceholderIfUnnamed)
    @discardableResult
    static func createBook(folderName: String? = nil, existingCount: Int = 0,
                           in context: ModelContext) -> ReaderBook {
        let book = ReaderBook()
        book.coverColorIndex = existingCount
        book.folderName = folderName
        context.insert(book)
        return book
    }

    static func setTitle(_ title: String, for book: ReaderBook) {
        book.title = title
        book.updatedAt = .now
    }

    static func setFolder(_ name: String?, for book: ReaderBook) {
        book.folderName = name
        book.updatedAt = .now
    }

    /// Фото-обкладинка (вже стиснена до JPEG; nil — прибрати)
    static func setCover(_ data: Data?, for book: ReaderBook) {
        book.photoData = data
        book.updatedAt = .now
    }

    static func softDeleteBook(_ book: ReaderBook) {
        book.deletedAt = .now
        book.updatedAt = .now
    }

    static func undoDeleteBook(_ book: ReaderBook) {
        book.deletedAt = nil
        book.updatedAt = .now
    }

    // MARK: - Папки (рядкові — SPEC §11.7: окремої сутності немає,
    // на книзі лише folderName; список назв живе в UserDefaults, як
    // readerFolders у прототипі)

    private static let foldersKey = "readerFolders"

    /// Збережений список + папки, що реально стоять на книгах
    /// (обʼєднання, щоб назви з книг не губились)
    static func folders(including books: [ReaderBook]) -> [String] {
        var list = EmbarDefaults.store.stringArray(forKey: foldersKey) ?? []
        for name in books.compactMap(\.folderName) where !list.contains(name) {
            list.append(name)
        }
        return list
    }

    /// Прибрати папку зі списку (книги чіпає View — їй вирішувати,
    /// зберегти їх чи видалити разом)
    static func removeFolder(_ name: String) {
        var list = EmbarDefaults.store.stringArray(forKey: foldersKey) ?? []
        list.removeAll { $0 == name }
        EmbarDefaults.store.set(list, forKey: foldersKey)
    }

    /// Додати папку в список (дублікати не плодимо). Повертає чисту назву
    @discardableResult
    static func addFolder(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var list = EmbarDefaults.store.stringArray(forKey: foldersKey) ?? []
        if !list.contains(name) {
            list.append(name)
            EmbarDefaults.store.set(list, forKey: foldersKey)
        }
        return name
    }

    // MARK: - Джерело (link-bar; блокнот має одне джерело — sources[0])

    /// Зберегти URL з link-bar: порожній рядок → без джерела; інакше
    /// нормалізуємо до https і виводимо label з домену (прототип saveReaderLink).
    /// Старі джерела — SOFT-delete (правило «never hard-delete user data»;
    /// code review M5 #8): читання йде через activeSource, чистить purge
    static func setSource(_ raw: String, for book: ReaderBook, in context: ModelContext) {
        for old in book.sources ?? [] where old.deletedAt == nil {
            old.deletedAt = .now
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let source = ReaderSource(url: normalizedURL(trimmed), label: sourceLabel(trimmed))
            source.book = book
            context.insert(source)
        }
        book.updatedAt = .now
    }

    /// «example.com» → «https://example.com»; те, що вже починається
    /// з http, не чіпаємо (поведінка прототипу)
    static func normalizedURL(_ raw: String) -> String {
        raw.hasPrefix("http") ? raw : "https://" + raw
    }

    /// Лейбл джерела = хост без протоколу: «https://a.com/read/1» → «a.com»
    static func sourceLabel(_ raw: String) -> String {
        var s = normalizedURL(raw)
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        return String(s.split(separator: "/").first ?? "")
    }

    // MARK: - Записи

    /// Додати запис. Порожній author не зберігаємо (nil, не "").
    @discardableResult
    static func addEntry(kind: ReaderEntryKind, text: String,
                         author: String? = nil,
                         photoData: Data? = nil,
                         audioData: Data? = nil, audioDuration: Double? = nil,
                         to book: ReaderBook, in context: ModelContext) -> ReaderEntry {
        let entry = ReaderEntry(kind: kind,
                                text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        entry.author = nonEmpty(author)
        entry.photoData = photoData
        entry.audioData = audioData
        entry.audioDuration = audioDuration
        entry.book = book
        // Активна тема тегує все нове (2026-07-21); nil = загальний потік
        entry.theme = book.activeTheme
        context.insert(entry)
        book.updatedAt = .now
        return entry
    }

    // MARK: - Теми (2026-07-21, «теми замість сторінок»)

    /// Створити тему і одразу зробити її активною
    @discardableResult
    static func createTheme(name: String, in book: ReaderBook,
                            context: ModelContext) -> ReaderTheme? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let theme = ReaderTheme(name: trimmed)
        theme.book = book
        context.insert(theme)
        activate(theme, in: book)
        return theme
    }

    /// Інваріант «одна активна тема на блокнот» живе тут
    static func activate(_ theme: ReaderTheme, in book: ReaderBook) {
        for other in book.themes ?? [] where other.isActive {
            other.isActive = false
        }
        theme.isActive = true
        theme.updatedAt = .now
        book.updatedAt = .now
    }

    /// Завершити тему: нові записи знову йдуть у загальний потік
    static func finishActiveTheme(in book: ReaderBook) {
        guard let active = book.activeTheme else { return }
        active.isActive = false
        active.updatedAt = .now
        book.updatedAt = .now
    }

    /// Порожня тема при завершенні — сміття, ховаємо замість лишати
    /// завершеною (закриває і гонку «скасувати чернетку»: blur від кліку
    /// по кнопці встигає створити тему — code review 2026-07-23)
    static func discardTheme(_ theme: ReaderTheme) {
        theme.isActive = false
        theme.deletedAt = .now
        theme.updatedAt = .now
        theme.book?.updatedAt = .now
    }

    /// Перейменування — клік по назві в розділювачі (інлайн)
    static func renameTheme(_ theme: ReaderTheme, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != theme.name else { return }
        theme.name = trimmed
        theme.updatedAt = .now
    }

    /// Замінити фото запису (кроп 2026-07-22); nil — прибрати
    static func setPhoto(_ data: Data?, for entry: ReaderEntry) {
        entry.photoData = data
        touch(entry)
    }

    static func editText(_ text: String, of entry: ReaderEntry) {
        adjustHighlights(of: entry, old: entry.text as NSString,
                         new: text as NSString)
        entry.text = text
        touch(entry)
    }

    /// Хайлайти липнуть до СВОГО тексту при редагуванні (фідбек
    /// 2026-07-22: діапазони індексні, без корекції вони зʼїжджали на
    /// сусідні слова). Правку зводимо до заміни одного відрізка —
    /// спільний префікс/суфікс старого й нового тексту (типовий
    /// однокурсорний ввід); діапазони до правки стоять, після —
    /// зсуваються, перетнуті обрізаються, поглинуті зникають.
    private static func adjustHighlights(of entry: ReaderEntry,
                                         old: NSString, new: NSString) {
        let live = (entry.highlights ?? []).filter { $0.deletedAt == nil }
        guard !live.isEmpty else { return }
        var prefix = 0
        let maxShared = min(old.length, new.length)
        while prefix < maxShared,
              old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        while suffix < maxShared - prefix,
              old.character(at: old.length - 1 - suffix)
                  == new.character(at: new.length - 1 - suffix) {
            suffix += 1
        }
        let editStart = prefix
        let oldEditEnd = old.length - suffix
        let newEditEnd = new.length - suffix
        let delta = newEditEnd - oldEditEnd
        guard delta != 0 || editStart < oldEditEnd else { return } // текст той самий
        for h in live {
            if h.end <= editStart { continue }        // повністю до правки
            if h.start >= oldEditEnd {                // повністю після — зсув
                h.start += delta
                h.end += delta
                continue
            }
            if h.start < editStart, h.end > oldEditEnd {
                h.end += delta                        // обіймає правку — тягнеться
            } else if h.start < editStart {
                h.end = editStart                     // хвіст у правці — обрізати
            } else if h.end > oldEditEnd {
                h.start = newEditEnd                  // голова у правці
                h.end += delta
            } else {
                // «Всередині правки», але текст, можливо, живий: дві
                // правки по краях однієї сесії дають ОДИН спільний
                // відрізок, і незайманий хайлайт між ними опинявся б
                // «усередині» — шукаємо той самий текст у новому відрізку
                // і переносимо; зник справді — ховаємо
                // (code review 2026-07-23)
                var relocated = false
                if h.start >= 0, h.end <= old.length {
                    let piece = old.substring(
                        with: NSRange(location: h.start, length: h.end - h.start))
                    let found = new.range(
                        of: piece, options: [],
                        range: NSRange(location: editStart,
                                       length: newEditEnd - editStart))
                    if found.location != NSNotFound {
                        h.start = found.location
                        h.end = found.location + found.length
                        relocated = true
                    }
                }
                if !relocated { h.deletedAt = .now }
            }
            if h.deletedAt == nil, h.end <= h.start { h.deletedAt = .now }
        }
    }

    /// Знімок хайлайтів перед правкою тексту: Cmd+Z повертає не лише
    /// текст, а й діапазони та «життя» хайлайтів, які adjustHighlights
    /// обрізав чи сховав (code review 2026-07-23)
    typealias HighlightSnapshot = [(highlight: Highlight, start: Int,
                                    end: Int, deletedAt: Date?)]

    static func highlightSnapshot(of entry: ReaderEntry) -> HighlightSnapshot {
        (entry.highlights ?? []).map { ($0, $0.start, $0.end, $0.deletedAt) }
    }

    /// Відкат правки тексту: сирий текст (БЕЗ adjustHighlights — він
    /// би не повернув видалене) + відновлення знімка
    static func restoreTextEdit(_ text: String, snapshot: HighlightSnapshot,
                                of entry: ReaderEntry) {
        entry.text = text
        for item in snapshot {
            item.highlight.start = item.start
            item.highlight.end = item.end
            item.highlight.deletedAt = item.deletedAt
        }
        touch(entry)
    }

    /// Стерти покриття інструмента в діапазоні (повторний прохід тим
    /// самим маркером/підкресленням = прибрати; фідбек 2026-07-22).
    /// Краї, що виступають за діапазон, живуть далі окремими шматками.
    /// Повертає (сховані, створені) — для undo
    static func eraseHighlights(start: Int, end: Int, colorName: String,
                                mode: String, from entry: ReaderEntry,
                                in context: ModelContext)
        -> (removed: [Highlight], added: [Highlight]) {
        var removed: [Highlight] = []
        var added: [Highlight] = []
        for h in (entry.highlights ?? [])
        where h.deletedAt == nil && h.mode == mode && h.colorName == colorName
            && h.end > start && h.start < end {
            removed.append(h)
            h.deletedAt = .now
            if h.start < start {
                let left = Highlight(start: h.start, end: start,
                                     colorName: colorName, mode: mode)
                left.entry = entry
                context.insert(left)
                added.append(left)
            }
            if h.end > end {
                let right = Highlight(start: end, end: h.end,
                                      colorName: colorName, mode: mode)
                right.entry = entry
                context.insert(right)
                added.append(right)
            }
        }
        touch(entry)
        return (removed, added)
    }

    static func toggleFavorite(_ entry: ReaderEntry) {
        entry.favorite.toggle()
        touch(entry)
    }

    static func softDeleteEntry(_ entry: ReaderEntry) {
        entry.deletedAt = .now
        touch(entry)
    }

    static func undoDeleteEntry(_ entry: ReaderEntry) {
        entry.deletedAt = nil
        touch(entry)
    }

    // MARK: - Хайлайти

    /// Додати хайлайт/підкреслення до діапазону UTF-16 у text запису.
    /// Валідність діапазону гарантує View перед викликом; рендер додатково
    /// ігнорує биті діапазони (SPEC §11.6).
    @discardableResult
    static func addHighlight(start: Int, end: Int, colorName: String, mode: String,
                             to entry: ReaderEntry, in context: ModelContext) -> Highlight {
        let highlight = Highlight(start: start, end: end, colorName: colorName, mode: mode)
        highlight.entry = entry
        context.insert(highlight)
        touch(entry)
        return highlight
    }

    static func softDeleteHighlight(_ highlight: Highlight) {
        highlight.deletedAt = .now
        if let entry = highlight.entry { touch(entry) }
    }

    static func undoDeleteHighlight(_ highlight: Highlight) {
        highlight.deletedAt = nil
        if let entry = highlight.entry { touch(entry) }
    }

    // MARK: - Цитата → нотатка (SPEC §12.3, крок 16)

    /// Вставити запис блоком-цитатою: existing == nil → нова нотатка
    /// (title = назва блокнота, born=reader); інакше — доклеїти в кінець.
    /// Тости показує View (як скрізь).
    @discardableResult
    static func quoteToNote(entry: ReaderEntry, book: ReaderBook,
                            into existing: Note?,
                            in context: ModelContext) -> Note {
        let block = ReaderQuoteBuilder.block(
            bookID: book.id, bookTitle: book.title,
            entryID: entry.id, kind: entry.kind,
            text: entry.text, author: entry.author)

        let note: Note
        if let existing {
            let current = NSMutableAttributedString()
            if let data = existing.contentData,
               let decoded = NoteArchiver.decode(data) {
                current.append(decoded)
            } else if !existing.content.isEmpty {
                // До-M4 плейн-нотатка: конвертуємо дзеркало в p-абзац
                current.append(NSAttributedString(
                    string: existing.content,
                    attributes: [
                        .embarRole: ParagraphRole.p.rawValue as NSString,
                        .font: NoteTypography.font(role: .p),
                        .foregroundColor: NoteTypography.inkColor,
                        .paragraphStyle: NoteTypography.paragraphStyle(role: .p),
                    ]))
            }
            if current.length > 0, !current.string.hasSuffix("\n") {
                current.append(NSAttributedString(string: "\n"))
            }
            current.append(block)
            existing.contentData = NoteArchiver.encode(current)
            existing.contentVersion = 1
            existing.content = NoteArchiver.plainText(current)
            existing.updatedAt = .now
            note = existing
        } else {
            let created = Note(title: book.title)
            created.bornType = "reader"
            created.bornDate = entry.createdAt // дата запису-джерела
            created.sourceBook = book
            created.contentData = NoteArchiver.encode(block)
            created.contentVersion = 1
            created.content = NoteArchiver.plainText(block)
            context.insert(created)
            note = created
        }
        return note
    }

    // MARK: - Помічники

    private static func touch(_ entry: ReaderEntry) {
        entry.updatedAt = .now
        entry.book?.updatedAt = .now
    }

    private static func nonEmpty(_ s: String?) -> String? {
        let trimmed = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
