//
//  ReaderShelfLayout.swift
//  Embar
//
//  Чисте групування карток полиці (SPEC §4.1; прототип renderReaderShelf).
//  Editorial-сітка: групи «tall + 2 квадрати», сторона tall чергується;
//  хвости — «tall + квадрат» (2) або tall на всю ширину (1).
//

import Foundation

enum ReaderShelfLayout {

    /// Група карток; значення — індекси у відсортованому масиві блокнотів
    enum Group: Equatable {
        /// Одна картка на всю ширину (tall)
        case full(Int)
        /// tall + один квадрат
        case pair(tall: Int, square: Int, tallLeft: Bool)
        /// Стандартна група: tall + два квадрати
        case trio(tall: Int, squares: [Int], tallLeft: Bool)
    }

    static func groups(count: Int) -> [Group] {
        var result: [Group] = []
        var i = 0
        var groupIdx = 0
        while i < count {
            let remaining = count - i
            let tallLeft = groupIdx % 2 == 0
            switch remaining {
            case 1:
                result.append(.full(i))
                i += 1
            case 2:
                result.append(.pair(tall: i, square: i + 1, tallLeft: tallLeft))
                i += 2
            default:
                result.append(.trio(tall: i, squares: [i + 1, i + 2], tallLeft: tallLeft))
                i += 3
            }
            groupIdx += 1
        }
        return result
    }
}
