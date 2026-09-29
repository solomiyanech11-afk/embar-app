//
//  Highlight.swift
//  Embar
//
//  Хайлайт у тексті рідер-запису. SPEC.md §11.6
//  Кольори фіксовані (yellow/purple/blue/red), НЕ залежать від палітри.
//

import Foundation
import SwiftData

@Model
final class Highlight {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil

    /// Індекси символів у text запису; невалідні діапазони ігноруються при рендерингу
    var start: Int = 0
    var end: Int = 0
    /// "yellow" | "purple" | "blue" | "red"
    var colorName: String = "yellow"
    /// "highlight" | "underline"
    var mode: String = "highlight"

    var entry: ReaderEntry? = nil

    init(start: Int = 0, end: Int = 0, colorName: String = "yellow", mode: String = "highlight") {
        self.start = start
        self.end = end
        self.colorName = colorName
        self.mode = mode
    }
}
