//
//  LazyTwoColumnMasonry.swift
//  Embar
//
//  Дві колонки з ЛІНИВИМ рендером (перф-фікс 2026-08-16): попередник
//  (TwoColumnMasonry, Layout-протокол) інстанціював і міряв УСІ картки —
//  на 5000 стіків це сотні мілісекунд на кожну розкладку і секунди на
//  перебудову. Тут навпаки: розкладання по колонках рахуємо самі за
//  ОЦІНКОЮ висот (кешованою), а картки живуть у двох LazyVStack — SwiftUI
//  створює лише видимі.
//
//  Ціна компромісу: колонки балансуються за оцінкою, а не реальними
//  висотами. Оцінка міряє той самий текст тим самим шрифтом (TextKit),
//  тож розбіжність — пікселі; на рендер карток вона не впливає взагалі
//  (LazyVStack кладе їх за реальною висотою).
//
//  Ідентичність карток стабільна (id елемента), але живе В МЕЖАХ своєї
//  колонки — перескік між колонками (done/pin/delete) пересотворює вьюху.
//  Для видимих ~15 карток це дешево.
//
//  Ширину масонрі міряє САМА (ревʼю 2026-08-18, знахідка 7). Раніше її
//  міряв GeometryReader на всій поверхні Стіків і писав у @State вьюхи —
//  а ресайз панелі шле подію на КОЖЕН рух миші (ResizeHandleView кличе
//  setFrame щокадру). Через це кожен кадр ресайзу інвалідовував увесь
//  body: O(n) фільтр, O(n log n) сортування, прохід лічильників — хоча
//  ширина потрібна ЛИШЕ тут, для розкладання по колонках. Тепер @State
//  локальний, і перерахунок теж локальний.
//

import SwiftUI

struct LazyTwoColumnMasonry<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var spacing: CGFloat = 10
    /// Ширина до першого заміру геометрії — щоб не мигнути нульовою
    var fallbackWidth: CGFloat = 340
    /// Оцінка висоти елемента при ширині колонки (кешування — на совісті
    /// того, хто дає замикання)
    let estimatedHeight: (Item, CGFloat) -> CGFloat
    /// Вміст картки: елемент + його НАСКРІЗНИЙ порядковий номер (для каскаду)
    @ViewBuilder let content: (Item, Int) -> Content

    /// Виміряна ширина під обидві колонки. Локальний @State: його зміна
    /// не інвалідовує нічого, крім самої масонрі
    @State private var measuredWidth: CGFloat = 0

    private struct Placed: Identifiable {
        let item: Item
        let order: Int
        var id: Item.ID { item.id }
    }

    var body: some View {
        let width = measuredWidth > 0 ? measuredWidth : fallbackWidth
        let colWidth = max((width - spacing) / 2, 0)
        let (left, right) = split(colWidth: colWidth)
        HStack(alignment: .top, spacing: spacing) {
            column(left)
            column(right)
        }
        // Ширину диктує батько (картки тягнуться на всю колонку), тож
        // замір не залежить від вмісту і петлі «зміряв → пересунув →
        // зміряв інакше» не буває
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear.onChange(of: geo.size.width, initial: true) { _, w in
                    if measuredWidth != w { measuredWidth = w }
                }
            }
        )
    }

    private func column(_ placed: [Placed]) -> some View {
        LazyVStack(spacing: spacing) {
            ForEach(placed) { entry in
                content(entry.item, entry.order)
            }
        }
    }

    /// Greedy: кожен елемент — у коротшу (за оцінкою) колонку. O(n) при
    /// теплому кеші висот
    private func split(colWidth: CGFloat) -> ([Placed], [Placed]) {
        #if DEBUG
        // Зонд пісочниці: поза -SandboxPerfProbe це один Bool-чек
        let probeStart = PerfProbe.isActive ? CFAbsoluteTimeGetCurrent() : 0
        defer {
            if PerfProbe.isActive {
                PerfProbe.shared.record("masonry.split(\(items.count) карток)",
                                        seconds: CFAbsoluteTimeGetCurrent() - probeStart)
            }
        }
        #endif
        var left: [Placed] = []
        var right: [Placed] = []
        var leftH: CGFloat = 0
        var rightH: CGFloat = 0
        for (order, item) in items.enumerated() {
            let h = estimatedHeight(item, colWidth) + spacing
            if leftH <= rightH {
                left.append(Placed(item: item, order: order))
                leftH += h
            } else {
                right.append(Placed(item: item, order: order))
                rightH += h
            }
        }
        return (left, right)
    }
}
