import AVFoundation
import Foundation

/// Streams frames from the camera on a background queue.
///
/// Frames are handed to `onFrame` as they arrive and are never stored.
final class CameraSource: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    typealias FrameHandler = (CVPixelBuffer, TimeInterval) -> Void

    enum CameraError: Error, CustomStringConvertible {
        case accessDenied
        case noCamera
        case cannotConfigure

        var description: String {
            switch self {
            case .accessDenied:
                return "Camera access was denied. Allow it for your terminal app in "
                    + "System Settings > Privacy & Security > Camera, then run again."
            case .noCamera:
                return "No camera was found."
            case .cannotConfigure:
                return "The camera could not be configured."
            }
        }
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "airswipe.camera", qos: .userInteractive)
    private let onFrame: FrameHandler

    init(onFrame: @escaping FrameHandler) {
        self.onFrame = onFrame
        super.init()
    }

    /// Asks for camera permission if it has not been decided, then starts streaming.
    func start() throws {
        try requestAccess()

        guard let device = Self.preferredCamera() else { throw CameraError.noCamera }
        let input = try AVCaptureDeviceInput(device: device)

        let output = AVCaptureVideoDataOutput()
        // If Vision is still busy, drop the frame instead of queueing latency.
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        // Hand pose does not need more than VGA, and it keeps CPU and battery low.
        session.sessionPreset = .vga640x480
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraError.cannotConfigure
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        session.startRunning()
    }

    func stop() {
        session.stopRunning()
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        onFrame(pixelBuffer, time)
    }

    // MARK: - Helpers

    /// Blocks start-up until the user answers the system prompt, so the first
    /// frames are not silently lost.
    private func requestAccess() throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            let answered = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .video) {
                granted = $0
                answered.signal()
            }
            answered.wait()
            if !granted { throw CameraError.accessDenied }
        default:
            throw CameraError.accessDenied
        }
    }

    /// Prefer the built-in camera over a phone or external one.
    private static func preferredCamera() -> AVCaptureDevice? {
        let builtIn = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.first
        return builtIn ?? AVCaptureDevice.default(for: .video)
    }
}
