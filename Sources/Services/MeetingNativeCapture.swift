import AppKit
import AVFoundation
import ScreenCaptureKit

@MainActor
protocol MeetingCapturing: AnyObject {
    func start(folder: URL, microphone: Bool, system: Bool,
               closed: @escaping @Sendable (MeetingAudioChunk) -> Void,
               failed: @escaping @Sendable (String) -> Void) async throws
    func stop() async -> [MeetingAudioChunk]
}

@MainActor
final class MeetingNativeCapture: NSObject, MeetingCapturing, SCStreamDelegate {
    private(set) var identity: UUID?
    private let startupForTesting: (() async throws -> Void)?
    private var engine: AVAudioEngine?
    private var stream: SCStream?
    private var output: MeetingSystemAudioOutput?
    private var sinks: [MeetingAudioSink] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var reportFailure: (@Sendable (String) -> Void)?
    private var stopTask: Task<[MeetingAudioChunk], Never>?

    init(startupForTesting: (() async throws -> Void)? = nil) { self.startupForTesting = startupForTesting }

    func start(folder: URL, microphone: Bool, system: Bool,
               closed: @escaping @Sendable (MeetingAudioChunk) -> Void,
               failed: @escaping @Sendable (String) -> Void) async throws {
        guard !AppEnvironment.isRunningTests || startupForTesting != nil, identity == nil, microphone || system else {
            throw MeetingError.audio
        }
        let id = UUID()
        stopTask = nil
        identity = id
        reportFailure = failed
        do {
            if let startupForTesting { try await startupForTesting(); try check(id); return }
            try await permissions(microphone: microphone, system: system)
            try check(id)
            let epoch = AVAudioTime.seconds(forHostTime: mach_absolute_time())
            if microphone {
                let sink = MeetingAudioSink(folder: folder, source: .microphone, epoch: epoch, closed: closed, failed: failed)
                sinks.append(sink)
                try startMicrophone(sink)
            }
            if system {
                let sink = MeetingAudioSink(folder: folder, source: .system, epoch: epoch, closed: closed, failed: failed)
                sinks.append(sink)
                try await startSystem(sink, id: id)
            }
            try check(id)
            observeInterruptions()
        } catch {
            if identity == id { _ = await stop() }
            throw error
        }
    }

    private func permissions(microphone: Bool, system: Bool) async throws {
        if microphone {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .audio) }
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw MeetingError.microphone }
        }
        if system, !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            guard CGPreflightScreenCaptureAccess() else { throw MeetingError.systemPermission }
        }
    }

    private func check(_ id: UUID) throws {
        try Task.checkCancellation()
        guard identity == id else { throw CancellationError() }
    }

    private func startMicrophone(_ sink: MeetingAudioSink) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MeetingError.audio }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, time in
            let stamp = time.isHostTimeValid ? time.hostTime : mach_absolute_time()
            sink.append(buffer, time: AVAudioTime.seconds(forHostTime: stamp))
        }
        self.engine = engine
        engine.prepare()
        try engine.start()
    }

    private func startSystem(_ sink: MeetingAudioSink, id: UUID) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try check(id)
        guard let display = content.displays.first else { throw MeetingError.noDisplay }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let output = MeetingSystemAudioOutput(sink: sink, failed: reportFailure ?? { _ in })
        try stream.addStreamOutput(output, type: .audio,
                                   sampleHandlerQueue: DispatchQueue(label: "com.audiowhisper.meeting-system"))
        self.stream = stream
        self.output = output
        try await stream.startCapture()
        do { try check(id) } catch { try? await stream.stopCapture(); throw error }
    }

    private func observeInterruptions() {
        if let engine {
            let center = NotificationCenter.default
            let observer = center.addObserver(forName: .AVAudioEngineConfigurationChange,
                object: engine, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.interrupt("Microphone configuration changed. Audio was kept.") }
                }
            observers.append((center, observer))
        }
        let center = NSWorkspace.shared.notificationCenter
        let observer = center.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.interrupt("The Mac went to sleep. Audio was kept.") }
            }
        observers.append((center, observer))
    }

    private func interrupt(_ message: String) {
        guard identity != nil else { return }
        reportFailure?(message)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let message = error.localizedDescription
        let source = ObjectIdentifier(stream)
        Task { @MainActor [weak self] in
            guard let self, self.stream.map(ObjectIdentifier.init) == source else { return }
            interrupt("System audio stopped: " + message)
        }
    }

    func stop() async -> [MeetingAudioChunk] {
        if let stopTask { return await stopTask.value }
        identity = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers = []
        let stream = self.stream
        self.stream = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        output = nil
        let sources = sinks
        sinks = []
        let task = Task {
            try? await stream?.stopCapture()
            var chunks: [MeetingAudioChunk] = []
            for sink in sources { chunks += await sink.finish() }
            return chunks
        }
        stopTask = task
        return await task.value
    }
}

private final class MeetingSystemAudioOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let sink: MeetingAudioSink
    let failed: @Sendable (String) -> Void
    init(sink: MeetingAudioSink, failed: @escaping @Sendable (String) -> Void) {
        self.sink = sink
        self.failed = failed
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                    frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))) else {
            failed("System audio buffer allocation failed. Closed chunks were kept.")
            return
        }
        buffer.frameLength = buffer.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(buffer.frameLength),
                                                         into: buffer.mutableAudioBufferList) == noErr else {
            failed("System audio conversion failed. Closed chunks were kept.")
            return
        }
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        sink.append(buffer, time: time)
    }
}
