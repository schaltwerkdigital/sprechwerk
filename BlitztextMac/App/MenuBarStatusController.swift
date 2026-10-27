import AppKit

enum MenuBarStatus: Equatable {
    case idle
    case recording(WorkflowType)
    case processing(WorkflowType)
    case success(WorkflowType?)
    case error(WorkflowType?)
    /// Not pasted on purpose, e.g. because another field has the focus; the text is on the clipboard.
    case copied(WorkflowType?)
    /// A meeting is being recorded; shown while no dictation is active.
    case meeting
}

@MainActor
final class MenuBarStatusController {
    private weak var button: NSStatusBarButton?
    private var animationTimer: Timer?
    private var animationFrame = 0
    private var currentStatus: MenuBarStatus = .idle
    /// Small dot on the idle icon while a release note is unread.
    var showsNewBadge = false {
        didSet {
            guard oldValue != showsNewBadge else { return }
            renderCurrentStatus()
        }
    }

    func attach(to button: NSStatusBarButton) {
        self.button = button
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        renderCurrentStatus()
    }

    func update(to status: MenuBarStatus) {
        currentStatus = status
        animationFrame = 0
        configureAnimationIfNeeded()
        renderCurrentStatus()
    }

    private func configureAnimationIfNeeded() {
        stopAnimation()

        switch currentStatus {
        case .recording:
            startAnimation(interval: 0.12)
        case .processing:
            startAnimation(interval: 0.18)
        default:
            break
        }
    }

    private func startAnimation(interval: TimeInterval) {
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(animationTimer!, forMode: .common)
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func tick() {
        animationFrame = (animationFrame + 1) % 4
        renderCurrentStatus()
    }

    private func renderCurrentStatus() {
        guard let button else { return }
        var image = MenuBarStatusIconRenderer.makeImage(for: currentStatus, frame: animationFrame)
        if showsNewBadge, case .idle = currentStatus {
            image = MenuBarStatusIconRenderer.withNewDot(image)
        }
        button.image = image
        button.image?.isTemplate = true
        // A running meeting turns the symbol red, so it stands out next to the microphone
        // indicator that other apps keep on as well.
        button.contentTintColor = currentStatus == .meeting ? .systemRed : nil
        button.toolTip = tooltip(for: currentStatus)
    }

    private func tooltip(for status: MenuBarStatus) -> String {
        switch status {
        case .idle:
            return "Sprechwerk ist bereit"
        case .recording(let type):
            return "\(type.displayName): Aufnahme läuft"
        case .processing(let type):
            return "\(type.displayName): Verarbeitung läuft"
        case .success(let type):
            if let type {
                return "\(type.displayName): Fertig"
            }
            return "Sprechwerk: Fertig"
        case .copied:
            return "Sprechwerk: Text liegt in der Zwischenablage"
        case .error(let type):
            if let type {
                return "\(type.displayName): Fehler"
            }
            return "Sprechwerk: Fehler"
        case .meeting:
            return "Meeting: Aufnahme l\u{00E4}uft"
        }
    }

    deinit {
        animationTimer?.invalidate()
    }
}

private enum MenuBarStatusIconRenderer {
    static func withNewDot(_ base: NSImage) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { bounds in
            base.draw(in: bounds)
            let diameter: CGFloat = 5.5
            let dot = NSRect(x: bounds.maxX - diameter, y: bounds.maxY - diameter, width: diameter, height: diameter)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
    }

    static func makeImage(for status: MenuBarStatus, frame: Int) -> NSImage {
        if case .idle = status, let baseImage = baseTemplateImage() {
            return baseImage
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            drawBaseIcon(in: bounds, status: status, frame: frame)

            switch status {
            case .recording(let type):
                drawActivityBadge(
                    type: type,
                    systemName: badgeSymbol(for: type),
                    in: bounds,
                    frame: frame,
                    phase: .recording
                )
            case .processing(let type):
                drawActivityBadge(
                    type: type,
                    systemName: badgeSymbol(for: type),
                    in: bounds,
                    frame: frame,
                    phase: .processing
                )
            case .success:
                drawBadge(systemName: "checkmark", in: bounds, fillOpacity: 1.0)
            case .copied:
                drawBadge(systemName: "doc.on.clipboard", in: bounds, fillOpacity: 1.0)
            case .error:
                drawBadge(systemName: "exclamationmark", in: bounds, fillOpacity: 1.0)
            case .meeting:
                drawBadge(systemName: "record.circle", in: bounds, fillOpacity: 1.0)
            default:
                break
            }

            return true
        }
        image.isTemplate = true
        image.size = size
        return image
    }

