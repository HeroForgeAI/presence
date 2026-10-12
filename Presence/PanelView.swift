import AppKit
import Carbon.HIToolbox
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: AppModel
    var showsWordmark: Bool
    var clearsWindow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsWordmark {
                Text("Presence")
                    .font(.headline)
            }
            preview
            settings
            actions
            statusLine
        }
        .padding(.horizontal, 20)
        .padding(.top, showsWordmark ? 16 : 12)
        .padding(.bottom, 16)
        .frame(width: 368)
        .background {
            WindowGlass(amount: model.glass, clearsWindow: clearsWindow)
        }
        .background(ChordMonitor(active: model.listening != nil) { event in
            guard !event.isARepeat else { return }
            if event.keyCode == UInt16(kVK_Escape) {
                model.cancelListening()
                return
            }
            model.assignChord(keyCode: event.keyCode, flags: event.modifierFlags)
        })
    }

    private var preview: some View {
        Color.black
            .frame(maxWidth: .infinity)
            .frame(height: 185)
            .overlay {
                if let preview = model.preview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if let badge = previewBadge {
                    chip(badge).padding(10)
                }
            }
            .overlay(alignment: .topTrailing) {
                status.padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
    }

    private var status: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            chip(statusTitle(now: context.date), dot: model.isRecording)
        }
    }

    private func chip(_ title: String, dot: Bool = false) -> some View {
        HStack(spacing: 5) {
            if dot {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
            }
            Text(title)
                .monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private func statusTitle(now: Date) -> String {
        switch model.mode {
        case .recording(let endsAt):
            let remaining = max(0, Int(ceil(endsAt.timeIntervalSince(now))))
            return "\(remaining)s"
        case .ready:
            return "Ready"
        case .away:
            return "Away"
        case .live:
            return "Live"
        }
    }

    private var previewBadge: String? {
        switch model.mode {
        case .ready: return "Take"
        case .away: return "Loop"
        case .live, .recording: return nil
        }
    }

    private var settings: some View {
        VStack(spacing: 0) {
            backgroundRow
            rowDivider
            frameRow
            rowDivider
            glassRow
            rowDivider
            lengthRow
            rowDivider
            cameraRow
            rowDivider
            shortcutRow("Record", chord: model.recordChord, role: .record)
            rowDivider
            shortcutRow("Step away", chord: model.stepChord, role: .step)
        }
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 14)
    }

    private var backgroundRow: some View {
        HStack(spacing: 12) {
            Text("Background")
            Spacer(minLength: 12)
            Menu {
                Button("None") { model.selectBackground(nil) }
                if !model.yourBackgrounds.isEmpty {
                    Section("On this Mac") {
                        ForEach(model.yourBackgrounds) { item in
                            backgroundButton(item)
                        }
                    }
                }
                if !model.libraryBackgrounds.isEmpty {
                    Section("Zoom’s library") {
                        ForEach(model.libraryBackgrounds) { item in
                            backgroundButton(item)
                        }
                    }
                }
                Divider()
                Button("Choose a file…") { model.chooseBackgroundFile() }
            } label: {
                HStack(spacing: 6) {
                    if let id = model.backgroundID, let thumb = model.thumbs[id] {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Text(model.backgroundTitle)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 190, alignment: .trailing)
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .disabled(model.isRecording || model.isAway)
    }

    private func backgroundButton(_ item: ZoomBackground) -> some View {
        Button {
            model.selectBackground(item.id)
        } label: {
            if model.backgroundID == item.id {
                Text("\(item.title) ✓")
            } else {
                Text(item.title)
            }
        }
    }

    private var frameRow: some View {
        sliderRow("Frame", low: "Wider", high: "Closer", value: Binding(
            get: { model.frameZoom },
            set: { model.setFrameZoom($0) }
        ), range: 1...2)
        .disabled(model.isRecording || model.isAway)
    }

    private var glassRow: some View {
        sliderRow("Glass", low: "Off", high: "Clear", value: Binding(
            get: { model.glass },
            set: { model.setGlass($0) }
        ), range: 0...1)
    }

    private func sliderRow(_ title: String, low: String, high: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            HStack(spacing: 10) {
                Text(low)
                Slider(value: value, in: range)
                Text(high)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var lengthRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Length")
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Length", selection: $model.duration) {
                ForEach(TakeDuration.allCases) { duration in
                    Text(duration.label).tag(duration)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .disabled(model.isRecording || model.isAway)
    }

    private var cameraRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.cameras.isEmpty {
                Text(model.cameraNote ?? "Looking for a camera.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    Text("Camera")
                    Spacer(minLength: 12)
                    Picker("Camera", selection: Binding(
                        get: { model.cameraID ?? "" },
                        set: { model.selectCamera($0) }
                    )) {
                        ForEach(model.cameras) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 210, alignment: .trailing)
                }
            }
            if let note = model.cameraNote, !model.cameras.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if note.contains("camera") {
                    Button("Open Camera settings") { model.openCameraSettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .padding(.vertical, model.cameraNote == nil ? 0 : 6)
        .disabled(model.isRecording || model.isAway)
    }

    private func shortcutRow(_ title: String, chord: KeyChord, role: ChordRole) -> some View {
        let armed = model.listening == role
        return Button {
            model.toggleListening(role)
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Text(armed ? "Press keys" : chord.label)
                    .font(.body)
                    .foregroundStyle(armed ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 72, minHeight: 26)
                    .background(Color.primary.opacity(armed ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }

    private var actions: some View {
        VStack(spacing: 6) {
            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle)
            if let secondaryTitle {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var primaryTitle: String {
        switch model.mode {
        case .recording: return "Cancel"
        case .away: return "I’m back"
        case .ready: return "Step away"
        case .live: return model.hasTake ? "Step away" : "Record"
        }
    }

    private var secondaryTitle: String? {
        switch model.mode {
        case .ready: return "Record again"
        case .live where model.hasTake: return "Record again"
        default: return nil
        }
    }

    private func primaryAction() {
        switch model.mode {
        case .recording: model.recordPressed()
        case .away: model.stepPressed()
        case .ready: model.stepPressed()
        case .live where model.hasTake: model.stepPressed()
        case .live: model.recordPressed()
        }
    }

    private func secondaryAction() {
        model.recordPressed()
    }

    private var statusLine: some View {
        VStack(spacing: 3) {
            if model.listening != nil, model.chordNote == nil {
                Text("Esc cancels")
            }
            if let chordNote = model.chordNote {
                Text(chordNote)
            }
            if model.backgroundID != nil {
                Text("Turn Zoom’s background off.")
            }
            if let publishNote = model.publishNote {
                if model.publishOpensSettings {
                    Button(publishNote) { model.openExtensionSettings() }
                        .buttonStyle(.plain)
                } else {
                    Text(publishNote)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WindowGlass: View {
    var amount: Double
    var clearsWindow: Bool

    var body: some View {
        ZStack {
            if amount < 0.02 {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(amount > 0.66 ? .clear : .regular, in: Rectangle())
                Color.black.opacity(0.22 * (1 - amount) + 0.06)
            }
        }
        .ignoresSafeArea()
        .background(WindowSurface(clear: clearsWindow && amount >= 0.02))
    }
}

private struct WindowSurface: NSViewRepresentable {
    var clear: Bool

    func makeNSView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.clear = clear
        return view
    }

    func updateNSView(_ view: SurfaceView, context: Context) {
        view.clear = clear
    }
}

private final class SurfaceView: NSView {
    var clear = false {
        didSet { apply() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    override func layout() {
        super.layout()
        apply()
    }

    private func apply() {
        guard let window else { return }
        let opaque = !clear
        if window.isOpaque != opaque {
            window.isOpaque = opaque
        }
        let color: NSColor = clear ? .clear : .windowBackgroundColor
        if window.backgroundColor != color {
            window.backgroundColor = color
        }
        if window.titlebarAppearsTransparent != clear {
            window.titlebarAppearsTransparent = clear
        }
        let separator: NSTitlebarSeparatorStyle = clear ? .none : .automatic
        if window.titlebarSeparatorStyle != separator {
            window.titlebarSeparatorStyle = separator
        }
        if clear {
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

private struct ChordMonitor: NSViewRepresentable {
    var active: Bool
    var onKey: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sync(active: active, onKey: onKey)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.sync(active: false, onKey: { _ in })
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
        var onKey: ((NSEvent) -> Void)?

        func sync(active: Bool, onKey: @escaping (NSEvent) -> Void) {
            self.onKey = onKey
            if !active {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
                return
            }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.onKey?(event)
                return nil
            }
        }
    }
}
