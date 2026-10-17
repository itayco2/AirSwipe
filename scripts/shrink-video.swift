import AVFoundation
import Foundation

// Makes a small, easy-to-share copy of a screen recording: 1080p H.264 that fits a size budget.
//
//   swift scripts/shrink-video.swift input.mov output.mp4 [megabytes]      default 45
//
// A raw Retina screen recording is hundreds of MB. macOS's built-in presets are generous
// (the 1080p preset made 173 MB from a 90 s recording), so this asks the exporter to fit a
// file size instead, which leaves the picture sharp enough to read text. The original is
// never touched. Needs only Apple's own frameworks.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: swift scripts/shrink-video.swift input.mov output.mp4 [megabytes]")
    exit(2)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let megabytes = arguments.count > 3 ? Int64(arguments[3]) ?? 45 : 45

try? FileManager.default.removeItem(at: output)
let asset = AVURLAsset(url: input)
guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
    print("could not start the export")
    exit(1)
}
export.outputURL = output
export.outputFileType = .mp4
export.fileLengthLimit = megabytes * 1024 * 1024
export.shouldOptimizeForNetworkUse = true

let finished = DispatchSemaphore(value: 0)
export.exportAsynchronously { finished.signal() }
finished.wait()

if export.status == .completed {
    let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64) ?? 0
    print("wrote \(output.path) (\(size / 1024 / 1024) MB)")
} else {
    print("failed: \(String(describing: export.error))")
    exit(1)
}
