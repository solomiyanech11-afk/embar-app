//
//  HomeTimelineView.swift
//  Embar
//
//  Таймлайн дня (SPEC §5.2): 00:00–24:00, 58pt/год, горизонтальний скрол,
//  події з lane-packing, now-лінія лише на сьогодні, автоскрол до поточної
//  години. Drag-to-create/resize/move — лише сьогодні/майбутні дні.
//

import SwiftUI
import SwiftData

struct HomeTimelineView: View {
    @ObservedObject var home: HomeModel
    let palette: Palette
    @Query private var allEvents: [Event]

    var onAddEvent: () -> Void = {}
    var onEventTap: (Event) -> Void = { _ in }
    var onCreateDrag: (_ start: Double, _ end: Double, _ color: Int) -> Void = { _, _, _ in }

    // Константи прототипу
    private let pxH: CGFloat = 58
    private let areaTop: CGFloat = 24
    private let laneOffset: CGFloat = 55
    private let eventHeight: CGFloat = 65
    private let trackHeight: CGFloat = 150
    private var trackWidth: CGFloat { 24 * pxH }

    private enum DragMode { case none, move, resize }
    @State private var dragEventID: UUID?
    @State private var dragMode: DragMode = .none
    @State private var dragDeltaH: Double = 0
    /// Ghost drag-to-create; lane 1 = «другий поверх», коли налазить
    /// на існуючу подію (прототип: top 24↔79)
    @State private var ghost: (start: Double, end: Double, lane: Int)?
    /// Рандомний колір поточної спроби створення (ghost + модал)
    @State private var draftColor = Int.random(in: 0..<5)
    /// Защіпка початкового позиціювання: скролимо один раз при першому
    /// реальному layout; ресайз панелі більше НЕ смикає користувача (review)
    @State private var didInitialScroll = false

    private var isToday: Bool { home.isToday }
    private var editable: Bool { !home.isReadOnlyDay }

    /// X-ціль позиціювання: сьогодні — now-лінія, інші дні — 08:00
    private var anchorX: CGFloat {
        isToday ? CGFloat(HomeService.hourOfDay(.now)) * pxH : 8 * pxH
    }

    /// Висота вмісту треку. До ДВОХ поверхів (lane 0–1) все вміщається у
    /// вікно 150pt — вміст = вікно, жодного вертикального «колихання».
    /// Вертикальний скрол з'являється лише з 3+ поверхами
    private func contentHeight(maxLane: Int) -> CGFloat {
        guard maxLane >= 2 else { return trackHeight }
        return areaTop + CGFloat(maxLane) * laneOffset + eventHeight + 8
    }