    private enum ActivityPhase {
        case recording
        case processing
    }

    /// Sprechwerk's mark, the same as menubar_icon.png: the Schaltwerk speech bubble with four
    /// sound bars cut out where the logo has "SW". While recording the bars fill and pulse.
    private static func drawBaseIcon(in bounds: CGRect, status: MenuBarStatus, frame: Int) {
        let baseAlpha = baseAlphaValues(for: status, frame: frame)
        let bubble = BubbleGeometry(in: bounds.insetBy(dx: 1, dy: 1))
        NSColor.black.setFill()
        bubble.path().fill()

        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.compositingOperation = .destinationOut
        for (index, bar) in bubble.bars().enumerated() {
            NSColor.black.withAlphaComponent(baseAlpha[index]).setFill()
            NSBezierPath(roundedRect: bar, xRadius: bar.width / 2, yRadius: bar.width / 2).fill()
        }
        context.restoreGraphicsState()
    }

    /// logo-sw-bubble-fullcolor-positive.svg (61.68 x 52.97), fitted into a rect.
    private struct BubbleGeometry {
        static let size = CGSize(width: 61.68, height: 52.97)
        let scale: CGFloat
        let originX: CGFloat
        let top: CGFloat

        init(in rect: CGRect) {
            scale = min(rect.width / Self.size.width, rect.height / Self.size.height)
            originX = rect.midX - Self.size.width * scale / 2
            top = rect.midY + Self.size.height * scale / 2
        }

        /// SVG coordinates (y down) to AppKit (y up).
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: originX + x * scale, y: top - y * scale)
        }

        func path() -> NSBezierPath {
            let path = NSBezierPath()
            path.move(to: point(55.7, 52.97))
            path.line(to: point(16.07, 52.97))
            path.curve(to: point(0, 36.91), controlPoint1: point(7.23, 52.97), controlPoint2: point(0, 45.74))
            path.line(to: point(0, 16.07))
            path.curve(to: point(16.07, 0), controlPoint1: point(0, 7.23), controlPoint2: point(7.23, 0))
            path.line(to: point(36.91, 0))
            path.curve(to: point(52.97, 16.07), controlPoint1: point(45.74, 0), controlPoint2: point(52.97, 7.23))
            path.line(to: point(52.97, 36.91))
            path.curve(to: point(61.68, 52.98), controlPoint1: point(52.97, 49.42), controlPoint2: point(61.68, 52.98))
            path.close()
            return path
        }

