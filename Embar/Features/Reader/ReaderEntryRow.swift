//
//  ReaderEntryRow.swift
//  Embar
//
//  Запис у стрічці блокнота (SPEC §4.3; прототип .reader-entry).
//  Кроки 4–5: думка/цитата + hover-дії (обране, редагування, видалення,
//  «У нотатку»-заглушка). Хештеги — крок 6; хайлайти — крок 9;
//  голосові/фото — кроки 13–14. Видалення миттєве + undo-тост
//  (SPEC §8.2 — інлайн-confirm прототипу свідомо вирівняно).
//

import SwiftUI

struct ReaderEntryRow: View {
    let entry: ReaderEntry
    /// Збереження інлайн-редагування (непорожній текст)
    var onEdit: (String) -> Void = { _ in }
    var onDelete: () -> Void = {}
    var onToggleFav: () -> Void = {}
    /// «У нотатку» (крок 16): 5 останніх нотаток для попапа + вибір
    /// (nil = нова нотатка)
    var recentNotes: [Note] = []
    var onQuote: (Note?) -> Void = { _ in }
    /// Пен-режим: тіло стає selectable, виділення → новий хайлайт
    var penActive: Bool = false
    var onHighlight: (NSRange) -> Void = { _ in }
    /// Обітнути фото запису (2026-07-22): кнопка на ховері фото
    var onCropPhoto: (() -> Void)? = nil
    // Налаштування рідера (SPEC §4.4) — ПАРАМЕТРАМИ від блокнота, не
    // @AppStorage: два спостерігачі UserDefaults на кожен рядок означали
    // тисячі KVO-реєстрацій/знять при скролі стрічки (перф-фікс
    // 2026-08-16, той самий урок, що в StickyCard)
    var hashtagsEnabled = true
    var fontRaw = ReaderBodyFont.inter.rawValue

    /// Фіксовані кольори дій (прототип, НЕ з палітри)
    private static let favPink = Color(hex: "e85a72")
    private static let favPinkHover = Color(hex: "d04258")
    private static let dangerHover = EmbarColors.danger

    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @State private var quoteDestOpen = false
    @FocusState private var editFocused: Bool
    /// Спільний плеєр блокнота (крок 13): другий play зупиняє перший
    @EnvironmentObject private var player: VoicePlayer

    /// Шрифт тіла й цитати — через `Font(nsFont)`, а НЕ `.custom(size:)`.
    /// ❗ .custom масштабується з системним розміром тексту, а NSTextView
    /// (пен-режим/показ хайлайтів) бере фіксований NSFont — тому текст
    /// «стрибав» на інший розмір. Тепер обидва шляхи на ОДНОМУ NSFont —
    /// піксель-у-піксель, завжди однаковий розмір (фідбек 2026-07-13)
    private var bodyFont: Font {
        Font((ReaderBodyFont(rawValue: fontRaw) ?? .inter).nsFont(13.5))
    }
    /// Fraunces italic 14.5 (цитати) — той самий NSFont, що в NSTextView
    private var quoteFont: Font {
        Font(ReaderBodyFont.quoteNSFont())
    }

