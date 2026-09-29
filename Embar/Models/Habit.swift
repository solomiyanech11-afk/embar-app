//
//  Habit.swift
//  Embar
//
//  Звичка зі стріком. SPEC.md §11.10
//

import Foundation
import SwiftData

@Model
final class Habit {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil

    var text: String = ""
    /// Виконано СЬОГОДНІ. Скидається опівночі локального часу (M3),
    /// а факт виконання записується в completions
    var doneToday: Bool = false
    /// Історія виконань (дати днів). Стрік = послідовні календарні дні
    /// назад від сьогодні/вчора — НЕ демо-алгоритм прототипу
    var completions: [Date] = []

    init(text: String = "") {
        self.text = text
    }
}
