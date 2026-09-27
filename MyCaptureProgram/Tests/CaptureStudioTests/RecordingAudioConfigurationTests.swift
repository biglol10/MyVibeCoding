@preconcurrency import AVFoundation
import AudioToolbox
import XCTest
@testable import CaptureStudio

@MainActor
final class RecordingAudioConfigurationTests: XCTestCase {
    func testSystemAndMicrophoneInputsWriteDecodableAudioTracksToMP4() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audio-test-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let inputs = [2, 1].map { RecordingAudioConfiguration.makeInput(channelCount: $0) }
        for input in inputs {
            XCTAssertTrue(writer.canAdd(input))
            writer.add(input)
        }
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for (index, input) in inputs.enumerated() {
            for _ in 0..<100 {
                if input.isReadyForMoreMediaData { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(input.isReadyForMoreMediaData)
            let sample = try tone(channelCount: index == 0 ? 2 : 1)
            XCTAssertTrue(input.append(sample), "\(String(describing: writer.error))")
            input.markAsFinished()
        }
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 2)
        for track in tracks {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            reader.add(output)
            XCTAssertTrue(reader.startReading())
            var hasSignal = false
            while let sample = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
                var values = [Int16](repeating: 0, count: CMBlockBufferGetDataLength(block) / 2)
                let status = values.withUnsafeMutableBytes {
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
                }
                XCTAssertEqual(status, noErr)
                if values.contains(where: { abs(Int($0)) > 1_000 }) { hasSignal = true }
            }
            XCTAssertEqual(reader.status, .completed)
            XCTAssertTrue(hasSignal, "The encoded audio track must contain the synthetic tone, not silence.")
        }
    }

    private func tone(channelCount: Int) throws -> CMSampleBuffer {
        let sampleRate = 48_000
        let frames = 12_000
        var format = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channelCount * 2), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channelCount * 2), mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 16, mReserved: 0
        )
        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &description), noErr)
        var samples = [Int16](repeating: 0, count: frames * channelCount)
        for frame in 0..<frames {
            let value = Int16(sin(Double(frame) * 2 * .pi * 440 / Double(sampleRate)) * 10_000)
            for channel in 0..<channelCount { samples[frame * channelCount + channel] = value }
        }
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: samples.count * 2, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: samples.count * 2, flags: 0, blockBufferOut: &block), noErr)
        let buffer = try XCTUnwrap(block)
        XCTAssertEqual(samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: buffer, offsetIntoDestination: 0, dataLength: $0.count)
        }, noErr)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
            dataBuffer: buffer, formatDescription: try XCTUnwrap(description), sampleCount: frames,
            presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }
}
