//
//  HomeModel.swift
//  Embar
//
//  Стан Home-шторки (SPEC §5). Живе на рівні панелі (ContentView).
//  `todayAnchor` оновлюється при переході доби (нотифікація .embarDayChanged
//  з AppDelegate) — тиждень/таймлайн перемальовуються.
//

import SwiftUI
import Combine

@MainActor
final class HomeModel: ObservableObject {
    @Published var isOpen = false
    @Published var selectedDate: Date
    @Published var todayAnchor: Date

    private var observer: NSObjectProtocol?

    init() {
        let today = Calendar.current.startOfDay(for: .now)
        selectedDate = today
        todayAnchor = today
        observer = NotificationCenter.default.addObserver(
            forName: .embarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let wasToday = self.isToday
                self.todayAnchor = Calendar.current.startOfDay(for: .now)
                // Якщо дивилися «сьогодні» — лишаємось на новому сьогодні
                if wasToday { self.selectedDate = self.todayAnchor }
            }
        }
    }

    nonisolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var isToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: todayAnchor)
    }

    /// Дні від сьогодні до вибраного (від'ємне — минуле): визначає доступ до подій
    var dayOffset: Int {
        Calendar.current.dateComponents([.day], from: todayAnchor, to: selectedDate).day ?? 0
    }

    /// Read-only, якщо вибрано минулий день (SPEC §5.2)
    var isReadOnlyDay: Bool { dayOffset < 0 }

    func open() {
        selectedDate = todayAnchor
        isOpen = true
    }

    func close() { isOpen = false }
    func goToToday() { selectedDate = todayAnchor }
}
