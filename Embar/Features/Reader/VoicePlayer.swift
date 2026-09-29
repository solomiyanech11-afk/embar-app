//
//  VoicePlayer.swift
//  Embar
//
//  Відтворення голосових (SPEC §4.3, крок 13): ОДИН спільний плеєр на
//  блокнот — старт нового запису зупиняє попередній. Пауза тримає
//  позицію; сік по кліку на хвилю; після фінішу все скидається.
//

import Foundation
import Combine
import AVFoundation

@MainActor
final class VoicePlayer: NSObject, ObservableObject {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    @Published private(set) var currentID: UUID?
    @Published private(set) var isPlaying = false
    /// 0…1 поточного запису
    @Published private(set) var progress: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    /// Play/pause для запису; інший запис — зупиняє попередній
    func toggle(_ id: UUID, data: Data) {
        if currentID == id, let player {
            if isPlaying {
                player.pause()
                isPlaying = false
                stopTimer()
            } else {
                player.play()
                isPlaying = true
                startTimer()
            }
            return
        }
        load(id, data: data)
        player?.play()
        isPlaying = player != nil
        startTimer()
    }

    /// Клік по хвилі: перемотати (і грати, якщо ще не грає)
    func seek(_ id: UUID, data: Data, fraction: Double) {
        if currentID != id { load(id, data: data) }
        guard let player else { return }
        player.currentTime = max(0, min(fraction, 1)) * player.duration
        progress = max(0, min(fraction, 1))
        if !isPlaying {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func stop() {
        player?.stop()
        stopTimer()
        player = nil
        currentID = nil
        isPlaying = false
        progress = 0
    }

    private func load(_ id: UUID, data: Data) {
        stop()
        guard let newPlayer = try? AVAudioPlayer(data: data) else { return }
        newPlayer.delegate = self
        player = newPlayer
        currentID = id
        progress = 0
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.progress = player.duration > 0
                    ? player.currentTime / player.duration : 0
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension VoicePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer,
                                                 successfully flag: Bool) {
        Task { @MainActor in self.stop() } // фініш → бари скидаються
    }
}

// MARK: - Детермінована хвиля (прототип qnFillVoiceBars)

enum VoiceWaveform {
    /// Висоти барів 7–22px, стабільні між рендерами: сід — id запису,
    /// мікс — murmur-фіналізер по індексу
    static func heights(seed: UUID, count: Int) -> [CGFloat] {
        var hash: UInt32 = 2166136261
        withUnsafeBytes(of: seed.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt32(byte)
                hash = hash &* 16777619
            }
        }
        return (0..<count).map { index in
            var x = hash &+ UInt32(index) &* 0x9E3779B9
            x ^= x >> 16
            x = x &* 0x85ebca6b
            x ^= x >> 13
            return 7 + CGFloat(x % 16) // 7…22
        }
    }
}
