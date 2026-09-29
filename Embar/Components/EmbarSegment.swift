//
//  EmbarSegment.swift
//  Embar
//
//  Сегмент-контейнер (прототип .theme-segment): тонована капсула, активний
//  елемент — пігулка, що ковзає на нову позицію. Витягнуто зі
//  SettingsSheetContent (2026-08-18), щоб «Архівувати через» в острівці
//  стіка й дп/пп у степері часу були тим САМИМ компонентом.
//
//  Рух — 1:1 патерн чіпів стін (FolderChip + switchWall): тексти міняються
//  МИТТЄВО (.animation(nil)), фон їде matchedGeometryEffect-ом, а анімацію
//  запускає withAnimation(.spring 0.3/0.8) навколо зміни вибору. Жодних
//  власних кривих — консистентність із рештою програми (§7.2-A).
//
//  Дві шкіри однієї форми (як .surface/.tinted у NewChipField):
//  · surface — біла пігулка з тінню, світла панель (сегмент теми, прототип);
//  · tinted — чорна пігулка з білим текстом, кольорові поверхні (острівці).
//
//  Hover свідомо НЕМА (фідбек 2026-08-18): пігулка сама показує вибір.
//

import SwiftUI

struct EmbarSegment<ID: Hashable>: View {
    enum Style { case surface, tinted }
    /// regular — налаштування; compact — острівці; mini — в один зріст із
    /// пігулками степера часу (23pt)
    enum Size { case regular, compact, mini }

    struct Option {
        let id: ID
        let label: String
        var icon: String? = nil
    }

    let options: [Option]
    /// nil — жоден не активний (наприклад, строк автоархіву не з набору)
    let selection: ID?
    var style: Style = .surface
    var size: Size = .regular
    /// Елементи рівної ширини на весь контейнер. false — за вмістом (дп/пп)
    var fillWidth: Bool = true
    /// Чорнила кольорової поверхні (стік, SPEC §15.57): tint-контейнер
    /// напівпрозорий, тож неактивний текст фактично лежить на кольорі
    /// стіка; nil = панельні EmbarColors
    var inks: StickyInk.Tokens? = nil
    var onSelect: (ID) -> Void

    /// Спільний простір пігулки — щоб вона їхала, а не блимала
    @Namespace private var pillSpace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.id) { option in
                segButton(option)
            }
        }
        .padding(containerPad)
        .background(Capsule().fill(EmbarColors.tint))
    }

    private var containerPad: CGFloat {
        switch size { case .regular: 4; case .compact: 3; case .mini: 2 }
    }

    private var vPad: CGFloat {
        switch size { case .regular: 10; case .compact: 6; case .mini: 3 }
    }

    private var fontSize: CGFloat {
        switch size { case .regular: 12; case .compact: 11; case .mini: 10.5 }
    }

    private var activeFill: Color {
        style == .surface ? .white : EmbarColors.ink
    }

    private var activeInk: Color {
        style == .surface ? EmbarColors.ink : .white
    }

    private func segButton(_ option: Option) -> some View {
        let active = option.id == selection
        return Button {
            // Той самий спринг, що в switchWall (рух чіпів стін)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                onSelect(option.id)
            }
        } label: {
            HStack(spacing: 6) {
                if let icon = option.icon {
                    Image(systemName: icon).font(.system(size: 11))
                }
                Text(option.label)
                    .font(.emUI(fontSize, weight: active ? .medium : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? activeInk : (inks?.ink2 ?? EmbarColors.ink3))
            // Тексти — миттєво (FolderChip robить так само)
            .animation(nil, value: active)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .padding(.horizontal, fillWidth ? 0 : 9)
            .padding(.vertical, vPad)
            .background {
                if active {
                    Capsule().fill(activeFill)
                        .matchedGeometryEffect(id: "pill", in: pillSpace)
                        .shadow(color: .black.opacity(style == .surface ? 0.06 : 0),
                                radius: 4, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