        /// Four bars centered on the rounded square, bolder than in the app icon so they
        /// still read at menu bar size.
        func bars() -> [CGRect] {
            let heights: [CGFloat] = [14, 26, 19.5, 9]
            let width: CGFloat = 5.2
            let gap: CGFloat = 3.0
            let total = CGFloat(heights.count) * width + CGFloat(heights.count - 1) * gap
            let center = point(Self.size.height / 2, Self.size.height / 2)
            return heights.enumerated().map { index, height in
                CGRect(
                    x: center.x + (CGFloat(index) * (width + gap) - total / 2) * scale,
                    y: center.y - height * scale / 2,
                    width: width * scale,
                    height: height * scale
                )
            }
        }
    }

    /// The badge sits on the bubble's tail; a thin gap around it keeps the two apart.
    private static func clearBadgeArea(in bounds: CGRect) {
        let badgeSize: CGFloat = 7.5
        let badgeRect = CGRect(x: bounds.maxX - badgeSize - 0.8, y: bounds.minY + 0.8, width: badgeSize, height: badgeSize)
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.compositingOperation = .destinationOut
        NSColor.black.setFill()
        NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1.4, dy: -1.4)).fill()
        context.restoreGraphicsState()
    }

    private static func drawActivityBadge(
        type: WorkflowType,
        systemName: String,
        in bounds: CGRect,
        frame: Int,
        phase: ActivityPhase
    ) {
        clearBadgeArea(in: bounds)
        let badgeSize: CGFloat = 7.5
        let badgeRect = CGRect(
            x: bounds.maxX - badgeSize - 0.8,
            y: bounds.minY + 0.8,
            width: badgeSize,
            height: badgeSize
        )

        let badgeOpacity: CGFloat
        let haloOpacity: CGFloat

        switch phase {
        case .recording:
            let values: [CGFloat]
            switch type {
            case .tapTalk, .localTapTalk:
                values = [0.74, 1.0, 0.82, 0.92]
            case .textImprover:
                values = [0.66, 0.84, 1.0, 0.8]
            case .dampfAblassen:
                values = [1.0, 0.76, 0.94, 0.68]
            case .emojiText:
                values = [0.8, 0.92, 0.7, 1.0]
            }
            badgeOpacity = values[frame % values.count]
            haloOpacity = 0.14 + (CGFloat(frame % 4) * 0.04)
        case .processing:
            let values: [CGFloat]
            switch type {
            case .tapTalk, .localTapTalk:
                values = [0.58, 0.72, 0.9, 0.72]
            case .textImprover:
                values = [0.48, 0.68, 0.92, 0.84]
            case .dampfAblassen:
                values = [0.84, 0.62, 0.9, 0.56]
            case .emojiText:
                values = [0.54, 0.76, 0.88, 0.68]
            }
            badgeOpacity = values[frame % values.count]
            haloOpacity = 0.12 + (CGFloat((frame + 2) % 4) * 0.03)
        }

        let haloInset = phase == .recording ? -0.8 : -0.45
        let haloRect = badgeRect.insetBy(dx: haloInset, dy: haloInset)
        let haloPath = NSBezierPath(ovalIn: haloRect)
        NSColor.black.withAlphaComponent(haloOpacity).setStroke()
        haloPath.lineWidth = phase == .recording ? 0.9 : 0.75
        haloPath.stroke()

        drawBadge(systemName: systemName, in: bounds, fillOpacity: badgeOpacity, clearsArea: false)

        if phase == .processing {
            drawProcessingDot(around: badgeRect, frame: frame)
        }
    }

    private static func drawBadge(systemName: String, in bounds: CGRect, fillOpacity: CGFloat, clearsArea: Bool = true) {
        if clearsArea { clearBadgeArea(in: bounds) }
        let badgeSize: CGFloat = 7.5
        let badgeRect = CGRect(
            x: bounds.maxX - badgeSize - 0.8,
            y: bounds.minY + 0.8,
            width: badgeSize,
            height: badgeSize
        )

        let badgePath = NSBezierPath(ovalIn: badgeRect)
        NSColor.black.withAlphaComponent(fillOpacity).setFill()
        badgePath.fill()

        guard let symbol = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: nil
        ) else {
            return
        }

        let config = NSImage.SymbolConfiguration(pointSize: 5.5, weight: .bold)
        let configuredSymbol = symbol.withSymbolConfiguration(config) ?? symbol
        let symbolRect = badgeRect.insetBy(dx: 1.2, dy: 1.2)
        configuredSymbol.draw(
            in: symbolRect,
            from: .zero,
            operation: .destinationOut,
            fraction: 1.0
        )
    }

    private static func drawProcessingDot(around badgeRect: CGRect, frame: Int) {
        let orbitPoints: [CGPoint] = [
            CGPoint(x: badgeRect.midX, y: badgeRect.maxY + 0.35),
            CGPoint(x: badgeRect.maxX + 0.35, y: badgeRect.midY),
            CGPoint(x: badgeRect.midX, y: badgeRect.minY - 0.35),
            CGPoint(x: badgeRect.minX - 0.35, y: badgeRect.midY),
        ]
        let point = orbitPoints[frame % orbitPoints.count]
        let dotRect = CGRect(x: point.x - 0.85, y: point.y - 0.85, width: 1.7, height: 1.7)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSColor.black.withAlphaComponent(0.92).setFill()
        dotPath.fill()
    }

    private static func baseAlphaValues(for status: MenuBarStatus, frame: Int) -> [CGFloat] {
        switch status {
        case .idle, .meeting:
            return [1.0, 0.82, 0.64, 0.46]
        case .recording(let type):
            return recordingAlphaValues(for: type, frame: frame)
        case .processing(let type):
            return processingAlphaValues(for: type, frame: frame)
        case .success, .copied:
            return [1.0, 0.9, 0.78, 0.62]
        case .error:
            return [1.0, 0.7, 0.52, 0.36]
        }
    }

    private static func recordingAlphaValues(for type: WorkflowType, frame: Int) -> [CGFloat] {
        switch type {
        case .tapTalk, .localTapTalk:
            let patterns: [[CGFloat]] = [
                [1.0, 0.42, 0.28, 0.18],
                [0.82, 1.0, 0.4, 0.24],
                [0.58, 0.86, 1.0, 0.36],
                [0.4, 0.62, 0.88, 1.0],
            ]
            return patterns[frame % patterns.count]
        case .textImprover:
            let patterns: [[CGFloat]] = [
                [1.0, 0.88, 0.52, 0.3],
                [0.86, 1.0, 0.84, 0.44],
                [0.64, 0.9, 1.0, 0.68],
                [0.48, 0.68, 0.9, 1.0],
            ]
            return patterns[frame % patterns.count]
        case .dampfAblassen:
            let patterns: [[CGFloat]] = [
                [1.0, 0.44, 0.78, 1.0],
                [0.86, 0.34, 0.96, 0.9],
                [0.72, 0.3, 1.0, 0.78],
                [0.94, 0.4, 0.74, 1.0],
            ]
            return patterns[frame % patterns.count]
        case .emojiText:
            let patterns: [[CGFloat]] = [
                [1.0, 0.7, 0.46, 0.28],
                [0.78, 1.0, 0.72, 0.42],
                [0.52, 0.82, 1.0, 0.66],
                [0.36, 0.58, 0.84, 1.0],
            ]
            return patterns[frame % patterns.count]
        }
    }

    private static func processingAlphaValues(for type: WorkflowType, frame: Int) -> [CGFloat] {
        switch type {
        case .tapTalk, .localTapTalk:
            let patterns: [[CGFloat]] = [
                [1.0, 0.84, 0.68, 0.52],
                [0.92, 0.8, 0.64, 0.5],
                [0.84, 0.74, 0.6, 0.48],
                [0.92, 0.8, 0.64, 0.5],
            ]
            return patterns[frame % patterns.count]
        case .textImprover:
            let patterns: [[CGFloat]] = [
                [1.0, 0.76, 0.52, 0.34],
                [0.86, 1.0, 0.74, 0.48],
                [0.7, 0.88, 1.0, 0.72],
                [0.56, 0.74, 0.9, 1.0],
            ]
            return patterns[frame % patterns.count]
        case .dampfAblassen:
            let patterns: [[CGFloat]] = [
                [0.9, 0.5, 0.72, 1.0],
                [0.78, 0.44, 0.9, 1.0],
                [0.66, 0.38, 1.0, 0.88],
                [0.84, 0.48, 0.78, 1.0],
            ]
            return patterns[frame % patterns.count]
        case .emojiText:
            let patterns: [[CGFloat]] = [
                [1.0, 0.8, 0.58, 0.4],
                [0.88, 1.0, 0.78, 0.54],
                [0.74, 0.9, 1.0, 0.7],
                [0.6, 0.76, 0.92, 1.0],
            ]
            return patterns[frame % patterns.count]
        }
    }

    private static func badgeSymbol(for type: WorkflowType) -> String {
        switch type {
        case .tapTalk:
            return "mic.fill"
        case .localTapTalk:
            return "lock.fill"
        case .textImprover:
            return "text.alignleft"
        case .dampfAblassen:
            return "flame.fill"
        case .emojiText:
            return "face.smiling"
        }
    }

    private static func baseTemplateImage() -> NSImage? {
        guard let image = NSImage(named: "menubar_icon") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
