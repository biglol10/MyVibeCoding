@preconcurrency import AVFoundation
import AudioToolbox

enum RecordingAudioConfiguration {
    static let sampleRate = 48_000

    static func makeInput(channelCount: Int) -> AVAssetWriterInput {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: channelCount == 1 ? 96_000 : 192_000
        ])
        input.expectsMediaDataInRealTime = true
        return input
    }
}
