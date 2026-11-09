@preconcurrency import AVFoundation
import Domain
import Foundation

/// Adds a music track to a rendered (silent) video: loops or trims it to the video length,
/// fades it in and out, and re-muxes. The video samples are copied as-is (no re-encode).
enum AudioMixer {
    static let fadeInMs = 500
    static let volume: Float = 0.8

    static func mux(video: URL, audio: URL, fadeOutMs: Int, to output: URL) async throws(RenderError) {
        do {
            try await performMux(video: video, audio: audio, fadeOutMs: fadeOutMs, to: output)
        } catch {
            try? FileManager.default.removeItem(at: output)
            if error is CancellationError { throw .cancelled }
            throw (error as? RenderError) ?? .writerFailed
        }
    }

    private static func performMux(video: URL, audio: URL, fadeOutMs: Int, to output: URL) async throws {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first
        else { throw RenderError.writerFailed }
        let duration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        guard audioDuration > .zero else { throw RenderError.writerFailed }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw RenderError.writerFailed }
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        var cursor = CMTime.zero
        while cursor < duration {
            let chunk = min(audioDuration, duration - cursor)
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: chunk), of: sourceAudio, at: cursor)
            cursor = cursor + chunk
        }

        let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
        let fadeIn = CMTime(value: CMTimeValue(fadeInMs), timescale: 1000)
        let fadeOut = CMTime(value: CMTimeValue(min(fadeOutMs, Int(duration.seconds * 500))), timescale: 1000)
        parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: volume, timeRange: CMTimeRange(start: .zero, duration: fadeIn))
        parameters.setVolumeRamp(fromStartVolume: volume, toEndVolume: 0, timeRange: CMTimeRange(start: duration - fadeOut, duration: fadeOut))
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]

        let reader = try AVAssetReader(asset: composition)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: [audioTrack], audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        audioOutput.audioMix = mix
        reader.add(videoOutput)
        reader.add(audioOutput)

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let formatHint = try await sourceVideo.load(.formatDescriptions).first
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatHint)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2, AVSampleRateKey: 44_100, AVEncoderBitRateKey: 128_000,
        ])
        writer.add(videoInput)
        writer.add(audioInput)
        guard reader.startReading(), writer.startWriting() else { throw RenderError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        try await interleave([(videoOutput, videoInput), (audioOutput, audioInput)])
        guard reader.status == .completed else {
            writer.cancelWriting()
            throw RenderError.writerFailed
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw RenderError.writerFailed }
    }

    /// Feeds every reader output into its writer input, alternating so the writer can interleave the tracks.
    private static func interleave(_ pairs: [(output: AVAssetReaderOutput, input: AVAssetWriterInput)]) async throws {
        var finished = Array(repeating: false, count: pairs.count)
        while finished.contains(false) {
            try Task.checkCancellation()
            var progressed = false
            for (index, pair) in pairs.enumerated() where !finished[index] && pair.input.isReadyForMoreMediaData {
                if let sample = pair.output.copyNextSampleBuffer() {
                    guard pair.input.append(sample) else { throw RenderError.writerFailed }
                } else {
                    pair.input.markAsFinished()
                    finished[index] = true
                }
                progressed = true
            }
            if !progressed { try await Task.sleep(for: .milliseconds(2)) }
        }
    }
}
