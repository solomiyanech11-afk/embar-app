//
//  Todo.swift
//  Embar
//
//  Тудушка на Home-екрані. SPEC.md §11.9
//

import Foundation
import SwiftData

@Model
final class Todo {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil

    var text: String = ""
    /// Назва тега («робота», «дім», «сім'я» чи кастомний); nil = без тега.
    /// Стік → тудушка: копія тексту, БЕЗ зворотного лінка (як у прототипі)
    var tagName: String? = nil
    var done: Bool = false
    /// Момент виконання (SPEC §11.9). Виконані лишаються у вкладці «Виконано»
    /// до кінця дня; після півночі — soft-delete у AppMaintenance
    var completedAt: Date? = nil

    init(text: String = "", tagName: String? = nil) {
        self.text = text
        self.tagName = tagName
    }
}
