import AppKit
import AVFoundation
import CoreVideo
import Foundation

@main
enum FrameVideoEncoder {
    static func main() async {
        do {
            let args = CommandLine.arguments
            // executable + frames directory + destination MP4
            guard args.count == 3 else { throw NSError(domain: "CasaReel", code: 1) }
            let frames = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: args[1]), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "webp" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard let first = frames.first, let image = NSImage(contentsOf: first), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw NSError(domain: "CasaReel", code: 2) }
            let size = CGSize(width: 720, height: 1280), output = URL(fileURLWithPath: args[2]); try? FileManager.default.removeItem(at: output)
            let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height, kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
            writer.add(input); guard writer.startWriting() else { throw writer.error ?? NSError(domain: "CasaReel", code: 3) }; writer.startSession(atSourceTime: .zero)
            for (index, url) in frames.enumerated() { while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }; guard let frame = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil), let pool = adaptor.pixelBufferPool else { continue }; var buffer: CVPixelBuffer?; guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { continue }; CVPixelBufferLockBaseAddress(buffer, []); let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!; context.clear(CGRect(origin: .zero, size: size)); let scale = max(size.width / CGFloat(frame.width), size.height / CGFloat(frame.height)); let rect = CGRect(x: (size.width-CGFloat(frame.width)*scale)/2, y: (size.height-CGFloat(frame.height)*scale)/2, width: CGFloat(frame.width)*scale, height: CGFloat(frame.height)*scale); context.draw(frame, in: rect); CVPixelBufferUnlockBaseAddress(buffer, []); guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 24)) else { throw writer.error ?? NSError(domain: "CasaReel", code: 4) } }
            input.markAsFinished(); await writer.finishWriting(); guard writer.status == .completed else { throw writer.error ?? NSError(domain: "CasaReel", code: 5) }
            _ = cg
        } catch { FileHandle.standardError.write(Data("Frame encoder: \(error)\n".utf8)); Foundation.exit(1) }
    }
}
