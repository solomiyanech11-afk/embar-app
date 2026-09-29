//
//  NoteEditorModel.swift
//  Embar
//
//  Стан одного відкритого редактора нотатки. Поки редактор відкритий,
//  NSTextStorage тіла — ЄДИНЕ джерело правди (SwiftUI не пише текст назад);
//  save читає з text view. Це прибирає клас багів «скинутий курсор / цикл
//  update». Автозбереження: дебаунс 0.8с + при закритті + на кожну команду.
//

import SwiftUI
import SwiftData
import Combine

/// Активне форматування на курсорі/виділенні — керує підсвіткою кнопок тулбара
struct NoteSelectionState: Equatable {
    var role: ParagraphRole = .p
    var bold = false
    var italic = false
    var alignment: NSTextAlignment = .natural
    var list: ListStyle? = nil
    var quote = false
    var highlight: HighlightColor? = nil
    var textColor: BodyTextColor? = nil
}

@MainActor
final class NoteEditorModel: ObservableObject {
    /// ❗ Модель умирає при КОЖНІЙ навігації між нотатками (.id(note.id)
    /// перебудовує редактор). Без явного deinit компілятор синтезує
    /// ІЗОЛЬОВАНИЙ, і його back-deploy шлях у рантаймі псує купу, коли
    /// останнє посилання відпускається всередині Task — далі фриз/краш у
    /// довільному місці (блокер «⌘Z після видалення цілі звʼязку»,
    /// 2026-08-26; механізм і правило — CLAUDE.md «Ізольований deinit»)
    nonisolated deinit {}

    let note: Note
    private let context: ModelContext

    /// Заголовок — дзеркало note.title (TextField у SwiftUI); тіло — у NSTextView
    @Published var title: String
    /// Налаштування рендеру (розмір/інтервал) — редагуються у кроці 11
    @Published var settings: NoteDocSettings
    /// Стан форматування на курсорі — для активних кнопок тулбара
    @Published var selection = NoteSelectionState()

    /// Активний запит `[[` — керує попапом згадок (SPEC §3.4)
    struct MentionQuery: Equatable {
        var range: NSRange   // покриває «[[запит»
        var query: String
        /// Рядок із «[[» у координатах видимої області тіла: попап стає
        /// щільно під ним або щільно над ним (фідбек 2026-09-03)
        var anchor: CGRect
    }
    @Published var mention: MentionQuery?
    @Published var mentionSelection = 0
    /// Кандидати попапа — on-demand fetch при зміні запиту (постійний
    /// @Query всіх нотаток у редакторі ре-фетчив таблицю на кожен autosave)
    @Published private(set) var mentionCandidates: [Note] = []

    private(set) weak var textView: EmbarTextView?
    private var saveTask: Task<Void, Never>?
    /// Чи є незбережені зміни. saveNow без змін — no-op: відкрити-закрити
    /// нотатку НЕ бампає updatedAt і не пересортовує список (code review)
    private var dirty = false

    init(note: Note, context: ModelContext) {
        self.note = note
        self.context = context
        self.title = note.title
        self.settings = NoteDocSettings(note: note)
    }

    func attach(_ tv: EmbarTextView) { textView = tv }

    // MARK: - Завантаження документа (лінива міграція)

    /// Побудувати початковий вміст тіла: декодувати архів або (для старих
    /// нотаток contentVersion 0) взяти плейн `content` як один абзац P.
    /// Чіпи-згадки освіжаються (титули) і чистяться (purged → плейн-текст).
    func loadDocument() -> NSAttributedString {
        let doc: NSMutableAttributedString
        if note.contentVersion >= 1, let data = note.contentData,
           let decoded = NoteArchiver.decode(data) {
            doc = NSMutableAttributedString(attributedString: decoded)
        } else {
            doc = NSMutableAttributedString(string: note.content, attributes: bodyTypingAttributes())
        }
        refreshMentionChips(in: doc)
        attachPhotoResolvers(in: doc)
        return doc
    }

