//
//  ReaderSource.swift
//  Embar
//
//  Джерело блокнота (лінк на статтю/відео/документ). SPEC.md §11.8
//

import Foundation
import SwiftData

@Model
final class ReaderSource {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date? = nil

    /// Нормалізується до https при збереженні
    var url: String = ""
    /// Людська назва (домен), виводиться з url
    var label: String = ""

    var book: ReaderBook? = nil

    init(url: String = "", label: String = "") {
        self.url = url
        self.label = label
    }
}
