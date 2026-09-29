//
//  VoiceRecorder.swift
//  Embar
//
//  Запис голосових у Рідері (SPEC §4.2, крок 12). Дозвіл мікрофона —
//  ЛІНИВО при першому тапі (Embar.md §12): системний діалог через
//  AVCaptureDevice; відмова → View показує мʼяке пояснення з лінком у
//  System Settings (не alert — прототипний alert це заглушка).
//  Формат: AAC m4a, 44.1 кГц, моно → тимчасовий файл у контейнері →
//  Data в ReaderEntry.audioData (externalStorage).
//

import Foundation
import Combine
import AVFoundation

@MainActor
final class VoiceRecorder: ObservableObject {
    nonisolated deinit {} // захист від міни ізольованого deinit — див. CLAUDE.md
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// Доступ заборонено — показати пояснення (скидається хрестиком)
    @Published var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    /// «0:07» — таймер запису і тривалість пігулки (прототип fmtVoiceTime)
    static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    // MARK: - Старт (лінивий дозвіл)

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                // Колбек приходить на довільній черзі — стрибаємо на main
                Task { @MainActor in
                    if granted { self.begin() } else { self.permissionDenied = true }
                }
            }
        default:
            permissionDenied = true
        }
    }

    private func begin() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("embar-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let newRecorder = try? AVAudioRecorder(url: url, settings: settings),
              newRecorder.record() else { return }
        recorder = newRecorder
        fileURL = url
        elapsed = 0
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsed = self?.recorder?.currentTime ?? 0
            }
        }
    }

    // MARK: - Стоп

    /// Зупинити і віддати аудіо. ❗ Тривалість читаємо ДО stop() —
    /// після нього currentTime скидається в 0. Закороткі (<0.4с) —
    /// відкидаємо (випадковий тап)
    func finish() -> (data: Data, duration: Double)? {
        guard let activeRecorder = recorder, let url = fileURL else { return nil }
        let duration = activeRecorder.currentTime
        activeRecorder.stop()
        resetState()
        defer { try? FileManager.default.removeItem(at: url) }
        guard duration > 0.4, let data = try? Data(contentsOf: url) else { return nil }
        return (data, duration)
    }

    /// Блокнот закрився під час запису — тихо прибрати
    func cancel() {
        recorder?.stop()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        resetState()
    }

    private func resetState() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        fileURL = nil
        isRecording = false
        elapsed = 0
    }
}
