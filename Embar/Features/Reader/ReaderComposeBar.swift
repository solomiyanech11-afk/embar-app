//
//  ReaderComposeBar.swift
//  Embar
//
//  Композер блокнота (SPEC §4.2; прототип .reader-compose). Докований
//  знизу (SPEC «Compose знизу» — вирішена розбіжність із прототипом,
//  де він угорі скролу). Тогл Думка/Цитата, автор (сторінки прибрано
//  2026-07-21 — рішення «теми замість сторінок»), текст + send. Перо (крок 9), фото (14), мікрофон (11–12) — заглушки.
//

import SwiftUI

extension Notification.Name {
    /// Стрічка просить фокус у compose (Enter у назві теми — клавіатура
    /// одразу повертається до думки; фідбек 2026-07-22)
    static let embarReaderFocusCompose = Notification.Name("embarReaderFocusCompose")
}

struct ReaderComposeBar: View {
    /// (тип, текст, автор, фото). Валідний або непорожній
    /// текст, або фото без тексту (SPEC §8.3)
    let onSubmit: (ReaderEntryKind, String, String?, Data?) -> Void
    // Пен-режим хайлайтів (SPEC §4.2): стан живе в блокноті —
    // рядкам записів треба знати режим/колір при виділенні
    @Binding var penActive: Bool
    @Binding var penMode: String
    @Binding var penColor: String
    /// Чи брати фокус на показі панелі (false — зверху sheet/пошук;
    /// code review M5 #6)
    var shouldAutoFocus: () -> Bool = { true }
    // Теми (2026-07-22, інлайн-розділювачі): чип — простий тогл, без
    // попапів; ввід назви живе у стрічці блокнота
    /// Назва активної теми блокнота (nil — загальний потік)
    var activeThemeName: String? = nil
    /// true — у стрічці відкрито ввід назви нової теми
    var themeDrafting: Bool = false
    /// Тогл: нема активної → почати ввід назви; є → завершити;
    /// чернетка відкрита → скасувати
    var onThemeToggle: () -> Void = {}
    /// Кроп фото-превʼю (2026-07-22): блокнот показує шит кропа і
    /// повертає обрізане через замикання
    var onCropPhoto: (NSImage, @escaping (NSImage) -> Void) -> Void = { _, _ in }
    /// P2.26: реєстрація відкату в undo-стеку блокнота (⌘Z). Композер
    /// власного стека не має - кроп превʼю відкочується тим самим
    /// механізмом, що дії над записами
    var onRegisterUndo: (ReaderUndoLabel, @escaping () -> Void) -> Void = { _, _ in }
    /// Готовий голосовий запис (крок 12): (аудіо, тривалість у секундах)
    var onVoice: (Data, Double) -> Void = { _, _ in }

    // Налаштування рідера (SPEC §4.4)
    @AppStorage("readerExtraTypes") private var extraTypes = false
    @AppStorage("readerFont") private var fontRaw = ReaderBodyFont.inter.rawValue

    @State private var kind: ReaderEntryKind = .thought
    @State private var text = ""
    @State private var author = ""
    /// Фото до відправки: дані + декодоване один раз зображення
    /// (кеш проти мигання — урок обкладинки)
    @State private var pendingPhoto: (data: Data, image: NSImage)?
    @FocusState private var textFocused: Bool
    @StateObject private var recorder = VoiceRecorder()

