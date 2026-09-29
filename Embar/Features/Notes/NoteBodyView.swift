//
//  NoteBodyView.swift
//  Embar
//
//  NSViewRepresentable тіла нотатки: NSTextView на примусовому TextKit 1 у
//  NSScrollView. Документ вантажиться ОДИН раз на note-id (порівняння в
//  координаторі) — SwiftUI не пише текст назад під час редагування, тож
//  курсор не скидається. Скрол живе всередині фіксованої панелі.
//

import SwiftUI
import AppKit

struct NoteBodyView: NSViewRepresentable {
    @ObservedObject var model: NoteEditorModel
    var onEscape: () -> Void
    var onMentionClick: (UUID) -> Void = { _ in }
    /// Клік по підпису цитати з Рідера (M5): (bookID, entryID)
    var onReaderSourceClick: (UUID, UUID) -> Void = { _, _ in }
    var spellcheck: Bool = true
    /// Нижній inset скролу (фідбек 2026-07-28): тулбар плаває НАД текстом,
    /// і рядок з курсором пірнав під нього при наборі внизу. Inset входить
    /// у видиму зону кліпа, тож штатний автоскрол NSTextView (набір,
    /// Enter, вставка блоку) сам тримає курсор над тулбаром із запасом
    var bottomInset: CGFloat = 0

    func makeNSView(context: Context) -> NSScrollView {
        // Явний стек TextKit 1 (детермінований layout: rect-запити, attachment-
        // верстка, малювання рамки цитати — усе стабільне під TextKit 1)
        let storage = NSTextStorage()
        // Наш layout manager: гасить системну заливку виділення в УСІХ
        // станах фокуса (Theme/SelectionColor.swift). Без нього при втраті
        // фокуса поверталась груба системна смуга на всю рядкову коробку
        let layout = EmbarSelectionLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let tv = EmbarTextView(frame: .zero, textContainer: container)
        tv.delegate = context.coordinator
        // Чіп-згадка переноситься на новий рядок ЦІЛОЮ пігулкою (P2.20):
        // text view як делегат layout manager забороняє перенос усередині
        // рана згадки (прототип: .qn-mention white-space:nowrap)
        layout.delegate = tv
        tv.isRichText = true
        tv.allowsUndo = true
        tv.isEditable = true
        tv.isSelectable = true
        tv.usesFontPanel = false
        tv.importsGraphics = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 18, height: 12)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.placeholder = String(localized: "Почніть писати…", comment: "Плейсхолдер порожнього тіла нотатки")
        tv.onEscape = onEscape
        tv.onMentionClick = onMentionClick
        tv.onReaderSourceClick = onReaderSourceClick
        tv.mentionKeyHandler = { [weak model] key in model?.handleMentionKey(key) ?? false }
        // ⌘B / ⌘I — ті самі дії, що кнопки тулбара (2026-08-20)
        tv.onToggleBold = { [weak model] in model?.toggleBold() }
        tv.onToggleItalic = { [weak model] in model?.toggleItalic() }
        tv.onPhotoHover = { [weak model] info in model?.setPhotoHover(info) }
        tv.onPhotoRowDelete = { [weak model] idx in model?.deletePhotoRow(at: idx) }
        tv.onReviveFragment = { [weak model] doc in model?.reviveFragment(doc) }
        tv.docSettings = model.settings
        tv.typingAttributes = model.bodyTypingAttributes()
        // Каретка — брендовий червоний (фідбек 2026-08-17: «зроби такий
        // самий червоний, як усюди»). До цього тут було чорнило, а в
        // SwiftUI-полях каретку фарбував АКЦЕНТ СИСТЕМИ — тобто колір
        // залежав від налаштувань macOS людини. Тепер обидва шляхи
        // брендові: тут явно, у полях — через AccentColor в асетах
        tv.insertionPointColor = NSColor(EmbarColors.brandRed)
        // Системну заливку виділення прибрано — малюємо свою, snug і
        // нашим тоном (див. EmbarTextView.drawSelection). Пара до
        // EmbarSelectionLayoutManager вище: атрибути прибирають заливку у
        // сфокусованому стані, layout manager — в усіх решті
        tv.selectedTextAttributes = [.backgroundColor: NSColor.clear]
        tv.isContinuousSpellCheckingEnabled = spellcheck

