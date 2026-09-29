//
//  Wall.swift
//  Embar
//
//  Стіна (тека) стіків. SPEC.md §11.2
//

import Foundation
import SwiftData

@Model
final class Wall {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil

    var name: String = ""
    /// Колір стіни в режимі «Свій колір у стіни»: індекс 0–4 у палітру
    /// (стабільний при зміні палітри). nil = різнокольорові
    var colorSlot: Int? = nil
    /// Порядок у барі стін (drag-сортування)
    var sortOrder: Int = 0

    @Relationship(inverse: \Sticker.wall)
    var stickers: [Sticker]? = nil

    /// Колір стіни в режимі byWall: явно обраний colorSlot, інакше
    /// детермінований дефолт за порядком (стабільний між запусками)
    var effectiveColorSlot: Int {
        colorSlot ?? (((sortOrder % 5) + 5) % 5)
    }

    init(name: String = "") {
        self.name = name
    }
}