    /// Дати кожному фото-attachment резолвер (зображення живуть у NoteImage,
    /// не в архіві — тож підставляються при відкритті). Заодно самолікування:
    /// абзац фото отримує стиль без lineHeightMultiple (старі нотатки
    /// зберігали текстовий 1.75 — фото «провалювалось» вниз рядка)
    /// Фрагмент, що приїхав ззовні (драг усередині тіла або вставка нашого
    /// архіву), проходить той самий крок, що й документ при відкритті:
    /// attachment-и фото декодуються без резолвера, тож без цього ряд
    /// намалювався б сірими плитками (F2, тест-план 2026-08-25)
    func reviveFragment(_ doc: NSMutableAttributedString) {
        attachPhotoResolvers(in: doc)
    }

    private func attachPhotoResolvers(in doc: NSMutableAttributedString) {
        let s = doc.string as NSString
        doc.enumerateAttribute(.attachment, in: NSRange(location: 0, length: doc.length)) { v, r, _ in
            if let att = v as? EmbarPhotoRowAttachment {
                att.resolver = { [context] id in NoteImageStore.resolve(id, in: context) }
                let pr = s.paragraphRange(for: r)
                doc.addAttribute(.paragraphStyle,
                                 value: NoteTypography.photoRowParagraphStyle(), range: pr)
            }
        }
    }

    /// Титули чіпів освіжаються при відкритті (не live — рішення §3.4);
    /// згадка на ФІЗИЧНО видалену нотатку деградує в плейн-текст (§12.5)
    private func refreshMentionChips(in doc: NSMutableAttributedString) {
        var edits: [(NSRange, String?, String)] = [] // (ран, новий титул | nil=зняти, uuid)
        doc.enumerateAttribute(.embarMention, in: NSRange(location: 0, length: doc.length)) { v, r, _ in
            guard let raw = v as? String else { return }
            guard let uuid = UUID(uuidString: raw),
                  let target = NoteService.find(uuid, in: context) else {
                edits.append((r, nil, raw))
                return
            }
            let title = Self.chipTitle(for: target)
            if doc.attributedSubstring(from: r).string != title {
                edits.append((r, title, raw))
            }
        }
        for (r, title, raw) in edits.reversed() {
            if let title {
                var attrs = doc.attributes(at: r.location, effectiveRange: nil)
                attrs[.embarMention] = raw as NSString
                doc.replaceCharacters(in: r, with: NSAttributedString(string: title, attributes: attrs))
            } else {
                doc.removeAttribute(.embarMention, range: r)
            }
        }
        // Косметика чіпів — з маркерів (self-healing: старі чіпи, збережені
        // до зміни стилю, підтягуються при відкритті)
        doc.enumerateAttribute(.embarMention, in: NSRange(location: 0, length: doc.length)) { v, r, _ in
            guard v is String else { return }
            let attrs = doc.attributes(at: r.location, effectiveRange: nil)
            doc.addAttribute(.font, value: NoteFormatter.font(from: attrs, settings: settings), range: r)
            doc.addAttribute(.foregroundColor, value: NoteTypography.mentionTextColor, range: r)
        }
    }

    /// Типові атрибути для нового тексту тіла (роль P) — єдине джерело
    /// в NoteFormatter (дубль розходився б; code review)
    func bodyTypingAttributes() -> [NSAttributedString.Key: Any] {
        NoteFormatter.plainTypingAttributes(settings: settings)
    }

    // MARK: - Збереження

    /// Дебаунс-збереження після вводу (позначає незбережені зміни)
    func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Негайне збереження: архів тіла + плейн-дзеркало + заголовок + sync
    /// згадок (SPEC §11.3) + updatedAt. Без змін — no-op.
    func saveNow() {
        saveTask?.cancel()
        guard dirty else { return }
        dirty = false
        note.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tv = textView {
            let body = tv.attributedString()
            // ❗ Невдале кодування НЕ сміє затирати наявний архів — інакше
            // одна помилка серіалізації знищила б rich-тіло назавжди
            if let encoded = NoteArchiver.encode(body) {
                note.contentData = encoded
                note.contentVersion = 1
            } else {
                assertionFailure("NoteArchiver.encode повернув nil — архів не оновлено")
            }
            note.content = NoteArchiver.plainText(body)
            var ids: Set<UUID> = []
            body.enumerateAttribute(.embarMention, in: NSRange(location: 0, length: body.length)) { v, _, _ in
                if let raw = v as? String, let u = UUID(uuidString: raw) { ids.insert(u) }
            }
            NoteService.syncMentions(ids, for: note, in: context)
        }
        note.updatedAt = .now
        // Кеш списку (F5.4): title/content у зліпок не входять, а от
        // updatedAt — ключ сортування, тож збереження змінює порядок
        NoteMutation.changed(note)
    }

