import AVFoundation
import CoreMedia
import EdgelitCore
import ScreenCaptureKit

/// Listens to everything the Mac is playing (not the microphone) using ScreenCaptureKit's audio capture.
/// Needs the Screen Recording permission. Edgelit never records or stores any audio: each block is
/// turned into a few loudness numbers and thrown away.
final class AudioTap: NSObject, SCStreamOutput, SCStreamDelegate {
    private let pipeline: AudioPipeline
    private let queue = DispatchQueue(label: "edgelit.audio", qos: .userInteractive)
    private var stream: SCStream?
    private(set) var running = false
    var onActivity: (() -> Void)?
    var onError: ((String) -> Void)?
    private var lastKick: CFTimeInterval = 0

    init(pipeline: AudioPipeline) { self.pipeline = pipeline }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func start() {
        guard !running else { return }
        running = true
        Log.write("music: starting audio capture")
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else { throw NSError(domain: "Edgelit", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"]) }
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let cfg = SCStreamConfiguration()
                cfg.capturesAudio = true
                cfg.excludesCurrentProcessAudio = true
                cfg.sampleRate = 48000
                cfg.channelCount = 2
                // We only want sound, so ask for the smallest, slowest picture possible.
                cfg.width = 64; cfg.height = 64
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 2)
                cfg.queueDepth = 3
                let s = SCStream(filter: filter, configuration: cfg, delegate: self)
                try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                try await s.startCapture()
                self.stream = s
                Log.write("music: audio capture running")
            } catch {
                self.running = false
                Log.write("music: capture failed: \(error)")
                DispatchQueue.main.async { self.onError?(error.localizedDescription) }
            }
        }
    }

    func stop() {
        running = false
        let s = stream
        stream = nil
        Task { try? await s?.stopCapture() }
        pipeline.reset()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        running = false
        self.stream = nil
        Log.write("music: capture stopped: \(error)")
        DispatchQueue.main.async { self.onError?(error.localizedDescription) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid, let mono = Self.monoSamples(from: sb) else { return }
        pipeline.feed(mono)
        // Only wake the display when something is actually audible, so silence keeps the overlay asleep.
        let now = CACurrentMediaTime()
        if pipeline.latest.rms > 0.004, now - lastKick > 0.1 {
            lastKick = now
            DispatchQueue.main.async { [weak self] in self?.onActivity?() }
        }
    }

    /// Averages the channels of an audio buffer into one list of samples.
    private static func monoSamples(from sb: CMSampleBuffer) -> [Float]? {
        var size = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sb, bufferListSizeNeededOut: &size, bufferListOut: nil, bufferListSize: 0,
                                                                      blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil) == noErr,
              size > 0 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        defer { raw.deallocate() }
        let abl = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sb, bufferListSizeNeededOut: nil, bufferListOut: abl, bufferListSize: size,
                                                                      blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                                                                      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &block) == noErr
        else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        guard let first = buffers.first, let firstData = first.mData else { return nil }

        if buffers.count > 1 {                                     // one buffer per channel
            let n = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            var out = [Float](repeating: 0, count: n)
            for b in buffers {
                guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<min(n, Int(b.mDataByteSize) / 4) { out[i] += p[i] }
            }
            let k = 1 / Float(buffers.count)
            return out.map { $0 * k }
        }
        let channels = max(1, Int(first.mNumberChannels))          // channels interleaved in one buffer
        let total = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        let p = firstData.assumingMemoryBound(to: Float.self)
        let frames = total / channels
        var out = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            var s: Float = 0
            for c in 0..<channels { s += p[f * channels + c] }
            out[f] = s / Float(channels)
        }
        return out
    }
}
