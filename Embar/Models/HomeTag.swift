//
//  HomeTag.swift
//  Embar
//
//  Тег тудушок на Home (стандартні + кастомні). SPEC.md §11.12
//

import Foundation
import SwiftData

@Model
final class HomeTag {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil

    var name: String = ""
    /// "work" | "home" | "family" | "neutral" | випадковий з пулу для кастомних
    var colorKey: String = "neutral"

    init(name: String = "", colorKey: String = "neutral") {
        self.name = name
        self.colorKey = colorKey
    }
}