    // MARK: - Попап згадок `[[` (SPEC §3.4)

    /// Пересканувати запит `[[` на курсорі (викликається на кожен ввід/рух)
    func rescanMention() {
        guard let tv = textView else { return }
        var new = Self.scanMention(tv)
        // Закритий назавжди «[[» (P2.23): після хрестика чи Escape попап
        // не повертається, поки ЦЕЙ «[[» живе на своєму місці. Інший
        // «[[» (інша позиція) або зникнення цього — памʼять чиститься
        if let dismissed = dismissedMentionAt {
            if let found = new, found.range.location == dismissed {
                new = nil
            } else if new != nil || !Self.hasMentionOpener(tv, at: dismissed) {
                dismissedMentionAt = nil
            }
        }
        if new != mention {
            let queryChanged = new?.query != mention?.query || (new != nil && mention == nil)
            mention = new
            mentionSelection = 0
            if new == nil {
                mentionCandidates = []
            } else if queryChanged {
                updateMentionCandidates(query: new?.query ?? "")
            }
        }
    }

    /// Позиція «[[», який людина закрила хрестиком/Escape (P2.23)
    private var dismissedMentionAt: Int?

    /// Хрестик у попапі або Escape: закрити попап для ЦЬОГО «[[» назавжди
    func dismissMention() {
        dismissedMentionAt = mention?.range.location
        mention = nil
        mentionCandidates = []
    }

    /// «[[» досі стоїть на цій позиції? (страховка від застарілої памʼяті:
    /// текст могли переписати, і на цьому місці вже інший вміст)
    private static func hasMentionOpener(_ tv: EmbarTextView, at location: Int) -> Bool {
        guard let storage = tv.textStorage, location >= 0,
              location + 2 <= storage.length else { return false }
        return (storage.string as NSString)
            .substring(with: NSRange(location: location, length: 2)) == "[["
    }

