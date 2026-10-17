import AirSwipeCore
import AppKit
import AVFoundation

/// A small floating window that shows what the camera sees, with the hand drawn on it and
/// what AirSwipe is doing, so a screen recording shows both "you" and the Mac at once.
///
/// It sits in the bottom-right corner, above everything including full-screen apps, on every
/// desktop, and ignores the mouse so it never gets in the way. The image is the same live
/// feed AirSwipe reads (the camera is opened once), mirrored like a mirror unless
/// `--no-mirror`. Must be created and used on the main thread.
final class PreviewWindow {
    private static let size = CGSize(width: 320, height: 240)

    private let panel: NSPanel
    private let root: CALayer
    private let video: AVCaptureVideoPreviewLayer
    private let lines = CAShapeLayer()
    private let dots = CAShapeLayer()
    private let stateBackdrop = CALayer()
    private let stateText = CATextLayer()
    private let toastBackdrop = CALayer()
    private let toastText = CATextLayer()
    private let mirrored: Bool
    private var toastHide: DispatchWorkItem?

    init(session: AVCaptureSession, mirrored: Bool) {
        self.mirrored = mirrored
        let size = Self.size
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        root = view.layer!
        root.cornerRadius = 14
        root.masksToBounds = true
        root.borderWidth = 3
        root.borderColor = NSColor.systemGray.cgColor
        root.backgroundColor = NSColor.black.cgColor

        video = AVCaptureVideoPreviewLayer(session: session)
        video.frame = CGRect(origin: .zero, size: size)
        video.videoGravity = .resizeAspectFill
        if let connection = video.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
        root.addSublayer(video)

        for shape in [lines, dots] {
            shape.frame = CGRect(origin: .zero, size: size)
            root.addSublayer(shape)
        }
        lines.fillColor = nil
        lines.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        lines.lineWidth = 2
        lines.lineCap = .round
        lines.lineJoin = .round

        // The state strip along the top.
        stateBackdrop.frame = CGRect(x: 0, y: size.height - 26, width: size.width, height: 26)
        stateBackdrop.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        root.addSublayer(stateBackdrop)
        Self.configure(stateText, scale: scale, size: 13, align: .left)
        stateText.frame = CGRect(x: 10, y: size.height - 22, width: size.width - 20, height: 18)
        root.addSublayer(stateText)

        // The pill near the bottom that names the last thing AirSwipe did.
        toastBackdrop.frame = CGRect(x: 30, y: 14, width: size.width - 60, height: 28)
        toastBackdrop.cornerRadius = 14
        toastBackdrop.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        toastBackdrop.opacity = 0
        root.addSublayer(toastBackdrop)
        Self.configure(toastText, scale: scale, size: 14, align: .center)
        toastText.frame = CGRect(x: 30, y: 18, width: size.width - 60, height: 20)
        toastText.opacity = 0
        root.addSublayer(toastText)

        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        // Over full-screen apps and on every desktop, so it is in the recording wherever you swipe.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    /// Puts the window in the bottom-right corner of the main screen.
    func show() {
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = Self.size
        panel.setFrameOrigin(NSPoint(x: area.maxX - size.width - 20, y: area.minY + 20))
        panel.orderFrontRegardless()
    }

    /// Redraws the hand and the state strip. Called every camera frame.
    func update(skeleton: [[CGPoint]], armed: Bool, mode: HandPose, grabbing: Bool) {
        let size = Self.size
        let accent: NSColor = grabbing ? .systemOrange : (armed ? .systemGreen : .systemGray)

        let linePath = CGMutablePath()
        let dotPath = CGMutablePath()
        for chain in skeleton {
            // The image is mirrored on screen, so the drawing is flipped to match it.
            let points = chain.map {
                CGPoint(x: (mirrored ? 1 - $0.x : $0.x) * size.width, y: $0.y * size.height)
            }
            guard let first = points.first else { continue }
            linePath.move(to: first)
            for point in points.dropFirst() { linePath.addLine(to: point) }
            for point in points {
                dotPath.addEllipse(in: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lines.path = linePath
        dots.path = dotPath
        dots.fillColor = accent.cgColor
        root.borderColor = accent.cgColor
        stateText.string = Self.stateText(armed: armed, mode: mode, grabbing: grabbing)
        CATransaction.commit()
    }

    /// Names what AirSwipe just did ("swipe left", "thumbs up: sent") for a moment.
    func flash(_ text: String) {
        toastText.string = text
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        toastBackdrop.opacity = 1
        toastText.opacity = 1
        CATransaction.commit()

        toastHide?.cancel()
        let hide = DispatchWorkItem { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            self.toastBackdrop.opacity = 0
            self.toastText.opacity = 0
            CATransaction.commit()
        }
        toastHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: hide)
    }

    private static func configure(_ layer: CATextLayer, scale: CGFloat, size: CGFloat,
                           align: CATextLayerAlignmentMode) {
        layer.contentsScale = scale
        layer.fontSize = size
        layer.font = NSFont.systemFont(ofSize: size, weight: .semibold)
        layer.foregroundColor = NSColor.white.cgColor
        layer.alignmentMode = align
        layer.truncationMode = .end
    }

    private static func stateText(armed: Bool, mode: HandPose, grabbing: Bool) -> String {
        guard armed else { return "idle · hold an open palm still to start" }
        if grabbing { return "ARMED · pinch: scrolling" }
        switch mode {
        case .openPalm: return "ARMED · open palm (circle to dictate)"
        case .oneFinger: return "ARMED · one finger (swipe)"
        case .twoFingers: return "ARMED · two fingers (scroll)"
        case .thumbsUp: return "ARMED · thumbs up"
        case .fist: return "ARMED · fist"
        case .other: return "ARMED"
        }
    }
}