    var body: some View {
        // Розкладка дня — ОДИН раз за рендер і далі вниз параметрами:
        // як computed-властивості фільтр + lane-packing перезапускались
        // кожним читачем (~30×/body і на кожен кадр drag-у)
        let events = HomeService.events(on: home.selectedDate, from: allEvents)
        let laidOut = assignLanes(events)
        let maxLane = laidOut.map(\.lane).max() ?? 0
        VStack(spacing: 10) {
            header
            timelineScroll(events: events, laidOut: laidOut,
                           maxLane: maxLane,
                           contentHeight: contentHeight(maxLane: maxLane))
        }
        .padding(.vertical, 14)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12)).foregroundStyle(EmbarColors.ink3)
                .frame(width: 22, height: 22)
            Text("РОЗКЛАД ДНЯ")
                .font(.emUI(10, weight: .medium)).tracking(1.4)
                .foregroundStyle(EmbarColors.ink3)
            Spacer()
            if editable {
                Button(action: onAddEvent) {
                    Text("＋ подія").font(.emUI(12, weight: .medium))
                        .foregroundStyle(EmbarColors.ink2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Track

    private func timelineScroll(events: [Event], laidOut: [(event: Event, lane: Int)],
                                maxLane: Int, contentHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            // Вертикальна вісь вмикається лише з 3+ поверхами подій
            ScrollView(maxLane >= 2 ? [.horizontal, .vertical] : [.horizontal],
                       showsIndicators: false) {
                track(events: events, laidOut: laidOut, contentHeight: contentHeight)
                    .frame(width: trackWidth, height: contentHeight)
                    .coordinateSpace(name: "track")
                    .padding(.horizontal, 18)
            }
            .frame(height: trackHeight) // вікно фіксоване, вміст скролиться
            .scrollIndicators(.hidden)
            // Тригер позиціювання — ОДИН раз, коли ширина вьюпорта фактично
            // відома (перший layout); подальші зміни ширини (ресайз панелі)
            // позицію користувача не чіпають. Зміна дня — явний ре-тригер
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { initialScrollIfReady(g.size.width, proxy) }
                    .onChange(of: g.size.width) { _, w in initialScrollIfReady(w, proxy) }
            })
            .onChange(of: home.selectedDate) { _, _ in scrollToDayPosition(proxy) }
        }
    }

    private func initialScrollIfReady(_ width: CGFloat, _ proxy: ScrollViewProxy) {
        guard !didInitialScroll, width > 0 else { return }
        didInitialScroll = true
        scrollToDayPosition(proxy)
    }

    /// SPEC §5.2: сьогодні — now-лінія по центру видимої області (clamp
    /// країв робить сам scrollTo); інші дні — 08:00 зліва. Миттєво.
    private func scrollToDayPosition(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("dayAnchor", anchor: isToday ? .center : .leading)
    }

    private func track(events: [Event], laidOut: [(event: Event, lane: Int)],
                       contentHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Фон-шар для drag-to-create (за подіями)
            Color.white.opacity(0.001)
                .frame(width: trackWidth, height: contentHeight)
                .contentShape(Rectangle())
                .gesture(createDragGesture(events: events))

            // Осьова лінія
            Rectangle().fill(Color.black.opacity(0.06))
                .frame(width: trackWidth, height: 1).offset(y: 20)

            // Години: сітка + підписи.
            // ❗ Підписи — через .position, НЕ .offset: offset зсуває лише
            // картинку, а layout-frame лишається на (0,0) — через це
            // scrollTo їхав на 00:00 замість поточної години
            ForEach(0...24, id: \.self) { hr in
                Rectangle().fill(Color.black.opacity(0.04))
                    .frame(width: 1, height: contentHeight - 18)
                    .offset(x: CGFloat(hr) * pxH, y: 18)
                Text(ReaderDateFormat.hourLabel(hr))
                    .font(.emUI(10).monospacedDigit())
                    .foregroundStyle(EmbarColors.ink3)
                    .fixedSize()
                    .position(x: CGFloat(hr) * pxH, y: 9)
            }

            // Якір позиціювання дня: РЕАЛЬНА 1×1 layout-рамка на anchorX через
            // HStack зі спейсером. ❗ .position тут не годиться: .id висів би
            // на position-обгортці, чия рамка = весь трек (x=0, w=1392,
            // виміряно) — scrollTo «центрував» увесь вміст, а не точку now
            HStack(spacing: 0) {
                Color.clear.frame(width: anchorX, height: 1)
                Color.clear.frame(width: 1, height: 1).id("dayAnchor")
                Spacer(minLength: 0)
            }
            .frame(width: trackWidth, alignment: .leading)
            .allowsHitTesting(false)

            // Ghost drag-to-create: рандомний колір спроби; при перетині
            // з існуючою подією стрибає на другу доріжку
            if let g = ghost {
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.sticky[draftColor].opacity(0.7))
                    .frame(width: max(CGFloat(g.end - g.start) * pxH, 4), height: eventHeight)
                    .offset(x: CGFloat(g.start) * pxH,
                            y: areaTop + CGFloat(g.lane) * laneOffset)
                    .animation(.easeOut(duration: 0.12), value: g.lane)
            }

            // Події
            ForEach(laidOut, id: \.event.id) { item in
                eventPill(item.event, lane: item.lane)
            }

            // Now-лінія — лише сьогодні; ПОВЕРХ подій (у них zIndex 2+lane,
            // тому лінії потрібен вищий; прототип: z 20/21)
            if isToday {
                let nowX = CGFloat(HomeService.hourOfDay(.now)) * pxH
                Rectangle().fill(EmbarColors.ink.opacity(0.85))
                    .frame(width: 1.5, height: contentHeight - 22)
                    .offset(x: nowX, y: 18)
                    .zIndex(50)
                Circle().fill(EmbarColors.ink)
                    .frame(width: 8, height: 8)
                    .offset(x: nowX - 4, y: 14)
                    .zIndex(51)
            }

            // Empty state
            if events.isEmpty {
                Text("Подій немає.")
                    .font(.emDisplay(13, italic: true))
                    .foregroundStyle(EmbarColors.ink3)
                    .frame(width: trackWidth, height: contentHeight, alignment: .center)
                    .allowsHitTesting(false)
            }
        }
    }

    private func eventPill(_ event: Event, lane: Int) -> some View {
        var (start, end) = HomeService.eventHours(event)
        // Живий прев'ю під час drag
        if dragEventID == event.id {
            if dragMode == .move { start += dragDeltaH; end += dragDeltaH }
            else if dragMode == .resize { end += dragDeltaH }
        }
        let x = CGFloat(start) * pxH
        let w = max(CGFloat(end - start) * pxH - 4, 48)
        let color = palette.sticky[min(event.colorIndex % 5, palette.sticky.count - 1)]
        return RoundedRectangle(cornerRadius: 8).fill(color)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(EmbarColors.surface.opacity(0.6), lineWidth: 1))
            .overlay(
                Text(event.label).font(.emUI(11, weight: .medium))
                    .foregroundStyle(EmbarColors.ink).lineLimit(2)
                    .padding(.horizontal, 10)
            )
            .overlay(alignment: .trailing) {
                // Ручка ресайзу на правому краю (лише редаговані дні)
                if editable {
                    Color.white.opacity(0.001).frame(width: 12)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(event, mode: .resize))
                }
            }
            .frame(width: w, height: eventHeight)
            .offset(x: x, y: areaTop + CGFloat(lane) * laneOffset)
            .zIndex(Double(2 + lane))
            .onTapGesture { onEventTap(event) }
            .gesture(editable ? dragGesture(event, mode: .move) : nil)
    }

    // MARK: - Drag

    private func dragGesture(_ event: Event, mode: DragMode) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dragEventID = event.id
                dragMode = mode
                dragDeltaH = Double(value.translation.width) / Double(pxH)
            }
            .onEnded { _ in commitDrag(event) }
    }

    private func commitDrag(_ event: Event) {
        defer { dragEventID = nil; dragMode = .none; dragDeltaH = 0 }
        guard dragEventID == event.id else { return }
        let (start0, end0) = HomeService.eventHours(event)
        let snapped = (dragDeltaH * 2).rounded() / 2
        if dragMode == .move {
            let dur = end0 - start0
            let ns = min(max(start0 + snapped, 0), 24 - dur)
            event.startDate = HomeService.date(day: home.selectedDate, hour: ns)
            event.endDate = HomeService.date(day: home.selectedDate, hour: ns + dur)
        } else if dragMode == .resize {
            let ne = max(start0 + 0.5, min(24, end0 + snapped))
            event.endDate = HomeService.date(day: home.selectedDate, hour: ne)
        }
        event.updatedAt = .now
    }

    private func createDragGesture(events: [Event]) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("track"))
            .onChanged { value in
                guard editable else { return }
                if ghost == nil {
                    // Нова спроба — новий рандомний колір
                    draftColor = Int.random(in: 0..<palette.sticky.count)
                }
                let a = Double(value.startLocation.x / pxH)
                let b = Double(value.location.x / pxH)
                // Clamp 0…24 вже на ghost: курсор може вийти за межі треку
                let s = max(0, min(a, b)), e = min(24, max(a, b))
                ghost = (s, e, overlapsExisting(s, e, in: events) ? 1 : 0)
            }
            .onEnded { _ in
                defer { ghost = nil }
                guard editable, let g = ghost else { return }
                // Clamp обох країв: без max(0,…) drag за лівий край створював
                // подію о 23:00 ВЧОРА, що зникала з поточного дня (review)
                let start = max(0, (g.start * 2).rounded() / 2)
                var end = min(24, (g.end * 2).rounded() / 2)
                if end - start < 0.5 { end = min(start + 0.5, 24) }
                guard end > start else { return }
                onCreateDrag(start, end, draftColor)
            }
    }

    /// Чи перетинається інтервал з якоюсь подією дня (для «другого поверху» ghost)
    private func overlapsExisting(_ start: Double, _ end: Double, in events: [Event]) -> Bool {
        events.contains { ev in
            let (s, e) = HomeService.eventHours(ev)
            return max(start, s) < min(end, e)
        }
    }

    // MARK: - Lane-packing (кластер → доріжки)

    private func assignLanes(_ events: [Event]) -> [(event: Event, lane: Int)] {
        var laneEnds: [Double] = []
        var result: [(event: Event, lane: Int)] = []
        for event in events {
            let (start, end) = HomeService.eventHours(event)
            if let lane = laneEnds.firstIndex(where: { $0 <= start }) {
                laneEnds[lane] = end
                result.append((event, lane))
            } else {
                laneEnds.append(end)
                result.append((event, laneEnds.count - 1))
            }
        }
        return result
    }
}