    /// Свіжі кандидати одним обмеженим фетчем (без постійного @Query)
    private func updateMentionCandidates(query: String) {
        let selfID = note.id
        var d = FetchDescriptor<Note>(
            predicate: #Predicate { $0.deletedAt == nil && $0.id != selfID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        d.fetchLimit = 50
        let recent = (try? context.fetch(d)) ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? recent : recent.filter { $0.title.lowercased().contains(q) }
        mentionCandidates = Array(filtered.prefix(8))
    }

    /// Порт qnMentionScan: «[[» у поточному абзаці ліворуч від каретки,
    /// без «]]» після, запит ≤ 40 символів, не всередині чіпа
    private static func scanMention(_ tv: EmbarTextView) -> MentionQuery? {
        let sel = tv.selectedRange()
        guard sel.length == 0, let storage = tv.textStorage, storage.length > 0,
              sel.location <= storage.length else { return nil }
        let s = storage.string as NSString
        let pr = s.paragraphRange(for: NSRange(location: min(sel.location, s.length), length: 0))
        guard sel.location > pr.location else { return nil }
        // Вікно пошуку «[[»: запит обмежений 40 одиницями — далі 42 позаду
        // курсора не заглядаємо (раніше копіювався ввесь абзац до каретки
        // на КОЖЕН рух — зайва алокація; review perf)
        let windowStart = max(pr.location, sel.location - 42)
        let open = s.range(of: "[[", options: .backwards,
                           range: NSRange(location: windowStart,
                                          length: sel.location - windowStart))
        guard open.location != NSNotFound else { return nil }
        let query = s.substring(with: NSRange(location: open.location + open.length,
                                              length: sel.location - open.location - open.length))
        guard !query.contains("]]"), !query.contains("\n"), query.utf16.count <= 40 else { return nil }
        let start = open.location
        if start < storage.length,
           storage.attribute(.embarMention, at: start, effectiveRange: nil) != nil { return nil }
        let range = NSRange(location: start, length: sel.location - start)
        return MentionQuery(range: range, query: query, anchor: anchorRect(for: range, in: tv))
    }

    /// Прямокутник рядка з «[[…» у координатах видимої області тіла
    /// (text view flipped, скрол-офсет — bounds клип-в'ю). Потрібні ОБИДВА
    /// краї: попап стає під низ рядка або над його верх
    private static func anchorRect(for range: NSRange, in tv: NSTextView) -> CGRect {
        guard let window = tv.window else { return .zero }
        let screenRect = tv.firstRect(forCharacterRange: range, actualRange: nil)
        let winRect = window.convertFromScreen(screenRect)
        let tvRect = tv.convert(winRect, from: nil)
        let clipOrigin = tv.enclosingScrollView?.contentView.bounds.origin ?? .zero
        return tvRect.offsetBy(dx: -clipOrigin.x, dy: -clipOrigin.y)
    }

    /// Клавіші попапа (з text view; фокус не мігрує). true = спожито
    func handleMentionKey(_ key: EmbarTextView.MentionKey) -> Bool {
        guard let q = mention else { return false }
        let createRow = q.query.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1
        let count = mentionCandidates.count + createRow
        switch key {
        case .close:
            dismissMention() // Escape = «для цього [[ більше не пропонуй» (P2.23)
            return true
        case .up:
            mentionSelection = max(0, mentionSelection - 1)
            return true
        case .down:
            mentionSelection = min(max(count - 1, 0), mentionSelection + 1)
            return true
        case .commit:
            commitMention()
            return true
        }
    }

    /// Вставити вибрану згадку (або створити нову нотатку з запиту)
    func commitMention() {
        guard let q = mention else { return }
        defer { mention = nil }
        if mentionSelection < mentionCandidates.count {
            insertMention(mentionCandidates[mentionSelection], replacing: q.range)
            return
        }
        let name = q.query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Режим читання: «＋ Створити» з попапа згадок - теж створення
        guard ProGate.allowCreate() else { return }
        let created = NoteService.add(title: name, in: context)
        insertMention(created, replacing: q.range)
    }

    /// Чіп = ран тексту (титул) з .embarMention + NBSP після (щоб набір
    /// продовжувався ПОЗА чіпом)
    /// Текст чіпа: довга назва обрізається до 30 знаків із трьома
    /// крапочками (фідбек 2026-09-03) — інакше пігулка на пів абзацу.
    /// Одне джерело для вставки і для освіження титулів при відкритті:
    /// вони порівнюють рядки, і різні правила давали б вічний ре-запис
    static func chipTitle(for note: Note) -> String {
        let raw = note.title.isEmpty
            ? String(localized: "Без назви", comment: "Титул чіпа-згадки для нотатки без назви")
            : note.title
        return raw.truncatedChip(30)
    }

    private func insertMention(_ target: Note, replacing range: NSRange) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let title = Self.chipTitle(for: target)
        var base = tv.typingAttributes
        base[.embarMention] = nil
        base[.embarHighlight] = nil
        base[.link] = nil
        var chipAttrs = base
        chipAttrs[.embarMention] = target.id.uuidString as NSString
        // Текст чіпа — менший і приглушений (фідбек 2026-07-05)
        chipAttrs[.font] = NoteFormatter.font(from: chipAttrs, settings: settings)
        chipAttrs[.foregroundColor] = NoteTypography.mentionTextColor
        let out = NSMutableAttributedString(string: title, attributes: chipAttrs)
        out.append(NSAttributedString(string: "\u{00A0}", attributes: base))
        guard tv.shouldChangeText(in: range, replacementString: out.string) else { return }
        storage.replaceCharacters(in: range, with: out)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + out.length, length: 0))
        tv.window?.makeFirstResponder(tv)
        dirty = true // гарантована мутація тіла
        saveNow()
    }

    // MARK: - Форматування (тулбар). Кожна команда мутує NSTextStorage,
    // оновлює стан кнопок і зберігає.

    private func format(_ body: (EmbarTextView) -> Void) {
        guard let tv = textView else { return }
        body(tv)
        refreshSelection()
        scheduleSave()
    }

    func toggleBold()  { format { NoteFormatter.toggleBold($0, settings: settings) } }
    func toggleItalic() { format { NoteFormatter.toggleItalic($0, settings: settings) } }
    func setRole(_ r: ParagraphRole) { format { NoteFormatter.setRole(r, in: $0, settings: settings) } }
    func setAlignment(_ a: NSTextAlignment) { format { NoteFormatter.setAlignment(a, in: $0, settings: settings) } }
    func toggleHighlight(_ c: HighlightColor) { format { NoteFormatter.toggleHighlight(c, in: $0) } }
    func setTextColor(_ c: BodyTextColor?) { format { NoteFormatter.setTextColor(c, in: $0) } }
    func toggleQuote() { format { NoteFormatter.toggleQuote($0, settings: settings) } }
    func toggleList(_ s: ListStyle) { format { NoteFormatter.toggleList(s, in: $0, settings: settings) } }

    /// Перечитати стан форматування з курсора → підсвітка кнопок тулбара
    func refreshSelection() {
        guard let tv = textView else { return }
        let new = NoteFormatter.state(of: tv, settings: settings)
        if new != selection { selection = new }
    }

    // MARK: - Фото (SPEC §3.2)

    /// Вставити ряд із `columns` фото (1–3): вибір файлів → даунскейл у
    /// контейнер → attachment на власному рядку
    func insertPhotoRow(columns: Int) {
        guard textView != nil else { return }
        // Пікер неблокуючий (стоп-баг 2026-07-29) — вставка в completion;
        // selectedRange читається ТАМ (свіжий на момент вибору)
        NoteImageStore.pickImages(count: columns) { [weak self] urls in
            self?.finishPhotoRowInsert(urls: urls, columns: columns)
        }
    }

    private func finishPhotoRowInsert(urls: [URL], columns: Int) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        // Після діалогу повернути панель наперед і фокус у тіло
        tv.window?.orderFrontRegardless()
        tv.window?.makeFirstResponder(tv)
        guard !urls.isEmpty else { return }
        let ids = NoteImageStore.importImages(from: urls, note: note, in: context)
        guard !ids.isEmpty else { return }

        let att = EmbarPhotoRowAttachment(imageIDs: ids.map(\.uuidString),
                                          columns: min(ids.count, max(columns, 1)))
        att.resolver = { [context] id in NoteImageStore.resolve(id, in: context) }

        let attrs = bodyTypingAttributes()
        // Абзац фото — власний стиль без lineHeightMultiple (інакше рядок
        // у 1.75× вищий за фото і знімок «провалюється» вниз)
        var photoAttrs = attrs
        photoAttrs[.paragraphStyle] = NoteTypography.photoRowParagraphStyle()
        let sel = tv.selectedRange()
        let s = storage.string as NSString
        let block = NSMutableAttributedString()
        // Фото — на власному рядку, точно де стояв курсор (фідбек 2026-07-05):
        // порожній рядок → фото НА ньому; всередині тексту — розрив;
        // переноси додаються лише коли їх реально бракує (без порожніх рядків)
        if sel.location > 0, s.character(at: sel.location - 1) != 0x0A {
            block.append(NSAttributedString(string: "\n", attributes: attrs))
        }
        let attachStr = NSMutableAttributedString(attachment: att)
        attachStr.addAttributes(photoAttrs, range: NSRange(location: 0, length: attachStr.length))
        block.append(attachStr)
        let after = sel.location + sel.length
        if after >= s.length || s.character(at: after) != 0x0A {
            block.append(NSAttributedString(string: "\n", attributes: photoAttrs))
        }

        guard tv.shouldChangeText(in: sel, replacementString: block.string) else { return }
        storage.replaceCharacters(in: sel, with: block)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: sel.location + block.length, length: 0))
        tv.typingAttributes = attrs
        dirty = true // гарантована мутація тіла
        saveNow()
        tv.needsDisplay = true
    }

    // MARK: - Hover-дії фото: видалити / замінити / обітнути (фідбек 2026-07-05)

    /// Слот фото під мишкою (пігулку дій малює NoteEditorView)
    @Published var photoHover: EmbarTextView.PhotoHoverInfo?
    /// Мишка на самій пігулці дій — не гасити hover, коли text view шле exit
    var photoHoverHold = false
    /// Запит на кроп: шит відкриває NoteEditorView
    struct CropRequest: Identifiable {
        let id = UUID()
        let imageID: UUID
        let hover: EmbarTextView.PhotoHoverInfo
    }
    @Published var cropRequest: CropRequest?

    func setPhotoHover(_ info: EmbarTextView.PhotoHoverInfo?) {
        if info == nil && photoHoverHold { return }
        if photoHover != info { photoHover = info }
    }

    /// Скинути hover-стан пігулки повністю (єдиний власник життєвого циклу:
    /// SwiftUI не гарантує onHover(false) при знятті в'ю — латка залипала)
    func clearPhotoHover() {
        photoHoverHold = false
        photoHover = nil
    }

    /// Живий attachment за індексом hover-у. Документ міг змінитися між
    /// наведенням і дією (autosave/undo/кроп-шит) — знімку ids/columns
    /// довіряти не можна, читаємо ЖИВІ значення (code review)
    private func livePhotoRow(at charIndex: Int) -> EmbarPhotoRowAttachment? {
        guard let storage = textView?.textStorage, charIndex < storage.length else { return nil }
        return storage.attribute(.attachment, at: charIndex, effectiveRange: nil)
            as? EmbarPhotoRowAttachment
    }

    /// Прибрати слот; останній слот → видалити весь ряд (+ його перенос).
    /// Кожне видалення — з undo-тостом «Повернути» (фідбек 2026-07-29:
    /// правило «при кожній кнопці видалення — 5с опція повернути»)
    func deletePhotoSlot(_ info: EmbarTextView.PhotoHoverInfo) {
        clearPhotoHover()
        // textStorage лишається передумовою (без нього нижні правки тіла
        // нікуди не лягли б), але саме значення тут не потрібне
        guard let tv = textView, tv.textStorage != nil,
              let att = livePhotoRow(at: info.charIndex) else { return }
        var ids = att.imageIDs
        guard ids.indices.contains(info.slotIndex) else { return }
        let oldIds = ids
        ids.remove(at: info.slotIndex)
        if ids.isEmpty {
            deletePhotoRow(at: info.charIndex)
            return
        }
        replacePhotoAttachment(at: info.charIndex, ids: ids, columns: ids.count, tv: tv)
        dirty = true // гарантована мутація тіла
        saveNow()
        postUndoToast("Фото видалено") { [weak self] in
            guard let self, let tv = self.textView,
                  self.livePhotoRow(at: info.charIndex) != nil else { return }
            self.replacePhotoAttachment(at: info.charIndex, ids: oldIds,
                                        columns: oldIds.count, tv: tv)
            self.dirty = true
            self.saveNow()
        }
    }

    /// Видалити весь фото-ряд (+ його перенос) — ховер-пігулка з одним
    /// слотом і контекстне меню «Видалити фото»; з undo-тостом
    func deletePhotoRow(at charIndex: Int) {
        guard let tv = textView, let storage = tv.textStorage,
              charIndex < storage.length else { return }
        let s = storage.string as NSString
        var range = NSRange(location: charIndex, length: 1)
        if charIndex + 1 < s.length, s.character(at: charIndex + 1) == 0x0A {
            range.length += 1
        }
        // Знімок видаленого фрагмента: attachment-обʼєкти (з resolver-ами)
        // живуть у ньому і повертаються тим самим шматком
        let removed = storage.attributedSubstring(from: range)
        guard tv.shouldChangeText(in: range, replacementString: "") else { return }
        storage.replaceCharacters(in: range, with: "")
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: min(charIndex, storage.length),
                                    length: 0))
        dirty = true
        saveNow()
        postUndoToast("Фото видалено") { [weak self] in
            guard let self, let tv = self.textView,
                  let storage = tv.textStorage else { return }
            let loc = min(charIndex, storage.length)
            guard tv.shouldChangeText(in: NSRange(location: loc, length: 0),
                                      replacementString: removed.string)
            else { return }
            storage.insert(removed, at: loc)
            tv.didChangeText()
            self.dirty = true
            self.saveNow()
        }
    }

    /// Undo-тост з моделі (тости малює ContentView через ToastCenter)
    private func postUndoToast(_ message: LocalizedStringResource,
                               _ restore: @escaping () -> Void) {
        NotificationCenter.default.post(
            name: .embarUndoToast, object: nil,
            userInfo: ["message": message,
                       "action": ToastCenter.UndoAction(restore)])
    }

    /// Замінити фото у слоті (новий вибір файлу; пікер неблокуючий —
    /// стоп-баг 2026-07-29)
    func replacePhotoSlot(_ info: EmbarTextView.PhotoHoverInfo) {
        clearPhotoHover()
        guard textView != nil else { return }
        NoteImageStore.pickImages(count: 1) { [weak self] urls in
            guard let self, let tv = self.textView else { return }
            tv.window?.orderFrontRegardless()
            tv.window?.makeFirstResponder(tv)
            guard let url = urls.first,
                  let att = self.livePhotoRow(at: info.charIndex),
                  let newID = NoteImageStore.importImages(
                      from: [url], note: self.note, in: self.context).first
            else { return }
            var ids = att.imageIDs
            if ids.indices.contains(info.slotIndex) {
                ids[info.slotIndex] = newID.uuidString
            } else {
                ids.append(newID.uuidString)
            }
            self.replacePhotoAttachment(at: info.charIndex, ids: ids,
                                        columns: att.columns, tv: tv)
            self.dirty = true // гарантована мутація тіла
            self.saveNow()
        }
    }

    /// Відкрити кроп-редактор для слота
    func cropPhotoSlot(_ info: EmbarTextView.PhotoHoverInfo) {
        guard let raw = info.imageID, let uuid = UUID(uuidString: raw) else { return }
        clearPhotoHover()
        cropRequest = CropRequest(imageID: uuid, hover: info)
    }

    /// Зберегти обітнуте зображення в той самий NoteImage і перемалювати ряд
    func applyCrop(_ image: NSImage, for request: CropRequest) {
        defer { cropRequest = nil }
        guard let jpeg = NoteImageStore.downscaledJPEG(image), let tv = textView,
              let att = livePhotoRow(at: request.hover.charIndex),
              att.imageIDs.contains(request.imageID.uuidString) // ряд ще той самий?
        else { return }
        NoteImageStore.updateData(request.imageID, data: jpeg, in: context)
        // Свіжий attachment = скинутий кеш зображень → перемальовується
        replacePhotoAttachment(at: request.hover.charIndex, ids: att.imageIDs,
                               columns: att.columns, tv: tv)
        dirty = true // гарантована мутація тіла
        saveNow()
    }

    /// Пересадити attachment-символ на новий екземпляр (нові ids/кеш) —
    /// undo-дружньо: одна текстова заміна
    private func replacePhotoAttachment(at charIndex: Int, ids: [String], columns: Int,
                                        tv: EmbarTextView) {
        guard let storage = tv.textStorage, charIndex < storage.length,
              storage.attribute(.attachment, at: charIndex, effectiveRange: nil) != nil
        else { return }
        let old = storage.attributes(at: charIndex, effectiveRange: nil)
        let att = EmbarPhotoRowAttachment(imageIDs: ids, columns: columns)
        att.resolver = { [context] id in NoteImageStore.resolve(id, in: context) }
        let new = NSMutableAttributedString(attachment: att)
        new.addAttributes(old.filter { $0.key != .attachment },
                          range: NSRange(location: 0, length: new.length))
        let range = NSRange(location: charIndex, length: 1)
        guard tv.shouldChangeText(in: range, replacementString: new.string) else { return }
        storage.replaceCharacters(in: range, with: new)
        tv.didChangeText()
    }

    // MARK: - Налаштування нотатки (SPEC §3.3)

    /// Змінити налаштування вигляду: зберегти в нотатку + перерахувати стилі
    /// всього документа (ролі — маркери, тож це чиста косметика)
    func applySettings(size: BodySizeClass? = nil, font: NoteBodyFont? = nil,
                       spacing: NoteLineHeight? = nil) {
        if let size { settings.sizeClass = size; note.bodySizeRaw = size.rawValue }
        if let font { settings.font = font; note.bodyFontRaw = font.rawValue }
        if let spacing { settings.lineHeight = spacing; note.lineSpacingRaw = spacing.rawValue }
        note.updatedAt = .now
        NoteMutation.changed(note) // кеш списку (F5.4)
        if let tv = textView {
            tv.docSettings = settings
            NoteFormatter.restyleDocument(tv, settings: settings)
            if tv.string.isEmpty { tv.typingAttributes = bodyTypingAttributes() }
        }
        scheduleSave()
    }

    // MARK: - Eyebrow-дії (кожна зберігає)

    func togglePin() {
        NoteService.togglePin(note)
        objectWillChange.send()
    }

    func setAccent(_ index: Int?) {
        NoteService.setAccent(index, for: note)
        objectWillChange.send()
    }

    func setFolder(_ folder: NoteFolder?) {
        NoteService.setFolder(folder, for: note)
        objectWillChange.send()
    }
}
