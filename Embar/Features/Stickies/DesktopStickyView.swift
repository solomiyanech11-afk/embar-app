//
//  DesktopStickyView.swift
//  Embar
//
//  SwiftUI-корінь стіка-віджета на робочому столі (SPEC §2.7).
//  Скло — та сама VEV-конструкція, що в композерів (ComposerGlass):
//  blur + прибитий .state = .active + світлий кант; замість білого
//  молока — тінт кольору стіка ~0.72. Blur тут behindWindow: віджет
//  лежить просто на шпалерах, розмивати треба те, що ПОЗАДУ вікна.
//
//  Це ДРУГЕ відображення того самого Sticker з mainContext — редагування
//  і done видно в панелі миттєво (Observable @Model), і навпаки.
//

import SwiftUI
import SwiftData
import AppKit

/// VEV-скло для окремого вікна на столі: та сама SaturatedGlassView
/// (буст насичення + гашення «молока» матеріалу), але behindWindow
struct BehindWindowGlass: NSViewRepresentable {
    var cornerRadius: CGFloat = 12

    func makeNSView(context: Context) -> SaturatedGlassView {
        let view = SaturatedGlassView()
        view.blendingMode = .behindWindow
        view.state = .active   // вікно nonactivating — без цього матеріал сірий
        view.material = .menu
        view.saturationBoost = 1.5      // калібр композерів (GlassLab 2026-07-20)
        view.stripsTint = true          // біле молоко замінює тінт кольору стіка
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: SaturatedGlassView, context: Context) {
        view.layer?.cornerRadius = cornerRadius
    }
}

/// ЄДИНЕ джерело стильових токенів віджета (знахідка 10 code review):
/// вʼюха стіка і його попап налаштувань зобовʼязані виглядати ідентично —
/// ефективний стиль, колір з палітри і чорнила рахуються ТУТ, не руками
/// в кожному файлі
struct WidgetStyleTokens {
    /// Ефективний стиль: спадковий "liquid" тихо рендериться як color
    let style: String
    /// Колір стіка з активної палітри (тінт стилю "color")
    let color: Color

    init(sticker: Sticker, paletteSlug: String,
         colorMode: String, noWallSlot: Int) {
        style = sticker.floatStyle == "liquid" ? "color" : sticker.floatStyle
        let palette = Palette.bySlug(paletteSlug)
        let idx = StickyColorMode.effectiveIndex(
            for: sticker, byWall: colorMode == "byWall", noWallSlot: noWallSlot)
        color = palette.sticky[min(idx, palette.sticky.count - 1)]
    }

    var isDark: Bool { style == "dark" }
    /// Темне скло — світлі чорнила; решта — адаптивні чорнила стіків,
    /// добрані під колір саме цього віджета (SPEC §15.57)
    var ink: Color { isDark ? .white.opacity(0.92) : StickyInk.on(color).ink }
    var ink2: Color { isDark ? .white.opacity(0.62) : StickyInk.on(color).ink2 }
    var ink3: Color { isDark ? .white.opacity(0.45) : StickyInk.on(color).ink3 }
}

/// Скло віджета за стилем — ОДНЕ джерело для самого стіка і його попапа
/// налаштувань (попап «належить» стіку і вдягнений так само, фідбек
/// 2026-07-30). style — вже effective: "color" | "dark" | "light"
struct DesktopStickyBackdrop: View {
    let style: String
    /// Колір стіка з палітри (тінт стилю "color")
    let color: Color
    var cornerRadius: CGFloat = 12