    var body: some View {
        VStack(spacing: 0) {
            if recorder.permissionDenied {
                micDeniedRow
            } else if recorder.isRecording {
                recordingRow
            } else if penActive {
                penRow
            } else {
                topRow
            }
            Rectangle().fill(.black.opacity(0.07)).frame(height: 1)
                .padding(.horizontal, 10)
            if let photo = pendingPhoto { photoPreview(photo.image) }
            textRow
            if kind == .quote { authorRow }
        }
        .onDisappear { recorder.cancel() } // закрили блокнот під час запису
        // Левітуюча скляна поверхня (2026-07-21) — те саме скло, що поле
        // стіків; записи проступають крізь нього розмито
        .background(ComposerGlassBackdrop(cornerRadius: 12, milk: 0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Біліше скло + соковитіша тінь (фідбек 2026-07-21: зливалось
        // із фоном панелі)
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        // Кореневий фікс фокуса (2026-07-07): PanelController шле
        // did-show/did-hide — показ панелі кладе курсор СЮДИ (останній
        // вибраний тип), ховання скидає SwiftUI-стан фокуса
        .onReceive(NotificationCenter.default.publisher(
            for: .embarPanelDidShow)) { _ in
            if shouldAutoFocus() { textFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .embarPanelDidHide)) { _ in
            textFocused = false
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .embarReaderFocusCompose)) { _ in
            // Той самий запобіжник, що на показі панелі (code review
            // 2026-07-23): відкритий пошук по блокноту НЕ віддає
            // клавіатуру compose — букви летіли б у чернетку запису
            if shouldAutoFocus() { textFocused = true }
        }
        // Вимкнули додаткові типи в налаштуваннях — вибраний Питання/
        // Інсайт одразу повертається в Думку. ❗ На стабільному контейнері:
        // раніше висів на typeToggle, який при перемиканні extraTypes
        // перебудовується (їде на інший рядок) — onChange губився і
        // старий тип лишався (баг, фідбек 2026-07-22)
        .onChange(of: extraTypes) { _, enabled in
            if !enabled, kind == .question || kind == .insight {
                kind = .thought
            }
        }
    }

    // MARK: - Верхній ряд: перо · фото · мікрофон · тип

    private var topRow: some View {
        // З додатковими типами 4 чіпи не вміщаються поруч з іконками —
        // тогл і тема їдуть на другий рядок (фідбек 2026-07-07)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                // Олівець із рискою — прототипний .compose-pen-toggle
                ComposeIconButton(icon: "pencil.line") { penActive = true }
                ComposeIconButton(icon: "camera") {
                    // Той самий сендбокс-механізм, що фото нотаток (M4)
                    NoteImageStore.pickImages(count: 1) { urls in
                        guard let url = urls.first,
                              let image = NSImage(contentsOf: url),
                              let data = NoteImageStore.downscaledJPEG(image)
                        else { return }
                        pendingPhoto = (data, NSImage(data: data) ?? image)
                    }
                }
                ComposeIconButton(icon: "mic") {
                    // Режим читання: блок на СТАРТІ запису - щоб людина
                    // не наговорила аудіо, яке потім не збережеться
                    guard ProGate.allowCreate() else { return }
                    recorder.start() // лінивий системний запит при першому тапі
                }
                if !extraTypes {
                    typeToggle
                    Spacer(minLength: 0)
                    themeChip
                } else {
                    Spacer(minLength: 0)
                }
            }
            if extraTypes {
                HStack(spacing: 8) {
                    typeToggle
                    Spacer(minLength: 0)
                    themeChip
                }
            }
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 4, trailing: 10))
    }

    // MARK: - Тема (2026-07-22): тогл. Створюю (ввід назви у стрічці) →
    // активна, все нове пишеться під неї; повторний клік завершує —
    // нові записи знову в загальний потік

    private var themeChip: some View {
        let engaged = activeThemeName != nil || themeDrafting
        return Button(action: onThemeToggle) {
            HStack(spacing: 4) {
                Image(systemName: "bookmark")
                    .font(.system(size: 9))
                // 8 символів, не дефолт: довша назва видавлювала тогл
                // «Думка/Цитата» на два рядки (фідбек 2026-07-22)
                Text(activeThemeName?.truncatedChip(8) ?? String(localized: "Тема", comment: "Кнопка початку нової теми в композері рідера"))
                    .font(.emUI(10.5, weight: engaged ? .medium : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(engaged ? .white : EmbarColors.ink2)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(
                engaged ? EmbarColors.ink : Color.black.opacity(0.04)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Запис (прототип .compose-recording-state): червона
    // пульсуюча крапка · таймер · стоп; решта контролів схована

    /// Крапка й таймер запису = той самий функціональний червоний.
    /// ❗ Ревізія 2026-08-17: тут жив власний #dc2626 — сьомий червоний
    /// у продукті (та ще й RecordingDot дублював літерал замість цієї
    /// константи). Роль «щось активно пишеться» лишилась, значення —
    /// спільне; правити тільки в EmbarColors.danger
    private static let recordingRed = EmbarColors.danger

    private var recordingRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                RecordingDot()
                Text(VoiceRecorder.format(recorder.elapsed))
                    .font(.emUI(11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Self.recordingRed)
                Button(action: finishRecording) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Self.recordingRed))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Зупинити")
            }
            .padding(EdgeInsets(top: 4, leading: 11, bottom: 4, trailing: 5))
            .background(Capsule().fill(Self.recordingRed.opacity(0.08)))
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 4, trailing: 10))
    }

    private func finishRecording() {
        guard let voice = recorder.finish() else { return }
        onVoice(voice.data, voice.duration)
    }

    /// Відмова доступу → мʼяке пояснення + лінк на System Settings
    /// (SPEC §8.3: нативно, не alert)
    private var micDeniedRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.slash")
                .font(.system(size: 11))
                .foregroundStyle(EmbarColors.ink3)
            Text("Embar не має доступу до мікрофона")
                .font(.emUI(11))
                .foregroundStyle(EmbarColors.ink2)
                .lineLimit(1)
            Button("Відкрити налаштування") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.emUI(11, weight: .medium))
            .foregroundStyle(EmbarColors.ink)
            Spacer(minLength: 0)
            ComposeIconButton(icon: "xmark", size: 10) {
                recorder.permissionDenied = false
            }
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 8))
    }

    // MARK: - Пен-рядок: × · режим · 4 фіксовані кольори (SPEC §4.2;
    // кольори НЕ з палітри — HighlightColor)

    // Вигляд 1:1 з прототипом (фідбек 2026-07-07): тонкий олівець як
    // іконка маркера, активний режим — біла іконка в чорному колі,
    // свотчі 18px, активний — чорне кільце із зазором, «×» більший
    private var penRow: some View {
        HStack(spacing: 11) {
            ComposeIconButton(icon: "xmark", size: 11.5) { penActive = false }
            penModeButton("highlighter", mode: "highlight")
            penModeButton("underline", mode: "underline")
            Rectangle().fill(.black.opacity(0.08))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 1)
            ForEach(HighlightColor.allCases, id: \.rawValue) { color in
                penSwatch(color)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 5, trailing: 10))
    }

    private func penModeButton(_ icon: String, mode: String) -> some View {
        let active = penMode == mode
        return Button {
            penMode = mode
        } label: {
            Image(systemName: icon)
                // Лінійна вага — прототипний stroke-маркер, не заливка
                .font(.system(size: 12.5, weight: .light))
                .foregroundStyle(active ? .white : EmbarColors.ink2)
                .frame(width: 27, height: 27)
                .background(Circle().fill(active ? EmbarColors.ink : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func penSwatch(_ color: HighlightColor) -> some View {
        let active = penColor == color.rawValue
        return Button {
            penColor = color.rawValue
        } label: {
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .frame(width: 21, height: 21)
                .overlay {
                    if active {
                        // Тонке чорне кільце впритул до кольору
                        Circle().stroke(EmbarColors.ink, lineWidth: 1.4)
                            .padding(-2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var typeToggle: some View {
        HStack(spacing: 2) {
            typeButton("Думка", .thought)
            typeButton("Цитата", .quote)
            if extraTypes { // SPEC §4.4: додаткові типи
                typeButton("Питання", .question)
                typeButton("Інсайт", .insight)
            }
        }
        .padding(2)
        .background(Capsule().fill(.black.opacity(0.05)))
        // Тогл типів не стискається — чипи ніколи не переносяться
        // на два рядки (фідбек 2026-07-22)
        .fixedSize()
    }

    private func typeButton(_ label: LocalizedStringKey, _ value: ReaderEntryKind) -> some View {
        let active = kind == value
        return Button {
            kind = value // перемикання типу — миттєве (§7.2-A)
        } label: {
            Text(label)
                // Кнопки типів — теж обраним шрифтом (фідбек)
                .font((ReaderBodyFont(rawValue: fontRaw) ?? .inter)
                    .font(10.5, weight: .medium))
                .foregroundStyle(active ? EmbarColors.ink : EmbarColors.ink3)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    if active {
                        Capsule().fill(.white)
                            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Плейсхолдер — як у стіках: 14pt, єдиний тон EmbarColors.placeholder
    /// (консистентність, фінал 2026-07-22). ❗ Малюється власним Text-ом
    /// за полем, НЕ через prompt: macOS ігнорує .font у prompt
    private static let placeholderTint = EmbarColors.placeholder

    // MARK: - Текст + send

    private var placeholder: String {
        switch kind {
        case .quote: String(localized: "Що цікавого з джерела…", comment: "Плейсхолдер композера рідера — цитата")
        case .question: String(localized: "Що зачепило, що незрозуміло…", comment: "Плейсхолдер композера рідера — питання")
        case .insight: String(localized: "Інсайт або висновок…", comment: "Плейсхолдер композера рідера — інсайт")
        default: String(localized: "Що думаєш…", comment: "Плейсхолдер композера рідера — думка")
        }
    }

    private var textRow: some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextField("", text: $text, axis: .vertical)
                // Власний плейсхолдер — менший і ледь видимий.
                // opacity, НЕ if: структурна зміна на першій букві
                // може скинути редагування (урок поля назви теми)
                .background(alignment: .leading) {
                    Text(placeholder)
                        .font(kind == .quote
                              ? .emDisplay(14, italic: true)
                              : (ReaderBodyFont(rawValue: fontRaw) ?? .inter).font(14))
                        .foregroundStyle(Self.placeholderTint)
                        .opacity(text.isEmpty ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .textFieldStyle(.plain)
                // Цитата пишеться серифом-курсивом уже в композері;
                // решта — обраним шрифтом записів (SPEC §4.4).
                // 13, не 13.5 — поле вводу легше за текст стрічки (фідбек)
                .font(kind == .quote
                      ? .emDisplay(13, italic: true)
                      : (ReaderBodyFont(rawValue: fontRaw) ?? .inter).font(13))
                .foregroundStyle(EmbarColors.ink)
                .lineLimit(1...6)
                .lineSpacing(4)
                // Однорядковий текст — по центру висоти ряду (фідбек);
                // при рості поле розсуває frame і send лишається знизу
                .frame(minHeight: 26, alignment: .leading)
                .focused($textFocused)
                .onSubmit(submit)
            SendButton(action: submit)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 8))
    }

    private var authorRow: some View {
        TextField("", text: $author)
            .background(alignment: .leading) {
                // Виняток з 14pt-правила плейсхолдерів: підрядок автора —
                // другорядне поле, 10px (фідбек 2026-07-22)
                Text("- чия цитата (опційно)")
                    .font(.emUI(10).italic())
                    .foregroundStyle(Self.placeholderTint)
                    .opacity(author.isEmpty ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .textFieldStyle(.plain)
            .font(.emUI(12).italic())
            .foregroundStyle(EmbarColors.ink3)
            .padding(EdgeInsets(top: 0, leading: 12, bottom: 9, trailing: 12))
            .onSubmit(submit)
    }

    /// Превʼю фото (прототип .compose-photo-preview): до 140pt, radius 10,
    /// × у правому верхньому куті прибирає
    private func photoPreview(_ image: NSImage) -> some View {
        let aspect = image.size.width / max(image.size.height, 1)
        return Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxHeight: 140)
            .background(Image(nsImage: image).resizable().scaledToFill())
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    // Обітнути до відправки (2026-07-22) — той самий
                    // шит кропа, що фото нотаток
                    Button {
                        onCropPhoto(image) { cropped in
                            guard let data = NoteImageStore.downscaledJPEG(cropped)
                            else { return }
                            // P2.26: ⌘Z повертає превʼю ДО цього кропу
                            // (оригінал не втрачається)
                            let previous = pendingPhoto
                            pendingPhoto = (data, NSImage(data: data) ?? cropped)
                            onRegisterUndo(.cropPhoto) { pendingPhoto = previous }
                        }
                    } label: {
                        Image(systemName: "crop")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.black.opacity(0.55)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        pendingPhoto = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.black.opacity(0.55)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12))
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Запис лише з фото (без тексту) — валідний (SPEC §8.3)
        guard !trimmed.isEmpty || pendingPhoto != nil else { return }
        // Режим читання: відмова ДО очищення - текст/фото лишаються в полі
        guard ProGate.allowCreate() else { return }
        onSubmit(kind, trimmed,
                 author.isEmpty ? nil : author,
                 pendingPhoto?.data)
        text = ""
        author = ""
        pendingPhoto = nil
        textFocused = true // фокус лишається — наступна думка одразу
    }
}

// MARK: - Пульсуюча крапка запису (прототип recordingPulse 1.2s)

private struct RecordingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(EmbarColors.danger)
            .frame(width: 8, height: 8)
            .opacity(pulsing ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                       value: pulsing)
            .onAppear { pulsing = true }
    }
}

// MARK: - Кругла іконка-кнопка ряду (26px, прототип .compose-*-toggle)

private struct ComposeIconButton: View {
    let icon: String
    var size: CGFloat = 12.5
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(hovering ? EmbarColors.ink : EmbarColors.ink2)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.black.opacity(hovering ? 0.06 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Send (26px чорне коло, hover scale 1.1)

private struct SendButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(EmbarColors.ink))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.1 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
    }
}
