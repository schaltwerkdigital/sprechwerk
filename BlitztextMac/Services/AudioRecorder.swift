import AVFoundation
import Observation

@Observable
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var recordingURL: URL?
    var errorMessage: String?
    var audioLevel: Float = 0
    var lastRecordingDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    /// Recording from a microphone chosen in the settings (Sprechwerk); AVAudioRecorder only
    /// knows the system default.
    private var engine: AVAudioEngine?
    private var engineWriter: EngineFileWriter?

    /// One file per recording: deleting one after its transcription never hits the next.
    private var fileURL = AudioRecorder.newFileURL()

    private static func newFileURL(extension pathExtension: String = "m4a") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("recording-\(UUID().uuidString).\(pathExtension)")
    }

    /// Deletes this recorder's audio, for recordings that are not transcribed.
    func discardRecording() {
        try? FileManager.default.removeItem(at: fileURL)
        recordingURL = nil
    }

    /// Recordings a crash or quit left behind, with their padded copies (`AudioPadding`), the
    /// stretches of live notes and the converted and streamed copies of meeting and audio file
    /// sound; nothing records or transcribes while the app starts.
    static func removeLeftoverRecordings() {
        let temp = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let name = file.lastPathComponent
            let leftover = (name.hasPrefix("recording") && ["m4a", "wav"].contains(file.pathExtension))
                || (["blitztext-padded-", "blitztext-live-", "blitztext-import-"].contains { name.hasPrefix($0) } && file.pathExtension == "wav")
                || (name.hasPrefix("fluidaudio-streaming-") && file.pathExtension == "raw")
            if leftover { try? FileManager.default.removeItem(at: file) }
        }
    }

    func startRecording() {
        errorMessage = nil
        lastRecordingDuration = 0
        fileURL = Self.newFileURL()

        // Without access macOS records silence; say why instead of "Keine Aufnahme erkannt".
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            errorMessage = MicrophonePermission.deniedMessage
            return
        default:
            break
        }

        if let device = MicrophoneDevices.preferredDevice() {
            startEngineRecording(from: device)
            return
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            guard audioRecorder?.record() == true else {
                audioRecorder = nil
                errorMessage = "Die Aufnahme lie\u{00DF} sich nicht starten. Darf Sprechwerk das Mikrofon nutzen?"
                return
            }
            isRecording = true
            recordingURL = nil
            startMetering()
        } catch {
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            lastRecordingDuration = engineWriter?.close() ?? 0
            self.engine = nil
            engineWriter = nil
            isRecording = false
            recordingURL = fileURL
            audioLevel = 0
            return
        }
        stopMetering()
        lastRecordingDuration = audioRecorder?.currentTime ?? 0
        audioRecorder?.stop()
        isRecording = false
        recordingURL = fileURL
        audioLevel = 0
    }

    /// Records the chosen device as a mono WAV at its own sample rate; the transcription
    /// converts any file it gets.
    private func startEngineRecording(from device: MicrophoneDevices.Device) {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        var deviceID = device.id
        guard let unit = input.audioUnit,
              AudioUnitSetProperty(
                  unit,
                  kAudioOutputUnitProperty_CurrentDevice,
                  kAudioUnitScope_Global,
                  0,
                  &deviceID,
                  UInt32(MemoryLayout<AudioDeviceID>.size)
              ) == noErr
        else {
            errorMessage = "\u{201E}\(device.name)\u{201C} l\u{00E4}sst sich nicht als Mikrofon nutzen. In den Einstellungen ein anderes w\u{00E4}hlen."
            return
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false)
        else {
            errorMessage = "\u{201E}\(device.name)\u{201C} liefert gerade keinen Ton. In den Einstellungen ein anderes Mikrofon w\u{00E4}hlen."
            return
        }

        fileURL = Self.newFileURL(extension: "wav")
        do {
            let file = try AVAudioFile(forWriting: fileURL, settings: mono.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let writer = EngineFileWriter(file: file, format: mono)
            input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
                let level = writer.append(buffer)
                DispatchQueue.main.async { self?.audioLevel = level }
            }
            engine.prepare()
            try engine.start()
            self.engine = engine
            engineWriter = writer
            isRecording = true
            recordingURL = nil
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    private func startMetering() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.audioRecorder?.updateMeters()
            let power = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
            let normalized = max(0, min(1, (power + 50) / 50))
            self.audioLevel = normalized
        }
    }

    private func stopMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in
                self.errorMessage = "Aufnahme fehlgeschlagen"
            }
        }
    }
}

/// Writes the tapped input as mono into the recording file, off the main thread. Several
/// channels (an interface, a virtual device) are averaged.
final class EngineFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private let format: AVAudioFormat
    private var frames: AVAudioFramePosition = 0

    init(file: AVAudioFile, format: AVAudioFormat) {
        self.file = file
        self.format = format
    }

    /// Appends the buffer and returns its level 0...1, on the same scale as AVAudioRecorder's
    /// metering (-50 dB to 0 dB).
    func append(_ buffer: AVAudioPCMBuffer) -> Float {
        let count = Int(buffer.frameLength)
        guard count > 0, let source = buffer.floatChannelData,
              let mono = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              let target = mono.floatChannelData?[0]
        else { return 0 }
        let channels = Int(buffer.format.channelCount)
        var sumOfSquares: Float = 0
        for frame in 0..<count {
            var sample: Float = 0
            for channel in 0..<channels {
                sample += source[channel][frame]
            }
            sample /= Float(channels)
            target[frame] = sample
            sumOfSquares += sample * sample
        }
        mono.frameLength = buffer.frameLength

        lock.lock()
        if let file {
            try? file.write(from: mono)
            frames += AVAudioFramePosition(count)
        }
        lock.unlock()

        let rms = (sumOfSquares / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_001))
        return max(0, min(1, (decibels + 50) / 50))
    }

    /// Closes the file (by releasing it) and returns the recorded seconds.
    func close() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        file = nil
        return Double(frames) / format.sampleRate
    }
}
