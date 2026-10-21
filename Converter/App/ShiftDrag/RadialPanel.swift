import AppKit
import AudioToolbox
import AVFAudio
import ConverterCore
import os
import SwiftUI

/// The floating window that holds the wheel. Borderless and non-activating,
/// so the app the drag started in (Finder) keeps focus and the drag carries
/// on uninterrupted.
@MainActor
final class RadialPanel: NSPanel {
    let model: RadialMenuModel
    /// Called with what was chosen and the dropped files.
    var onPick: ((RadialMenuModel.Target, [InputFile]) -> Void)?
    /// The ring changed by scrolling (so the drag watcher can follow).
    var onModeChange: ((RingMode) -> Void)?
    /// Screen point at the ring's centre while visible.
    private(set) var ringCenter: CGPoint = .zero

    let dropView: RadialDropView
    private var hideTask: Task<Void, Never>?
    /// Bumped on every show, so a fade-out that finishes after the panel
    /// was shown again doesn't hide it.
    private var generation = 0
    private var scrollMonitor: Any?
    private var scroller = RingScroller()
    private let log = Logger(subsystem: "io.github.astmirzhan.Bloom", category: "shift-drag")

    init(model: RadialMenuModel) {
        self.model = model
        let side = model.geometry.panelSide
        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        dropView = RadialDropView(model: model, frame: bounds)
        super.init(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the ring draws its own
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        let container = NSView(frame: bounds)
        let host = NSHostingView(rootView: RadialMenuView(model: model))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        dropView.autoresizingMask = [.width, .height]
        container.addSubview(host)
        container.addSubview(dropView) // on top, so drags reach it first
        contentView = container

        dropView.onDrop = { [weak self] target in self?.picked(target) }
        dropView.onScroll = { [weak self] event in self?.scrolled(event) }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the wheel on `mode`, centred on `screenPoint`, nudged inwards
    /// near screen edges so the whole ring stays visible.
    func show(_ mode: RingMode, at screenPoint: CGPoint) {
        hideTask?.cancel()
        generation += 1
        model.reset(mode: mode)
        scroller = RingScroller()
        let g = model.geometry
        let screen = NSScreen.screens.first { NSMouseInRect(screenPoint, $0.frame, false) } ?? NSScreen.main
        var center = screenPoint
        if let visible = screen?.visibleFrame {
            let margin = g.outerRadius + 8
            center.x = min(max(center.x, visible.minX + margin), visible.maxX - margin)
            center.y = min(max(center.y, visible.minY + margin), visible.maxY - margin)
        }
        ringCenter = center
        setFrame(NSRect(x: center.x - g.panelSide / 2, y: center.y - g.panelSide / 2,
                        width: g.panelSide, height: g.panelSide), display: false)
        // The wheel springs in (or just fades, with Reduce Motion) on the
        // next frame, once the window is up.
        model.isPresented = false
        alphaValue = 1
        orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.model.isPresented = true }
        }
        // Scrolls over other windows (the wheel may not be under the
        // pointer) still switch rings. Mouse monitors need no permission.
        if scrollMonitor == nil {
            scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.scrolled(event) }
            }
        }
        log.notice("wheel shown: \(mode.rawValue, privacy: .public)")
    }

    /// Shows another ring (a different key was tapped).
    func switchMode(_ mode: RingMode) {
        guard isVisible else { return }
        model.setMode(mode)
        log.notice("ring: \(mode.rawValue, privacy: .public)")
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        guard isVisible else { return }
        let shown = generation
        model.isPresented = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000) // let the wheel animate away
            guard let self, self.generation == shown else { return }
            self.orderOut(nil)
            self.model.reset()
        }
        log.notice("wheel hidden")
    }

    /// The mouse button came up. A drop on the wheel arrives a moment later,
    /// so wait before hiding rather than pulling the window out from under it.
    func dragEnded() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func scrolled(_ event: NSEvent) {
        guard isVisible, let steps = scroller.steps(for: ScrollSample(event)) else { return }
        let mode = model.mode.advanced(by: steps)
        model.setMode(mode)
        onModeChange?(mode)
        log.notice("ring (scroll): \(mode.rawValue, privacy: .public)")
    }

    private func picked(_ target: RadialMenuModel.Target) {
        let inputs = model.inputs
        log.notice("dropped on \(target.title, privacy: .public) with \(inputs.count) item(s)")
        hide()
        onPick?(target, inputs)
    }
}

