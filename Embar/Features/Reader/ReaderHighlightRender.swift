//
//  ReaderHighlightRender.swift
//  Embar
//
//  Рендер хайлайтів запису (SPEC §4.3, §11.6; прототип renderEntryRichText).
//  Кольори ФІКСОВАНІ (не з палітри): заливка — спільний HighlightColor
//  (EmbarAttributes), лінії підкреслення — свої набори; при накладанні
//  заливки й підкреслення лінія темніша (прототип .hl-both.ul-*).
//  Кілька хайлайтів на символі — останній виграє (окремо фон і лінія).
//

import SwiftUI
import AppKit

/// Кольори ліній підкреслення (прототип 1677–1692)
extension HighlightColor {
    /// Лінія самостійного підкреслення
    var strokeNSColor: NSColor {
        switch self {
        case .yellow: return NSColor(embarHex: "#e6c34d")
        case .purple: return NSColor(embarHex: "#a285ce")
        case .blue:   return NSColor(embarHex: "#5e95d2")
        case .red:    return NSColor(embarHex: "#c97070")
        }
    }

    /// Темніша лінія, коли підкреслення накладене на заливку
    var combinedStrokeNSColor: NSColor {
        switch self {
        case .yellow: return NSColor(embarHex: "#c9a82a")
        case .purple: return NSColor(embarHex: "#7a5fa4")
        case .blue:   return NSColor(embarHex: "#4a72a6")
        case .red:    return NSColor(embarHex: "#9a4f4f")
        }
    }
}

/// Полегшений знімок Highlight для чистих функцій (тестується без SwiftData)
struct HighlightSpan: Equatable {
    let start: Int
    let end: Int
    let colorName: String
    let mode: String

    init(start: Int, end: Int, colorName: String, mode: String) {
        self.start = start
        self.end = end
        self.colorName = colorName
        self.mode = mode
    }

    init(_ highlight: Highlight) {
        self.init(start: highlight.start, end: highlight.end,
                  colorName: highlight.colorName, mode: highlight.mode)
    }
}

enum ReaderHighlightRender {

    /// Валідний діапазон UTF-16 у тексті довжини length (SPEC §11.6:
    /// биті діапазони ігноруються при рендері)
    static func isValid(_ span: HighlightSpan, length: Int) -> Bool {
        span.start >= 0 && span.start < span.end && span.end <= length
    }

    struct Segment: Equatable {
        let range: NSRange
        /// colorName заливки (mode=highlight), останній виграє
        let fill: String?
        /// colorName лінії (mode=underline), останній виграє
        let stroke: String?
    }

    /// Розкласти текст на сегменти зі зведеними стилями
    static func segments(length: Int, spans: [HighlightSpan]) -> [Segment] {
        let valid = spans.filter { isValid($0, length: length) }
        guard !valid.isEmpty, length > 0 else { return [] }
        var bounds: Set<Int> = [0, length]
        for span in valid {
            bounds.insert(span.start)
            bounds.insert(span.end)
        }
        let sorted = bounds.sorted()
        var result: [Segment] = []
        for (a, b) in zip(sorted, sorted.dropFirst()) where a < b {
            let fill = valid.last {
                $0.mode == "highlight" && $0.start <= a && b <= $0.end
            }?.colorName
            let stroke = valid.last {
                $0.mode == "underline" && $0.start <= a && b <= $0.end
            }?.colorName
            result.append(Segment(range: NSRange(location: a, length: b - a),
                                  fill: fill, stroke: stroke))
        }
        return result
    }

    /// Шматок слова з єдиним стилем (word-flow-рендер): слово ділиться
    /// по межах хайлайтів — «пів слова» фарбується рівно до межі (фідбек
    /// 2026-07-07). continues* кажуть, чи ця сама заливка триває за краєм
    /// шматка (тоді кут квадратний і фон тягнеться в проміжок — смуга
    /// виглядає суцільною через пробіли)
    struct WordPiece: Equatable {
        let range: NSRange
        let fill: String?
        let stroke: String?
        let fillContinuesLeft: Bool
        let fillContinuesRight: Bool
    }

    static func wordPieces(word: NSRange, length: Int,
                           spans: [HighlightSpan]) -> [WordPiece] {
        let segs = segments(length: length, spans: spans)
        guard !segs.isEmpty else {
            return [WordPiece(range: word, fill: nil, stroke: nil,
                              fillContinuesLeft: false, fillContinuesRight: false)]
        }
        // Заливка в позиції (для перевірки безперервності через пробіли)
        let valid = spans.filter { isValid($0, length: length) }
        func fillAt(_ position: Int) -> String? {
            guard position >= 0, position < length else { return nil }
            return valid.last {
                $0.mode == "highlight" && $0.start <= position && position < $0.end
            }?.colorName
        }
        var pieces: [WordPiece] = []
        for segment in segs {
            let start = max(segment.range.location, word.location)
            let end = min(segment.range.location + segment.range.length,
                          word.location + word.length)
            guard start < end else { continue }
            let continuesLeft = segment.fill != nil
                && fillAt(start - 1) == segment.fill
            let continuesRight = segment.fill != nil
                && fillAt(end) == segment.fill
            pieces.append(WordPiece(
                range: NSRange(location: start, length: end - start),
                fill: segment.fill, stroke: segment.stroke,
                fillContinuesLeft: continuesLeft,
                fillContinuesRight: continuesRight))
        }
        return pieces
    }
}
