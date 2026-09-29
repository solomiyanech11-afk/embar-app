//
//  EmbarToggleStyle.swift
//  Embar
//
//  iOS-подібний перемикач. Два розміри з прототипу:
//  · .sheet (36×21, knob 17) — bottom-sheet налаштувань
//  · .expanded (30×17, knob 13) — компактний, у expanded-редакторі стіка
//

import SwiftUI

struct EmbarToggleStyle: ToggleStyle {
    let trackSize: CGSize
    let knob: CGFloat

    static let sheet = EmbarToggleStyle(trackSize: CGSize(width: 36, height: 21), knob: 17)
    // Дрібніший розмір жив під тумблером автоархіву в стіку; той зник
    // разом із самим тумблером (2026-08-19), тож і розмір прибрано

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? EmbarColors.ink : Color.black.opacity(0.15))
                    .frame(width: trackSize.width, height: trackSize.height)
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                    .padding(2)
            }
            .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}