// MARK: - Drop target

/// Transparent layer over the wheel that receives the drag, tracks which
/// slice is under the cursor, and reports the drop.
@MainActor
final class RadialDropView: NSView {
    /// How long the cursor rests on a group ("More Formats", "Resize")
    /// before its sub-ring opens.
    static let dwellNanoseconds: UInt64 = 140_000_000

    var onDrop: ((RadialMenuModel.Target) -> Void)?
    var onScroll: ((NSEvent) -> Void)?
    private let model: RadialMenuModel
    private var dwellTask: Task<Void, Never>?

    init(model: RadialMenuModel, frame: NSRect) {
        self.model = model
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Only now does the app read the drag's contents: the user has
        // brought the files to this window.
        if model.phase == .waiting { model.load(StatusDropView.fileURLs(in: sender)) }
        return track(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dwellTask?.cancel()
        model.clearHover()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        _ = track(sender, allowDwell: false)
        dwellTask?.cancel()
        // No target (centre, a group, outside) returns false, and the source
        // slides the files back: nothing happens.
        guard let target = model.target else { return false }
        onDrop?(target)
        return true
    }

    /// Point relative to the ring centre, y up.
    func ringPoint(for windowPoint: NSPoint) -> CGPoint {
        let local = convert(windowPoint, from: nil)
        return CGPoint(x: local.x - bounds.midX, y: local.y - bounds.midY)
    }

    private func track(_ sender: NSDraggingInfo, allowDwell: Bool = true) -> NSDragOperation {
        if let group = model.hover(at: ringPoint(for: sender.draggingLocation)), allowDwell {
            dwellTask?.cancel()
            dwellTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.dwellNanoseconds)
                guard !Task.isCancelled else { return }
                self?.model.openGroup(group)
            }
        }
        return model.target == nil ? [] : DropOperation.safe(within: sender.draggingSourceOperationMask)
    }
}

/// The operation to accept a file drop with. Held modifier keys narrow what
/// the source allows (Command means move, generic; Control means link;
/// Option means copy), and a drop outside that mask is refused. So accept
/// whichever harmless operation is allowed, and never `.move` or `.delete`:
/// Converter only reads the originals.
enum DropOperation {
    static func safe(within mask: NSDragOperation) -> NSDragOperation {
        for operation in [NSDragOperation.copy, .generic, .link] where mask.contains(operation) {
            return operation
        }
        return []
    }
}

// MARK: - Scrolling between rings

/// One scroll event's essentials (testable without a real NSEvent).
struct ScrollSample {
    var deltaY: CGFloat
    var isPrecise: Bool
    var phase: NSEvent.Phase
    var isMomentum: Bool
    var time: TimeInterval

    init(deltaY: CGFloat, isPrecise: Bool, phase: NSEvent.Phase = [], isMomentum: Bool = false, time: TimeInterval) {
        self.deltaY = deltaY
        self.isPrecise = isPrecise
        self.phase = phase
        self.isMomentum = isMomentum
        self.time = time
    }

    init(_ event: NSEvent) {
        self.init(deltaY: event.scrollingDeltaY, isPrecise: event.hasPreciseScrollingDeltas, phase: event.phase,
                  isMomentum: !event.momentumPhase.isEmpty, time: event.timestamp)
    }
}

/// Turns scrolling into ring changes: one ring per trackpad swipe (momentum
/// ignored), or one per wheel notch with a short pause between.
struct RingScroller {
    static let trackpadDistance: CGFloat = 24
    static let wheelPause: TimeInterval = 0.2

    private var accumulated: CGFloat = 0
    private var switchedThisSwipe = false
    private var lastWheelSwitch: TimeInterval = -.infinity

    /// +1 (next ring), -1 (previous) or nil (no change yet). Scrolling up
    /// (positive delta) goes to the next ring.
    mutating func steps(for sample: ScrollSample) -> Int? {
        guard !sample.isMomentum else { return nil }
        if sample.isPrecise {
            if sample.phase.contains(.began) {
                accumulated = 0
                switchedThisSwipe = false
            }
            guard !switchedThisSwipe else { return nil }
            accumulated += sample.deltaY
            guard abs(accumulated) >= Self.trackpadDistance else { return nil }
            switchedThisSwipe = true
            return accumulated > 0 ? 1 : -1
        }
        guard sample.deltaY != 0, sample.time - lastWheelSwitch >= Self.wheelPause else { return nil }
        lastWheelSwitch = sample.time
        return sample.deltaY > 0 ? 1 : -1
    }
}

