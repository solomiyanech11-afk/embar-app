//
//  NoteFolder.swift
//  Embar
//
//  Папка нотаток. SPEC.md §11.4
//

import Foundation
import SwiftData

@Model
final class NoteFolder {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil

    var name: String = ""

    @Relationship(inverse: \Note.folder)
    var notes: [Note]? = nil

    init(name: String = "") {
        self.name = name
    }
}