        let scroll = NSScrollView()
        scroll.documentView = tv
        // Правило «без видимих індикаторів»: singularно БЕЗ скролера — стійко
        // до legacy-стилю (мишка / «Show scroll bars: Always» скидали б
        // scrollerStyle і показували жолоб; review). Колесо/трекпад скролять.
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0,
                                            bottom: bottomInset, right: 0)

        model.attach(tv)
        context.coordinator.model = model
        context.coordinator.loadIfNeeded(into: tv)
        // Скрол → ховаємо hover-пігулку фото (її позиція вже неактуальна)
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.didScroll),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? EmbarTextView else { return }
        if scroll.contentInsets.bottom != bottomInset {
            scroll.contentInsets.bottom = bottomInset // фокус-режим без тулбара
        }
        context.coordinator.model = model
        tv.onEscape = onEscape
        tv.onMentionClick = onMentionClick
        tv.onReaderSourceClick = onReaderSourceClick
        tv.mentionKeyHandler = { [weak model] key in model?.handleMentionKey(key) ?? false }
        tv.onToggleBold = { [weak model] in model?.toggleBold() }
        tv.onToggleItalic = { [weak model] in model?.toggleItalic() }
        tv.onReviveFragment = { [weak model] doc in model?.reviveFragment(doc) }
        tv.docSettings = model.settings
        if tv.isContinuousSpellCheckingEnabled != spellcheck {
            tv.isContinuousSpellCheckingEnabled = spellcheck
        }
        context.coordinator.loadIfNeeded(into: tv)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var model: NoteEditorModel?
        private var loadedNoteID: UUID?

        /// Undo-стек РЕДАКТОРА, не вікна (блокер 2026-08-26): менеджер
        /// вікна один на всю панель — його операції переживали перемикання
        /// нотаток і цілили в text view, знищені переходом (NSUndoManager
        /// цілі не ретейнить → повідомлення у звільнену памʼять). Власний
        /// менеджер народжується і вмирає разом з редактором нотатки, тож
        /// ⌘Z ніколи не бачить чужих чи посмертних операцій
        let editorUndoManager = UndoManager()

        func undoManager(for view: NSTextView) -> UndoManager? {
            editorUndoManager
        }

        nonisolated deinit { NotificationCenter.default.removeObserver(self) }

        @objc func didScroll() {
            model?.clearPhotoHover()
        }

        /// Завантажити вміст рівно один раз на нотатку
        func loadIfNeeded(into tv: EmbarTextView) {
            guard let model, loadedNoteID != model.note.id else { return }
            loadedNoteID = model.note.id
            tv.textStorage?.setAttributedString(model.loadDocument())
            tv.typingAttributes = model.bodyTypingAttributes()
            tv.needsDisplay = true
            model.refreshSelection()
        }

        func textDidChange(_ notification: Notification) {
            model?.scheduleSave()
            model?.rescanMention()
        }

        /// Рух курсора/зміна виділення → оновити кнопки тулбара, пересканувати
        /// `[[`-запит і прибрати .embarMention з typing-атрибутів (інакше
        /// текст одразу після чіпа «продовжував» би чіп)
        func textViewDidChangeSelection(_ notification: Notification) {
            model?.refreshSelection()
            model?.rescanMention()
            if let tv = notification.object as? EmbarTextView {
                // Каретка біля чіпа/блоку не «продовжує» його атрибутами
                for key in [NSAttributedString.Key.embarMention, .embarReaderQuote,
                            .embarReaderSource, .embarQuoteAuthor]
                where tv.typingAttributes[key] != nil {
                    tv.typingAttributes[key] = nil
                }
            }
        }

        /// Атомарність чіпів/блоків: правка або покриває атом ЦІЛКОМ, або не
        /// торкається його. Розширення «зачепив частково — зноситься цілком»
        /// живе ДО цієї пари: виділення снапить selectionRange(forProposedRange:),
        /// клавіатурні delete-и добирає snapDeletionToAtom у EmbarTextView.
        /// Сюди частковий діапазон може принести хіба екзотика (спелчекер,
        /// сервіси) — відповідь «ні», атом лишається недоторканим.
        /// ❗ ЗАМІНЮВАТИ ТЕКСТ ЗСЕРЕДИНИ ЦЬОГО ВИКЛИКУ НЕ МОЖНА: NSTextView
        /// веде облік undo в парі shouldChangeText → didChangeText, і
        /// вкладена пара під час незавершеної зовнішньої ламала бухгалтерію —
        /// перший же ⌘Z стирав УВЕСЬ документ (блокер тест-плану 2026-08-25).
        /// Частковий перетин можливий ЛИШЕ на краях діапазону — пробуємо два
        /// краї замість обходу всього документа (review perf)
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard let tv = textView as? EmbarTextView, let storage = tv.textStorage,
                  storage.length > 0, affectedCharRange.length > 0 else { return true }
            func partiallyCut(_ run: NSRange) -> Bool {
                NSIntersectionRange(run, affectedCharRange).length > 0 &&
                NSUnionRange(run, affectedCharRange) != affectedCharRange
            }
            if let run = tv.atomicRun(at: min(affectedCharRange.location, storage.length - 1)),
               partiallyCut(run) {
                return false
            }
            let lastIdx = min(NSMaxRange(affectedCharRange) - 1, storage.length - 1)
            if lastIdx >= 0, let run = tv.atomicRun(at: lastIdx), partiallyCut(run) {
                return false
            }
            return true
        }
    }
}