/// Feedback as the pointer reaches a slice: a short sound and a tap on a
/// Force Touch trackpad.
///
/// Sounds play as system sounds. NSSound's play and stop each wait on the
/// audio server on the calling thread (tens of milliseconds, hundreds the
/// first time), which froze the wheel on every new slice;
/// AudioServicesPlaySystemSound returns at once. Each sound is written once,
/// off the main thread, to a quiet copy in Caches, since system sounds have
/// no volume of their own.
@MainActor
enum WheelSound {
    /// Which sound plays. Soft is synthesised here; the rest are macOS's own.
    enum Choice: String, CaseIterable, Identifiable, Sendable {
        case soft, tink, pop, morse, purr, bottle

        var id: String { rawValue }
        var title: String { self == .soft ? "Soft" : rawValue.capitalized }
    }

    private static var ids: [Choice: SystemSoundID] = [:]
    private static var preparing: Set<Choice> = []

    static func play(_ choice: Choice) {
        guard let id = ids[choice] else { return prepare(choice, playWhenReady: true) }
        AudioServicesPlaySystemSound(id)
    }

    /// Readies `choice` in the background so its first play is instant.
    static func prepare(_ choice: Choice, playWhenReady: Bool = false) {
        guard ids[choice] == nil, preparing.insert(choice).inserted else { return }
        Task.detached(priority: .utility) {
            let url = try? soundFile(for: choice)
            await MainActor.run {
                preparing.remove(choice)
                var id: SystemSoundID = 0
                guard let url, AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr else { return }
                ids[choice] = id
                if playWhenReady { AudioServicesPlaySystemSound(id) }
            }
        }
    }

    /// The quiet copy of `choice` in Caches, written the first time.
    nonisolated static func soundFile(for choice: Choice) throws -> URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(Bundle.main.bundleIdentifier ?? "Bloom")/Sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(choice.rawValue)-1.caf")
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        let source: AVAudioFile
        if choice == .soft {
            let wav = folder.appendingPathComponent("soft-source.wav")
            try tickWAV().write(to: wav, options: .atomic)
            source = try AVAudioFile(forReading: wav)
        } else {
            source = try AVAudioFile(forReading: URL(fileURLWithPath: "/System/Library/Sounds/\(choice.title).aiff"))
        }
        let format = source.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(source.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try source.read(into: buffer)
        // Quieter than an alert: these play many times a second.
        let gain: Float = choice == .soft ? 0.5 : 0.3
        for channel in 0..<Int(format.channelCount) {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(buffer.frameLength) { samples[frame] *= gain }
        }
        let temporary = folder.appendingPathComponent("\(choice.rawValue)-\(UUID().uuidString).caf")
        do {
            let output = try AVAudioFile(forWriting: temporary, settings: format.settings)
            try output.write(from: buffer)
        }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: temporary, to: url)
        return url
    }

    /// The trackpad's "alignment" tap, as when a shape snaps to a guide.
    /// Felt only with a finger on a Force Touch trackpad, which a drag has.
    static func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Two pure tones a fifth apart (E6 and B6) with a smooth 4 ms rise and
    /// a gentle decay, faded to silence at the end so nothing clicks: 90 ms
    /// of 16-bit mono at 48 kHz, as WAV.
    nonisolated static func tickWAV() -> Data {
        let rate = 48_000, frames = rate * 90 / 1000
        var pcm = Data(capacity: frames * 2)
        for i in 0..<frames {
            let t = Double(i) / Double(rate)
            let rise = t < 0.004 ? pow(sin(.pi / 2 * t / 0.004), 2) : 1
            let tail = min(1, Double(frames - i) / Double(rate / 100)) // last 10 ms
            let tone = sin(2 * .pi * 1_318.5 * t) + 0.3 * sin(2 * .pi * 1_975.5 * t) * exp(-t / 0.012)
            let sample = Int16(0.45 * rise * tail * exp(-t / 0.022) * tone * Double(Int16.max))
            withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + pcm.count))
        wav.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        wav.append(contentsOf: Array("data".utf8)); append(UInt32(pcm.count))
        return wav + pcm
    }
}
