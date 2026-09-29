//
//  NewChipField.swift
//  Embar
//
//  Інлайн-поле створення чіпа («＋» у барі стін/папок). Було два дублі, які
//  вже розійшлися: у папок нотаток був автофокус, у стін — ні (code review,
//  reuse). Тепер автофокус мають обидва.
//

import SwiftUI

struct NewChipField: View {
    /// surface — біла пігулка з тінню (бари стін/папок на фоні панелі);
    /// tinted — прозоро-чорний фон у розмір optionPill, для кольорових
    /// острівців стіка (фідбек 2026-08-18: біле вибивалося з гами)
    enum Style { case surface, tinted }

    let placeholder: LocalizedStringKey
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void
    /// Спроба перевищити ліміт: господар-бар прогортує ряд, щоб пігулку
    /// було видно цілком (фідбек 2026-09-04 - вона відкривалась за краєм)
    var onLimitHit: (() -> Void)? = nil
    var style: Style = .surface

    @FocusState private var focused: Bool

    /// Спроба перевищити ліміт (R4): зайве вже зрізано, пігулка пояснює.
    /// Гасне, щойно людина зітре хоч символ
    @State private var hitLimit = false

    var body: some View {
        // Пігулка НАД полем: бари стін/папок стоять при самому низі
        // панелі, і все, що нижче поля, зрізав би горизонтальний
        // ScrollView бара (той самий кліп, через який ×-бейдж потребує
        // зазору). Зʼявлення миттєве - стан помилки, не поверхня (§7.2-A)
        VStack(alignment: .leading, spacing: 4) {
            if hitLimit {
                Text(FolderNameRule.message)
                    .font(.emUI(10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(EmbarColors.danger))
                    .fixedSize()
            }
            field
        }
        // Поле лишається на лінії чіпів: центр ряду береться від ПОЛЯ,
        // а не від блока з пігулкою - інакше пігулка штовхала поле вниз
        // (фідбек 2026-09-04). Число = половина висоти поля (шрифт +
        // вертикальні padding-и); без пігулки збігається зі звичайним
        // центром піксель у піксель
        .alignmentGuide(VerticalAlignment.center) { d in
            d[.bottom] - (style == .surface ? 13.5 : 11)
        }
    }

    private var field: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.emUI(style == .surface ? 12 : 11.5))
            .frame(width: style == .surface ? 90 : 80)
            .focused($focused)
            .padding(.horizontal, style == .surface ? 12 : 9)
            .padding(.vertical, style == .surface ? 6 : 4)
            .background(Capsule().fill(
                style == .surface ? AnyShapeStyle(EmbarColors.surface.opacity(0.92))
                                  : AnyShapeStyle(Color.black.opacity(0.06))))
            // Тінь = FolderChip (0.10/3/1, фідбек 2026-08-12); tinted — без
            // тіні, він лежить у пласкому острівці
            .shadow(color: .black.opacity(style == .surface ? 0.10 : 0),
                    radius: 3, y: 1)
            .onSubmit(onSubmit)
            // Жорсткий блок ліміту (R4): 51-й символ (чи довга вставка)
            // не пишеться - зайве зрізається тим самим тіком
            .onChange(of: text) { _, newValue in
                if FolderNameRule.exceeds(newValue) {
                    text = FolderNameRule.clamped(newValue)
                    hitLimit = true
                    onLimitHit?()
                } else if newValue.count < FolderNameRule.maxLength {
                    hitLimit = false
                }
            }
            .onExitCommand(perform: onCancel)
            // Передумали і клацнули в інше поле (пошук, композер) - поле
            // зникає, а не висить порожнім (фідбек 2026-08-12). Кліки повз,
            // що фокус не крадуть, ловить прозорий шар у господаря
            .onChange(of: focused) { _, isFocused in
                if !isFocused { onCancel() }
            }
            // Клавіатура ОДРАЗУ в полі (фідбек 2026-09-04): клік по «+» -
            // це клік по кнопці, а nonactivating-панель від кнопок key не
            // бере (becomesKeyOnlyIfNeeded) - @FocusState без key-вікна
            // мовчав, і доводилось клікати в поле ще раз
            .background(MakeWindowKeyOnAppear { focused = true })
    }
}

/// Робить вікно поля key при появі і ЛИШЕ ПОТІМ вмикає @FocusState -
/// у зворотному порядку фокус губився (вікно ще не key). Через NSView,
/// бо це єдиний шлях дістати вікно зсередини SwiftUI-компонента
private struct MakeWindowKeyOnAppear: NSViewRepresentable {
    var then: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            view?.window?.makeKey()
            then()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