    /// Кеш декодованого фото (урок обкладинки: NSImage(data:) на кожен
    /// рендер мигає)
    @State private var photoImage: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Колонка часу: 10px, tabular-nums. Ширина залежить від
            // формату системи — 12-годинний «9:26 AM» довший за «14:05».
            // lineLimit тут не косметика, а запобіжник: саме перенос
            // ламав час на «9:26 A» / «M»
            Text(ReaderDateFormat.time(entry.createdAt))
                .font(.emUI(10))
                .monospacedDigit()
                .tracking(0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(EmbarColors.ink4)
                .frame(width: ReaderDateFormat.timeColumnWidth(), alignment: .leading)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 8) {
                // Фото — над тілом (прототип .reader-entry-photo)
                if let image = photoImage { entryPhoto(image) }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Через кеш (2026-07-22): LazyVStack перестворює рядки на кожному
        // скролі/фільтрі, повторний декод JPEG підвішував стрічку.
        // hovering = false: ховер — памʼять рядка, яку LazyVStack
        // воскрешає за id навіть після видалення з даних (пастка F3,
        // SPEC §15.65) — «видалити під курсором → undo» повертало рядок
        // із фантомними іконками дій. Свіжій появі — чистий стан
        .onAppear {
            hovering = false
            photoImage = DecodedImageCache.image(id: entry.id,
                                                 data: entry.photoData)
        }
        .onChange(of: entry.photoData) { _, data in
            photoImage = DecodedImageCache.image(id: entry.id, data: data)
        }
        .padding(.vertical, 9)
        // ❗ overlay ПЕРЕД onHover: ховер має рахуватись і над кнопками
        // дій, інакше наведення на іконку «виходить» з рядка і вона
        // зникає під курсором (фідбек; так само зроблено в NoteCard)
        .overlay(alignment: .bottomTrailing) {
            // ❗ Будуємо ЛИШЕ коли щось справді видно (перф F5.4,
            // 2026-08-28): усі іконки мають opacity 0 і allowsHitTesting
            // false поза ховером, тобто поза ним оверлей — чиста
            // витрата. На 5000 записів це була найдорожча частина рядка
            // (виміряно A/B: 176 з 181 повільних кроків скролу → 120).
            // Серденько обраного видиме без ховера — тому воно в умові;
            // quoteDestOpen тримає попап прикріпленим до своєї іконки.
            // Вигляд не міняється: поява на ховері й так була миттєва
            if !editing, !penActive, hovering || entry.favorite || quoteDestOpen {
                actions
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    /// Живі хайлайти запису в порядку створення (останній виграє)
    /// ❗ Рахувати ОДИН раз на рендер (content бере в local і роздає
    /// параметром): кожен виклик — це доступ до relationship SwiftData +
    /// сортування, а раніше wordView смикав це на КОЖНЕ слово — рядок із
    /// тегами коштував ~15 мс і скрол стрічки на тисячах записів заїдав
    /// (перф-фікс 2026-08-16)
    private var spans: [HighlightSpan] {
        (entry.highlights ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
            .map(HighlightSpan.init)
    }

    /// Фото запису: на ширину, кеп 220pt, cover, radius 10 (прототип)
    private func entryPhoto(_ image: NSImage) -> some View {
        let aspect = image.size.width / max(image.size.height, 1)
        return Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxHeight: 220)
            .background(Image(nsImage: image).resizable().scaledToFill())
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            // Обітнути (2026-07-22) — на ховері рядка, стиль ×-превʼю
            .overlay(alignment: .topTrailing) {
                if hovering, !penActive, !editing, let onCropPhoto {
                    Button(action: onCropPhoto) {
                        Image(systemName: "crop")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.black.opacity(0.55)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
    }

    @ViewBuilder private var content: some View {
        let spans = self.spans
        if entry.kind == .voice {
            // Голосові пером/редагуванням не чіпаються
            voiceBody
        } else if entry.text.isEmpty, !editing {
            // Фото-без-тексту: тіла немає (фото вже вище)
            EmptyView()
        } else if penActive {
            // Raw-текст без декору: індекси виділення 1:1 із Highlight
            ReaderPenTextView(text: entry.text, kind: entry.kind,
                              spans: spans,
                              bodyFont: ReaderBodyFont(rawValue: fontRaw) ?? .inter,
                              onSelect: onHighlight)
        } else if editing {
            editorField
        } else {
            switch entry.kind {
            case .quote: quoteBody(spans)
            default: plainBody(spans) // thought; question/insight отримають стиль у кроці 15
            }
        }
    }

    // MARK: - Голосовий: пігулка з хвилею (SPEC §4.3, крок 13)

    // Як у прототипі .reader-voice-entry: БЕЗ пігулки-фону — голий
    // трикутник play, хвиля на всю ширину, тривалість праворуч
    private var voiceBody: some View {
        let isCurrent = player.currentID == entry.id
        let playing = isCurrent && player.isPlaying
        let progress = isCurrent ? player.progress : 0
        return HStack(spacing: 12) {
            Button {
                if let data = entry.audioData {
                    player.toggle(entry.id, data: data)
                }
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(EmbarColors.ink)
                    .frame(width: 16, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            waveform(progress: progress, playing: playing)
                .frame(maxWidth: .infinity)
            Text(VoiceRecorder.format(entry.audioDuration ?? 0))
                .font(.emUI(11))
                .monospacedDigit()
                .foregroundStyle(EmbarColors.ink3)
        }
    }

    /// Хвиля заповнює доступну ширину (прототип qnFillVoiceBars —
    /// кількість барів від ширини); зіграна частина — чорнилом;
    /// під час гри бари «дихають»; клік/протяжка = сік
    private func waveform(progress: Double, playing: Bool) -> some View {
        GeometryReader { geo in
            let count = max(12, Int(geo.size.width / 4))
            let heights = VoiceWaveform.heights(seed: entry.id, count: count)
            TimelineView(.animation(minimumInterval: 1.0 / 20,
                                    paused: !playing)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<heights.count, id: \.self) { index in
                        let done = Double(index) < progress * Double(count)
                        let dance = playing
                            ? 0.78 + 0.22 * sin(phase * 6 + Double(index) * 0.9)
                            : 1
                        Capsule()
                            .fill(done ? EmbarColors.ink : EmbarColors.ink4)
                            .frame(width: 2, height: heights[index] * dance)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height,
                       alignment: .leading)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { value in
                    guard let data = entry.audioData, geo.size.width > 0
                    else { return }
                    player.seek(entry.id, data: data,
                                fraction: value.location.x / geo.size.width)
                }
            )
        }
        .frame(height: 24)
    }

    // MARK: - Думка: 13.5px, чорнило (сірий .thought — легасі прототипу,
    // видимий дефолт чорний); #теги — справжні капсули інлайн (фідбек):
    // текст із тегами розкладається word-flow, щоб капсула стояла на місці

    /// Чи є серед спанів валідні хайлайти для показу
    private func hasHighlights(_ spans: [HighlightSpan]) -> Bool {
        let length = (entry.text as NSString).length
        return spans.contains { ReaderHighlightRender.isValid($0, length: length) }
    }

    /// Декоративний «?» питання (прототип: серифний курсив 19). Колір —
    /// бренд, а не колишній прибитий вохристий #c97a3a: той був акцентом
    /// однієї палітри й у решті читався випадковою помаранчевою плямою
    /// (ревізія 2026-08-17)
    @ViewBuilder private var questionMark: some View {
        if entry.kind == .question {
            Text("?")
                .font(.emDisplay(19, weight: .semibold, italic: true))
                .foregroundStyle(EmbarColors.brandRed)
        }
    }

    @ViewBuilder private func plainBody(_ spans: [HighlightSpan]) -> some View {
        let matches = hashtagsEnabled ? ReaderTags.matches(in: entry.text) : []
        if matches.isEmpty, !hasHighlights(spans) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                questionMark
                Text(entry.text)
                    .font(bodyFont)
                    .italic(entry.kind == .question)
                    .underline(entry.kind == .insight, color: EmbarColors.ink)
                    .lineSpacing(4)
                    .foregroundStyle(EmbarColors.ink)
            }
        } else if hasHighlights(spans) {
            // Хайлайти/підкреслення → NSTextView-показ: суцільне товсте
            // підкреслення (атрибут через пробіли) + заокруглені заливки,
            // як у прототипі (фідбек 2026-07-13). Теги тут — плейн-текст.
            // ❗ На ВСЮ ширину (як пен-режим): в HStack текст-в'ю не діставав
            // обмеження ширини й довгий текст обрізало замість переносу.
            // Питання при хайлайтах — окремим leading-рядком
            VStack(alignment: .leading, spacing: 3) {
                if entry.kind == .question {
                    HStack(spacing: 7) { questionMark }
                }
                ReaderPenTextView(text: entry.text, kind: entry.kind, spans: spans,
                                  bodyFont: ReaderBodyFont(rawValue: fontRaw) ?? .inter,
                                  selectable: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // Word-flow (варіант Б-1, крок Б): і теги-капсули, і хайлайти
            // з заокругленими кутами — SwiftUI-only, без AppKit-вью.
            // Хайлайт лягає пословно; фони розширені на 2px, тож сусідні
            // слова однієї смуги майже змикаються
            let length = (entry.text as NSString).length
            FlowRow(spacing: 3.5, lineSpacing: 5) {
                questionMark
                ForEach(Array(flowTokens(matches).enumerated()), id: \.offset) { pair in
                    switch pair.element {
                    case .word(let word, let range):
                        wordView(word, range: range, length: length, spans: spans)
                    case .tag(let name):
                        HashtagChip(name: name)
                    }
                }
            }
        }
    }

    /// Слово, поділене по межах хайлайтів: «пів слова» фарбується рівно
    /// до межі (фідбек). Кути заокруглені лише на КРАЯХ смуги — всередині
    /// (і через пробіли) заливка тягнеться без розривів
    @ViewBuilder private func wordView(_ word: String, range: NSRange,
                                       length: Int,
                                       spans: [HighlightSpan]) -> some View {
        if spans.isEmpty {
            // Швидкий шлях (перф 2026-08-16, полегшено F5.4 2026-08-28):
            // без хайлайтів слову не потрібні ні поділ на шматки, ні
            // HStack-обгортка — а це найчастіший випадок стрічки з
            // тегами. Тут же обходимо `.background`-модифікатор
            // pieceText: без заливки він однаково нічого не малює, але
            // SwiftUI будує і розкладає обгортку для КОЖНОГО слова
            plainWord(word)
        } else {
            let pieces = ReaderHighlightRender.wordPieces(word: range,
                                                          length: length,
                                                          spans: spans)
            let ns = entry.text as NSString
            HStack(spacing: 0) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { pair in
                    pieceText(ns.substring(with: pair.element.range),
                              piece: pair.element)
                }
            }
        }
    }

    /// Слово без хайлайту: рівно ті модифікатори, що справді малюють
    private func plainWord(_ string: String) -> some View {
        Text(string)
            .font(entry.kind == .quote ? quoteFont : bodyFont)
            .italic(entry.kind == .question)
            .foregroundStyle(EmbarColors.ink)
            .underline(entry.kind == .insight, color: EmbarColors.ink)
    }

    private func pieceText(_ string: String,
                           piece: ReaderHighlightRender.WordPiece) -> some View {
        let fill = piece.fill.flatMap(HighlightColor.init(rawValue:))
        let stroke = piece.stroke.flatMap(HighlightColor.init(rawValue:))
        let strokeNS = stroke.map { s in
            fill != nil ? s.combinedStrokeNSColor : s.strokeNSColor
        }
        return Text(string)
            .font(entry.kind == .quote ? quoteFont : bodyFont)
            .italic(entry.kind == .question)
            .foregroundStyle(EmbarColors.ink)
            // Хайлайт-лінія має пріоритет; без неї інсайт підкреслюється чорнилом
            .underline(strokeNS != nil || entry.kind == .insight,
                       color: strokeNS.map { Color(nsColor: $0) } ?? EmbarColors.ink)
            .background {
                if let fill {
                    // Кути тільки на краях смуги (.hl radius прототипу);
                    // фон розширений на 2px — містки через пробіли
                    UnevenRoundedRectangle(
                        topLeadingRadius: piece.fillContinuesLeft ? 0 : 3,
                        bottomLeadingRadius: piece.fillContinuesLeft ? 0 : 3,
                        bottomTrailingRadius: piece.fillContinuesRight ? 0 : 3,
                        topTrailingRadius: piece.fillContinuesRight ? 0 : 3)
                        .fill(Color(nsColor: fill.nsColor))
                        .padding(.vertical, -1)
                        .padding(.horizontal, -2)
                }
            }
    }

    private enum FlowToken {
        case word(String, NSRange)
        case tag(String)
    }

    /// Текст → слова (з raw-діапазонами) і теги в порядку появи
    private func flowTokens(_ matches: [ReaderTags.Match]) -> [FlowToken] {
        let ns = entry.text as NSString
        var tokens: [FlowToken] = []
        var cursor = 0
        func pushWords(_ range: NSRange) {
            let segment = ns.substring(with: range) as NSString
            var localStart: Int? = nil
            for offset in 0...segment.length {
                // Розділювачі — лише явні пробіли (сурогатні пари emoji
                // лишаються цілими всередині слова)
                let unit: unichar = offset == segment.length
                    ? 0x20 : segment.character(at: offset)
                let isSpace = unit == 0x20 || unit == 0x0A
                    || unit == 0x09 || unit == 0xA0
                if isSpace {
                    if let start = localStart {
                        let wordRange = NSRange(location: range.location + start,
                                                length: offset - start)
                        tokens.append(.word(ns.substring(with: wordRange), wordRange))
                        localStart = nil
                    }
                } else if localStart == nil {
                    localStart = offset
                }
            }
        }
        for match in matches {
            if match.range.location > cursor {
                pushWords(NSRange(location: cursor, length: match.range.location - cursor))
            }
            tokens.append(.tag(match.name))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            pushWords(NSRange(location: cursor, length: ns.length - cursor))
        }
        return tokens
    }

    // MARK: - Цитата: Fraunces italic 14.5 у лапках + сторінка + автор.
    // Теги вирізаються з тексту і йдуть trailing-чіпами (прототип)

    @ViewBuilder private func quoteBody(_ spans: [HighlightSpan]) -> some View {
        let tags = hashtagsEnabled
            ? ReaderTags.matches(in: entry.text).map(\.name) : []
        VStack(alignment: .leading, spacing: 4) {
            if tags.isEmpty, hasHighlights(spans) {
                // NSTextView-показ: суцільне товсте підкреслення + заокруглені
                // заливки, лапки обгортають текст (фідбек 2026-07-13)
                ReaderPenTextView(text: entry.text, kind: .quote, spans: spans,
                                  selectable: false, quoted: true)
            } else {
                // Прототипний quirk: цитата З тегами — stripped-текст,
                // хайлайти не рендеряться (індекси б з'їхали)
                Text("\u{201C}\(tags.isEmpty ? entry.text : ReaderTags.stripped(entry.text))\u{201D}")
                    .font(quoteFont)
                    .lineSpacing(4)
                    .foregroundStyle(EmbarColors.ink)
            }
            if !tags.isEmpty {
                FlowRow(spacing: 4, lineSpacing: 4) {
                    ForEach(tags, id: \.self) { HashtagChip(name: $0) }
                }
            }
            if let author = entry.author {
                HStack(spacing: 7) {
                    Rectangle().fill(EmbarColors.ink4)
                        .frame(width: 12, height: 1)
                    Text(author)
                        .font(.emUI(10.5))
                        .tracking(0.1)
                        .foregroundStyle(EmbarColors.ink3)
                }
            }
        }
    }

    private func quoteMark(_ mark: String) -> some View {
        Text(mark)
            .font(quoteFont)
            .foregroundStyle(EmbarColors.ink)
    }

    // MARK: - Інлайн-редагування (Enter зберігає, Esc скасовує,
    // порожнє — відкат; лапки цитати на час редагування зникають)

    private var editorField: some View {
        TextField("", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(entry.kind == .quote ? quoteFont : bodyFont)
            .lineSpacing(4)
            .foregroundStyle(entry.kind == .quote ? EmbarColors.ink : EmbarColors.ink2)
            .focused($editFocused)
            .onSubmit(commitEdit)
            .onExitCommand(perform: cancelEdit)
            .onChange(of: editFocused) { _, focused in
                // Клік повз поле — зберегти (прототип: blur = save)
                if !focused && editing { commitEdit() }
                // Фокус прийшов: macOS select-all-ить текст - натомість
                // ставимо курсор за правилом ReaderEditCaret
                if focused && editing {
                    DispatchQueue.main.async {
                        guard let editor = NSApp.keyWindow?
                            .firstResponder as? NSTextView else { return }
                        let location = ReaderEditCaret.location(in: editor.string)
                        editor.selectedRange = NSRange(location: location, length: 0)
                        if location == 0 {
                            // NSTextView, ставши first responder, сам
                            // прокручує до виділення - вирівнюємо на початок
                            editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
                        }
                    }
                }
            }
            // Панель сховалась під час редагування — зберегти як blur
            .onReceive(NotificationCenter.default.publisher(
                for: .embarPanelDidHide)) { _ in
                editFocused = false
            }
    }

    /// «У нотатку»: жирна «+ Нова нотатка» + 5 останніх (прототип
    /// quote-dest-pop; анатомія — як FolderPickerList)
    private var quoteDestList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("У нотатку")
                .font(.emUI(10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(EmbarColors.ink3)
                .padding(.horizontal, 8)
                .padding(.bottom, 3)
            destOption(label: String(localized: "+ Нова нотатка", comment: "Опція у попапі «У нотатку» — створити нову"), emphasized: true) {
                pickDestination(nil)
            }
            if !recentNotes.isEmpty {
                Rectangle().fill(.black.opacity(0.06)).frame(height: 1)
                    .padding(.vertical, 3)
                ForEach(recentNotes) { note in
                    destOption(label: note.title.isEmpty ? "Без назви" : note.title) {
                        pickDestination(note)
                    }
                }
            }
        }
        .padding(8)
        .frame(minWidth: 190)
    }

    private func destOption(label: String, emphasized: Bool = false,
                            select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack {
                Text(label.truncatedChip(24))
                    .font(.emUI(12, weight: emphasized ? .medium : .regular))
                    .foregroundStyle(emphasized ? EmbarColors.ink : EmbarColors.ink2)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pickDestination(_ note: Note?) {
        quoteDestOpen = false
        onQuote(note)
    }

    private func startEdit() {
        draft = entry.text
        editing = true
        editFocused = true
    }

    private func commitEdit() {
        guard editing else { return }
        editing = false
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Порожнє — відкат до попереднього тексту (SPEC §4.3)
        if !trimmed.isEmpty, trimmed != entry.text { onEdit(trimmed) }
    }

    private func cancelEdit() {
        editing = false
    }

    // MARK: - Hover-дії: [У нотатку][ред.][видалити][обране]
    // Іконки 0 → 0.5 на ховері рядка → 1 + scale на ховері іконки;
    // активне серденько видиме завжди (прототип .is-active)

    private var actions: some View {
        HStack(spacing: 9) {
            // Голосові: без «У нотатку» і редагування (прототип
            // renderReaderEntryActions withQuote=false)
            if entry.kind != .voice {
                EntryActionIcon(icon: "doc.text",
                                visible: hovering || quoteDestOpen,
                                action: { quoteDestOpen = true })
                    .help("У нотатку")
                    // Попап призначення (прототип quote-dest-pop) —
                    // нативний popover, як пікер папок (консистентність)
                    .popover(isPresented: $quoteDestOpen, arrowEdge: .bottom) {
                        quoteDestList
                    }
                EntryActionIcon(icon: "pencil", visible: hovering,
                                action: startEdit)
                    .help("Редагувати")
            }
            EntryActionIcon(icon: "trash", visible: hovering,
                            hoverTint: Self.dangerHover, action: onDelete)
                .help("Видалити")
            EntryActionIcon(icon: entry.favorite ? "heart.fill" : "heart",
                            visible: hovering || entry.favorite,
                            baseTint: entry.favorite ? Self.favPink : nil,
                            hoverTint: entry.favorite ? Self.favPinkHover : nil,
                            baseOpacity: entry.favorite ? 0.9 : 0.5,
                            action: onToggleFav)
                .help(entry.favorite ? "Прибрати з обраних" : "Додати в обрані")
        }
        .padding(.bottom, 7)
        .padding(.trailing, 10)
    }
}

// MARK: - Іконка дії (прототип .reader-entry-action-icon)

private struct EntryActionIcon: View {
    let icon: String
    let visible: Bool
    var baseTint: Color? = nil
    var hoverTint: Color? = nil
    var baseOpacity: Double = 0.5
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5))
                .foregroundStyle(hovering ? (hoverTint ?? EmbarColors.ink)
                                          : (baseTint ?? EmbarColors.ink2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? (hovering ? 1 : baseOpacity) : 0)
        .scaleEffect(hovering ? 1.15 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .allowsHitTesting(visible)
        .onHover { hovering = $0 }
    }
}

// MARK: - Пігулка тега «#ідея» (прототип .reader-hashtag)

struct HashtagChip: View {
    let name: String
    /// Кольори капсули йдуть за активною палітрою (P2.25);
    /// зміна палітри перемальовує чіпи миттєво (§7.2-A)
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        let capsule = ReaderTags.capsule(for: name, palette: theme.current)
        Text("#\(name)")
            .font(.emUI(11))
            .foregroundStyle(capsule.fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(capsule.bg))
            .fixedSize()
    }
}


// MARK: - Дата-роздільник «сьогодні / вчора / 5 лип»

/// Розділювач теми в стрічці (макет 2026-07-22): назва ПО ЦЕНТРУ між
/// двома тонкими лініями, маленький трикутник ▾ зліва. Трикутник — як у
/// спадного меню: клік згортає записи ЦІЄЇ теми, подвійний — усіх тем
/// блокнота (ExclusiveGesture: одинарний чекає, поки подвійний не
/// провалиться, — інакше клікались би обидва). Клік по назві —
/// ПРОДОВЖИТИ тему (знову активна, нові записи йдуть у неї; повторний
/// клік або чип «Тема» зупиняє — фідбек 2026-07-28); подвійний клік —
/// інлайн-перейменування
struct ReaderThemeDivider: View {
    let name: String
    var collapsed = false
    /// Стоїть одразу під дата-рядком — без верхнього повітря
    var tight = false
    /// Слідує шрифту блокнота (фідбек 2026-07-22); Inter лишає Fraunces
    var font: Font = .emDisplay(15, italic: true)
    var onToggle: () -> Void = {}
    var onToggleAll: () -> Void = {}
    var onRename: (String) -> Void = { _ in }
    /// Клік по назві: продовжити/зупинити це русло
    var onActivate: () -> Void = {}

    /// Тонка лінія обабіч назви (тон макета — теплий блідий hairline)
    static let lineTint = Color.black.opacity(0.14)

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var editFocus: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 7))
                .foregroundStyle(EmbarColors.ink3)
                .rotationEffect(.degrees(collapsed ? -90 : 0))
                .animation(.easeOut(duration: 0.15), value: collapsed)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .gesture(TapGesture(count: 2).onEnded { onToggleAll() }
                    .exclusively(before: TapGesture().onEnded { onToggle() }))
            Rectangle().fill(Self.lineTint).frame(height: 1)
            if editing {
                ThemeNameField(text: $draft, font: font, focus: $editFocus,
                               onCommit: commitRename,
                               onCancel: { editing = false })
                    // Той самий трюк, що в чернетці: фокус на наступному
                    // тіку, коли поле вже існує
                    .onAppear { DispatchQueue.main.async { editFocus = true } }
                    .onChange(of: editFocus) { _, focused in
                        if !focused, editing { commitRename() }
                    }
            } else {
                Text(name)
                    .font(font)
                    .foregroundStyle(EmbarColors.ink)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .contentShape(Rectangle())
                    .gesture(TapGesture(count: 2).onEnded {
                        draft = name
                        editing = true
                    }.exclusively(before: TapGesture().onEnded { onActivate() }))
            }
            Rectangle().fill(Self.lineTint).frame(height: 1)
        }
        .padding(.top, tight ? 6 : 18)
        .padding(.bottom, 12)
    }

    private func commitRename() {
        guard editing else { return }
        editing = false
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != name { onRename(trimmed) }
    }
}

/// Поле назви теми по центру між лініями — ФІКСОВАНІ 200pt: довша
/// назва прокручується вбік у полі, а не розпирає розділювач за краї.
/// ❗ Без динамічної ширини і структурних if навколо поля: зміна
/// розміру/структури активного NSTextField на кожній букві скидала
/// редагування — чернетка закривалась після першої ж літери
/// (баг, фідбек 2026-07-22)
struct ThemeNameField: View {
    @Binding var text: String
    var font: Font
    var focus: FocusState<Bool>.Binding
    var onCommit: () -> Void
    var onCancel: () -> Void

    /// Плейсхолдер — як у стіках: 14pt, єдиний тон (консистентність,
    /// фінал 2026-07-22). ❗ Власним Text-ом за полем, НЕ через prompt:
    /// macOS ігнорує .font у prompt
    private static let promptTint = EmbarColors.placeholder

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(EmbarColors.ink)
            .multilineTextAlignment(.center)
            .focused(focus)
            .onSubmit(onCommit)
            .onExitCommand(perform: onCancel)
            .background {
                Text("Назва теми…")
                    .font(.emDisplay(14, italic: true))
                    .foregroundStyle(Self.promptTint)
                    .opacity(text.isEmpty ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .frame(width: 200)
    }
}

struct ReaderDayDivider: View {
    let label: String
    var isFirst = false

    var body: some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(.emUI(10, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(EmbarColors.ink4)
            Rectangle().fill(.black.opacity(0.08)).frame(height: 1)
        }
        .padding(.top, isFirst ? 0 : 14)
        .padding(.bottom, 8)
    }
}

// MARK: - Курсор при відкритті інлайн-редактора

/// Куди ставити курсор, коли запис відкривають на редагування.
///
/// Прототип ставить у КІНЕЦЬ - аби macOS не виділяв весь текст. Але
/// NSTextView, ставши first responder, прокручує стрічку до виділення:
/// на багаторядковому записі це кидало список аж у його низ, і виглядало
/// як «заїдає і гортається далі вниз» (баг 2026-08-09). Тому такий запис
/// відкриваємо з ПОЧАТКУ - людина бачить те, що редагує.
enum ReaderEditCaret {
    static func location(in text: String) -> Int {
        let ns = text as NSString
        let multiline = ns.range(of: "\n").location != NSNotFound
        return multiline ? 0 : ns.length
    }
}