    /// Насиченість тінта стилю "color" — одна точка калібрування.
    /// 0.88 — вибір користувача з WidgetTintLab (2026-07-30): колір
    /// упізнається з першого погляду, скло ще відчутне
    static let colorTintAlpha: Double = 0.88

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius).fill(opaqueFill)
        } else {
            switch style {
            case "dark":
                glassBase(tint: .black.opacity(0.38), rimTop: 0.28, rimBottom: 0.12)
            case "light":
                glassBase(tint: .white.opacity(0.32), rimTop: 0.75, rimBottom: 0.4)
            default:
                glassBase(tint: color.opacity(Self.colorTintAlpha),
                          rimTop: 0.75, rimBottom: 0.4)
            }
        }
    }

    private var opaqueFill: Color {
        switch style {
        case "dark": Color(hex: "2e2c29")
        case "light": Color(hex: "fcfbf9")
        default: color
        }
    }

    /// VEV + тінт + кант композерів (зверху яскравіший, донизу мʼякший)
    private func glassBase(tint: Color, rimTop: Double,
                           rimBottom: Double) -> some View {
        ZStack {
            BehindWindowGlass(cornerRadius: cornerRadius)
            RoundedRectangle(cornerRadius: cornerRadius).fill(tint)
        }
        .overlay(RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(LinearGradient(
                colors: [.white.opacity(rimTop), .white.opacity(rimBottom)],
                startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// Ідеальна (без переносу) ширина тексту — авто-ширина «обіймає» короткий
/// текст (2026-07-30), довший розсуває вікно до maxWidth, далі перенос
private struct WidgetIdealWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Виміри розкладки тексту (рефактор 2026-07-30, SPEC §2.7):
/// ЄДИНЕ джерело правди про «скільки простору хоче текст». Всі поля —
/// з незалежних прихованих probe (не з видимого, можливо обрізаного,
/// тексту — самопосилання і було коренем класу багів «…-над-порожнечею»).
/// max-reduce дозволяє кільком probe писати різні поля одним ключем.
struct WidgetTextMetrics: Equatable {
    /// Природна висота тексту при ПОТОЧНІЙ ширині, без жодних обрізань.
    /// Під час редагування піднімається і виміром живих полів (fixedSize —
    /// вони ніколи не обрізані, max згладжує різницю метрик Text/TextField)
    var naturalTextHeight: CGFloat = 0
    var headerHeight: CGFloat = 0
    /// Висота ОДНОГО рядка (виміряна, не коефіцієнт) — для кепа скролу
    /// редактора при максимальній висоті вікна
    var titleLineHeight: CGFloat = 0
    var bodyLineHeight: CGFloat = 0
}

private struct WidgetTextMetricsKey: PreferenceKey {
    static var defaultValue = WidgetTextMetrics()
    static func reduce(value: inout WidgetTextMetrics,
                       nextValue: () -> WidgetTextMetrics) {
        let next = nextValue()
        value.naturalTextHeight = max(value.naturalTextHeight, next.naturalTextHeight)
        value.headerHeight = max(value.headerHeight, next.headerHeight)
        value.titleLineHeight = max(value.titleLineHeight, next.titleLineHeight)
        value.bodyLineHeight = max(value.bodyLineHeight, next.bodyLineHeight)
    }
}

struct DesktopStickyView: View {
    @Bindable var sticker: Sticker
    /// Контролер вікна слухає природну висоту (авто-розмір під текст)
    var onContentHeight: (CGFloat) -> Void = { _ in }
    /// …і ідеальну ширину тексту без переносу (авто-ширина)
    var onContentIdealWidth: (CGFloat) -> Void = { _ in }
    /// Зробити вікно key перед редагуванням: клік по статичному тексту
    /// в nonactivating-панелі key її не робить — поле не прийме клавіатуру
    var onRequestKey: () -> Void = {}
    /// ⋯ — попап налаштувань віджета (стиль/розмір тексту), живе в контролері
    var onOpenSettings: () -> Void = {}

    @State private var hovering = false
    @State private var editingTitle = false
    @State private var editingBody = false
    /// Знімок тексту на вході в редагування: updatedAt бампається лише
    /// при реальній зміні (ревʼю 2026-07-30, Д1 — без чурну для синку)
    @State private var editSnapshotTitle = ""
    @State private var editSnapshotBody = ""
    /// «Виконано» на віджеті: викреслення → fade ~2.4с → зняття зі столу.
    /// Повторний ✓ під час fade скасовує (undo done, opacity назад)
    @State private var fadeOpacity: Double = 1
    @State private var fadeOutTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?
    private enum Field { case title, body }

    // Ті самі ключі, що на стіні: зміна палітри/режиму кольору в програмі
    // перефарбовує віджети наживо (AppStorage сам тригерить ре-рендер)
    @AppStorage("palette") private var paletteSlug = Palette.defaultSlug
    @AppStorage("wallColorMode") private var colorMode = "random"
    @AppStorage("noWallColorSlot") private var noWallSlot = 0

    private static let cornerRadius: CGFloat = 12

    private var showBody: Bool {
        sticker.floatDisplayMode == "full" && (!sticker.bodyText.isEmpty || editingBody)
    }

    // MARK: - Стиль (SPEC §2.7) — усе зі спільних WidgetStyleTokens

    private var tokens: WidgetStyleTokens {
        WidgetStyleTokens(sticker: sticker, paletteSlug: paletteSlug,
                          colorMode: colorMode, noWallSlot: noWallSlot)
    }
    private var effectiveStyle: String { tokens.style }
    private var color: Color { tokens.color }
    private var ink: Color { tokens.ink }
    private var ink2: Color { tokens.ink2 }
    private var titleFontSize: CGFloat {
        switch sticker.floatTextSize {
        case "s": 12
        case "l": 17
        default: 14
        }
    }
    private var bodyFontSize: CGFloat {
        switch sticker.floatTextSize {
        case "s": 10
        case "l": 13.5
        default: 11.5
        }
    }

    /// Живі виміри розкладки (probe нижче). ЖОДНИХ статичних бюджетів
    /// рядків: обрізання показу — виключно від фактичної геометрії вікна
    @State private var metrics = WidgetTextMetrics()

    /// Кеп рядків ЛИШЕ для редактора: після нього поле скролить усередині
    /// (вікно на maxHeight). З виміряної висоти рядка, не з коефіцієнта
    private var editLineLimit: (title: Int, body: Int) {
        let area = DesktopStickyController.maxHeight - metrics.headerHeight - 20
        func lines(_ lineHeight: CGFloat) -> Int {
            lineHeight > 0 ? max(1, Int(area / lineHeight)) : 100
        }
        return (lines(metrics.titleLineHeight), lines(metrics.bodyLineHeight))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
                .background(GeometryReader { geo in
                    Color.clear.preference(
                        key: WidgetTextMetricsKey.self,
                        value: WidgetTextMetrics(headerHeight: geo.size.height))
                })
            VStack(alignment: .leading, spacing: 0) {
                titleView
                if showBody {
                    bodyView.padding(.top, 4)
                }
            }
            // У редагуванні поля fixedSize (ніколи не обрізані) — їхня
            // фактична висота піднімає natural через max-reduce; у показі
            // виміряне ≤ natural і нічого не псує
            .background(GeometryReader { geo in
                Color.clear.preference(
                    key: WidgetTextMetricsKey.self,
                    value: WidgetTextMetrics(naturalTextHeight: geo.size.height))
            })
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
        }
        .background(naturalProbe)
        .background(widthProbe)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(backdrop)
        .overlay(alignment: .bottomTrailing) { bottomControls }
        .onHover { hovering = $0 }
        .onPreferenceChange(WidgetTextMetricsKey.self) { new in
            metrics = new
            // Хром = виміряний хедер + падінги текст-зони (8 + 12)
            onContentHeight(new.headerHeight + 20 + new.naturalTextHeight)
        }
        .onPreferenceChange(WidgetIdealWidthKey.self) { onContentIdealWidth($0) }
        // Стік померив (видалення/архів з панелі, автоархів) → вікно
        // закривається; менеджер тримає інваріант. Task-хоп: не закривати
        // вікно посеред view-апдейту
        .opacity(fadeOpacity)
        .onChange(of: sticker.deletedAt) { _, _ in scheduleReconcile() }
        .onChange(of: sticker.archived) { _, _ in scheduleReconcile() }
        // Зняли «зроблено» з панелі під час fade — віджет лишається
        .onChange(of: sticker.done) { _, done in
            if !done { cancelFadeOut() }
        }
        .onChange(of: focusedField) { _, new in
            if new == nil { endEditing() }
        }
    }

    // MARK: - «Виконано» → fade → зняття зі столу (SPEC §2.7)

    private func doneAction() {
        if fadeOutTask != nil {
            // Встигли передумати — повертаємо як було (undo done)
            cancelFadeOut()
            StickerService.toggleDone(sticker)
            return
        }
        StickerService.toggleDone(sticker)
        // ✓ зняв «зроблено» з уже виконаного стіка — без зникнення
        guard sticker.done else { return }
        withAnimation(.easeInOut(duration: 2.4)) { fadeOpacity = 0 }
        fadeOutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            fadeOutTask = nil
            // Стік міг померти під час fade (видалення з панелі закрило
            // вікно, таск живе) — не мутувати: undo має повернути стан
            // як був, разом із віджетом (ревʼю 2026-07-30, Б3)
            guard sticker.deletedAt == nil, sticker.isFloating else { return }
            DesktopStickyManager.shared.reattach(sticker)
        }
    }

    private func cancelFadeOut() {
        guard fadeOutTask != nil else { return }
        fadeOutTask?.cancel()
        fadeOutTask = nil
        withAnimation(.easeOut(duration: 0.15)) { fadeOpacity = 1 }
    }

    // MARK: - Текст: показ ↔ редагування (клік у текст)

    // Інваріант розкладки (рефактор 2026-07-30, SPEC §2.7):
    // ПОКАЗ — Text БЕЗ fixedSize і БЕЗ lineLimit: текст бере рівно ту
    // висоту, що пропонує вікно; «…» зʼявляється тоді й тільки тоді,
    // коли природна висота не влазить (а вікно ≥ природної завжди, крім
    // стелі maxHeight) — «порожнеча під обрізаним» неможлива за побудовою.
    // Титул має layoutPriority — тіло обрізається першим.
    // РЕДАКТОР — поля fixedSize (вікно росте з кожним рядком) з кепом
    // editLineLimit (виміряним): після стелі скролять усередині.
    // ❗ БЕЗ .lineSpacing ніде: NSTextField-поле його ігнорує — відступи
    // «стрибали» між спокоєм і редагуванням.

    @ViewBuilder private var titleView: some View {
        if editingTitle {
            TextField("Думка…", text: $sticker.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.emUI(titleFontSize))
                .foregroundStyle(ink)
                .lineLimit(editLineLimit.title)
                .fixedSize(horizontal: false, vertical: true)
                .focused($focusedField, equals: .title)
                .onSubmit { endEditing() }
                .onExitCommand { endEditing() }
        } else {
            Text(sticker.text.isEmpty ? " " : sticker.text)
                .font(.emUI(titleFontSize))
                .foregroundStyle(ink)
                .strikethrough(sticker.done)
                .opacity(sticker.done ? 0.5 : 1)
                .layoutPriority(1)
                .contentShape(Rectangle())
                .onTapGesture { beginEdit(.title) }
        }
    }

    @ViewBuilder private var bodyView: some View {
        if editingBody {
            TextField("Додати деталі…", text: $sticker.bodyText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.emUI(bodyFontSize))
                .foregroundStyle(ink2)
                .lineLimit(editLineLimit.body)
                .fixedSize(horizontal: false, vertical: true)
                .focused($focusedField, equals: .body)
                .onSubmit { endEditing() }
                .onExitCommand { endEditing() }
        } else {
            Text(sticker.bodyText)
                .font(.emUI(bodyFontSize))
                .foregroundStyle(ink2)
                .opacity(sticker.done ? 0.4 : 1)
                .contentShape(Rectangle())
                .onTapGesture { beginEdit(.body) }
        }
    }

    private func beginEdit(_ field: Field) {
        onRequestKey()
        // Знімок лише на ВХОДІ в сесію редагування: перемикання
        // титул↔тіло без endEditing не перезнімає — інакше вже змінений
        // текст ставав «еталоном» і updatedAt губився (знахідка 5)
        if !editingTitle && !editingBody {
            editSnapshotTitle = sticker.text
            editSnapshotBody = sticker.bodyText
        }
        switch field {
        case .title: editingTitle = true
        case .body: editingBody = true
        }
        focusedField = field
    }

    private func endEditing() {
        guard editingTitle || editingBody else { return }
        editingTitle = false
        editingBody = false
        focusedField = nil
        if sticker.text != editSnapshotTitle
            || sticker.bodyText != editSnapshotBody {
            sticker.updatedAt = .now
        }
    }

    private func scheduleReconcile() {
        let s = sticker
        Task { @MainActor in DesktopStickyManager.shared.reconcile(s) }
    }

    /// Невидимий двійник тексту БЕЗ переносу — його ширина каже контролеру,
    /// якою «хоче бути» ширина вікна (найдовший жорсткий рядок)
    private var widthProbe: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sticker.text.isEmpty ? " " : sticker.text)
                .font(.emUI(titleFontSize))
            if showBody {
                Text(sticker.bodyText).font(.emUI(bodyFontSize))
            }
        }
        .fixedSize()
        .hidden()
        .background(GeometryReader { geo in
            Color.clear.preference(key: WidgetIdealWidthKey.self,
                                   value: geo.size.width)
        })
    }

    /// Невидимий двійник тексту, перенесений по АКТУАЛЬНІЙ ширині вікна,
    /// БЕЗ обрізань (fixedSize) — його висота і є «природна» правда для
    /// авто-висоти. Поруч — мікро-probe висоти одного рядка кожного кегля
    private var naturalProbe: some View {
        GeometryReader { outer in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(sticker.text.isEmpty ? " " : sticker.text)
                        .font(.emUI(titleFontSize))
                    if showBody {
                        Text(sticker.bodyText.isEmpty ? " " : sticker.bodyText)
                            .font(.emUI(bodyFontSize))
                            .padding(.top, 4)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geo in
                    Color.clear.preference(
                        key: WidgetTextMetricsKey.self,
                        value: WidgetTextMetrics(naturalTextHeight: geo.size.height))
                })
                // 24 — горизонтальні падінги текст-зони (12+12)
                .frame(width: max(outer.size.width - 24, 10), alignment: .topLeading)

                Text("X").font(.emUI(titleFontSize)).fixedSize()
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: WidgetTextMetricsKey.self,
                            value: WidgetTextMetrics(titleLineHeight: geo.size.height))
                    })
                Text("X").font(.emUI(bodyFontSize)).fixedSize()
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: WidgetTextMetricsKey.self,
                            value: WidgetTextMetrics(bodyLineHeight: geo.size.height))
                    })
            }
            .hidden()
        }
    }

    // MARK: - Скло за стилем (спільний DesktopStickyBackdrop)

    private var backdrop: some View {
        DesktopStickyBackdrop(style: effectiveStyle, color: color,
                              cornerRadius: Self.cornerRadius)
    }

    // MARK: - Хедер (тихіший, 2026-07-30): зліва «дата · стіна» звичайними
    // маленькими літерами, muted — як мета в картках панелі; справа шеврон
    // title↔full (лише коли є bodyText) + хрестик «сховати». Іконки
    // приглушені, на hover яскравішають; без риски-розділювача. Порожні
    // зони хедера тягнуть вікно — поводиться як заголовок.
    // Видалення з віджета НЕМАЄ (спрощення 2026-07-30): хрестик лише
    // прибирає зі столу, стік лишається в панелі. Видалення — з панелі.

    private var headerBar: some View {
        HStack(spacing: 6) {
            Text(headerLabel)
                .font(.emUI(10))
                .foregroundStyle(ink3)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Group {
                if !sticker.bodyText.isEmpty {
                    controlButton(sticker.floatDisplayMode == "full"
                                  ? "chevron.up" : "chevron.down") {
                        sticker.floatDisplayMode =
                            sticker.floatDisplayMode == "full" ? "title" : "full"
                        sticker.updatedAt = .now
                    }
                }
                controlButton("xmark") {
                    endEditing()
                    DesktopStickyManager.shared.reattach(sticker)
                }
            }
            .opacity(hovering ? 1 : 0.55)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var ink3: Color { tokens.ink3 }

    /// «вчора · Робота»; без живої стіни — лише дата
    private var headerLabel: String {
        let date = StickyDateFormat.relative(sticker.createdAt)
        if let wall = sticker.wall, wall.deletedAt == nil, !wall.name.isEmpty {
            return "\(date) · \(wall.name)"
        }
        return date
    }

    @ViewBuilder private var bottomControls: some View {
        if hovering {
            HStack(spacing: 8) {
                // Синхронно з панеллю: той самий обʼєкт бази
                controlButton("checkmark") { doneAction() }
                controlButton("ellipsis") { onOpenSettings() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    /// Гола іконка-дія (без плашок, делікатна); на темному склі — світла
    private func controlButton(_ systemName: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(ink.opacity(0.65))
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
