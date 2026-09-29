//
//  Event.swift
//  Embar
//
//  Подія на таймлайні Home. SPEC.md §11.11
//

import Foundation
import SwiftData

@Model
final class Event {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil

    /// Порожня назва при збереженні → дефолт «Подія»
    var label: String = ""
    /// Повноцінні дати (float-години прототипу конвертуються в Date)
    var startDate: Date? = nil
    var endDate: Date? = nil
    /// Індекс кольору в живу палітру (mod 5)
    var colorIndex: Int = 0
    var notes: String = ""

    init(label: String = "", startDate: Date? = nil, endDate: Date? = nil) {
        self.label = label
        self.startDate = startDate
        self.endDate = endDate
    }
}
