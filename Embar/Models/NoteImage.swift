//
//  NoteImage.swift
//  Embar
//
//  Інлайн-зображення нотатки. SPEC.md §11.3-b.
//  Байти зберігаються ОКРЕМО від архіву тіла: autosave не переписує
//  мегабайти, а під CloudKit кожне фото стає окремим CKAsset.
//

import Foundation
import SwiftData

@Model
final class NoteImage {
    var id: UUID = UUID()
    var createdAt: Date = Date.now

    /// Даунскейлена копія (JPEG). externalStorage — поруч із базою, не в ній.
    @Attribute(.externalStorage)
    var data: Data? = nil

    /// Нотатка-власник. Зворотний бік — Note.images (.cascade)
    var note: Note? = nil

    init() {}
}
