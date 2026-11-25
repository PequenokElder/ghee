import SwiftUI

/// Butter palette: cream backgrounds, golden accents, toasted-brown text.
enum Butter {
    static let cream     = Color(red: 0.97, green: 0.88, blue: 0.62)
    static let butter    = Color(red: 0.98, green: 0.82, blue: 0.38)
    static let gold      = Color(red: 0.93, green: 0.66, blue: 0.14)
    static let deepGold  = Color(red: 0.80, green: 0.50, blue: 0.06)
    static let toast     = Color(red: 0.36, green: 0.21, blue: 0.07)
    static let toastSoft = Color(red: 0.36, green: 0.21, blue: 0.07).opacity(0.65)
    static let berry     = Color(red: 0.70, green: 0.20, blue: 0.08)
    static let sage      = Color(red: 0.30, green: 0.48, blue: 0.16)

    static let background = LinearGradient(colors: [cream, Color(red: 0.88, green: 0.68, blue: 0.28)],
                                           startPoint: .top, endPoint: .bottom)
}

@main
struct GuitarMonitorApp: App {
    @StateObject private var engine = GuitarEngine()
    @StateObject private var quips = QuipBoard()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .environmentObject(quips)
                .frame(width: 820, height: 640)
                .preferredColorScheme(.light)
                .tint(Butter.deepGold)
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @EnvironmentObject var engine: GuitarEngine
    @EnvironmentObject var quips: QuipBoard

    var body: some View {
        VStack(spacing: 18) {
            header
            devicePanel
            meter
            HStack(alignment: .top, spacing: 10) {
                Knob(title: "Churn", subtitle: "Input", value: $engine.inputGain, range: 0...3, defaultValue: 1) { String(format: "%+.0f dB", 20 * log10(max($0, 0.001))) }
                Knob(title: "Soften", subtitle: "Compression", value: $engine.compression, range: 0...1, defaultValue: 0) { "\(Int($0 * 100))%" }
                Knob(title: "Brown Butter", subtitle: "Drive", value: $engine.drive, range: 0...1, defaultValue: 0) { "\(Int($0 * 100))%" }
                Knob(title: "Stick", subtitle: "Bass", value: $engine.bass, range: -12...12, defaultValue: 0) { String(format: "%+.0f dB", $0) }
                Knob(title: "Spread", subtitle: "Mid", value: $engine.mid, range: -12...12, defaultValue: 0) { String(format: "%+.0f dB", $0) }
                Knob(title: "Sizzle", subtitle: "Treble", value: $engine.treble, range: -12...12, defaultValue: 0) { String(format: "%+.0f dB", $0) }
                Knob(title: "Swirl", subtitle: "Chorus", value: $engine.chorusMix, range: 0...1, defaultValue: 0) { "\(Int($0 * 100))%" }
                Knob(title: "Melt", subtitle: "Reverb", value: $engine.reverbMix, range: 0...1, defaultValue: 0) { "\(Int($0 * 100))%" }
                Knob(title: "Slather", subtitle: "Volume", value: $engine.volume, range: 0...1, defaultValue: 0.7) { "\(Int($0 * 100))%" }
            }
            delayPanel
            if let note = engine.deviceNote {
                Text(note).font(.caption).foregroundStyle(Butter.berry).multilineTextAlignment(.center)
            }
            Text(quips.line)
                .font(.system(.callout, design: .rounded).italic())
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Butter.toast.opacity(0.10)))
                .animation(.easeInOut(duration: 0.2), value: quips.line)
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .foregroundStyle(Butter.toast)
        .background(Butter.background.ignoresSafeArea())
    }

    private var delayPanel: some View {
        let seconds = engine.division.seconds(bpm: engine.bpm)
        let capped = seconds > DelayLimits.maxSeconds
        return HStack(spacing: 18) {
            Knob(title: "Drizzle", subtitle: "Delay", value: $engine.delayMix, range: 0...1, defaultValue: 0) { "\(Int($0 * 100))%" }
                .frame(width: 100)
            Knob(title: "Layers", subtitle: "Feedback", value: $engine.delayFeedback, range: 0...1, defaultValue: 0.35) { "\(Int($0 * 100))%" }
                .frame(width: 100)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Note").foregroundStyle(Butter.toastSoft).frame(width: 48, alignment: .leading)
                    Picker("Delay note length", selection: $engine.division) {
                        ForEach(DelayDivision.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                HStack(spacing: 10) {
                    Text("Tempo").foregroundStyle(Butter.toastSoft).frame(width: 48, alignment: .leading)
                    TextField("BPM", value: $engine.bpm, format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .accessibilityLabel("Tempo in beats per minute")
                    Stepper("", value: $engine.bpm, in: DelayLimits.bpmRange, step: 1)
                        .labelsHidden()
                    Text("BPM").foregroundStyle(Butter.toastSoft)
                    Button("Tap") { engine.tapTempo() }
                        .fixedSize()
                        .help("Tap along to set the tempo")
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int((min(seconds, DelayLimits.maxSeconds) * 1000).rounded())) ms")
                    .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                Text(capped ? "capped at 2 s" : "between repeats")
                    .font(.caption).foregroundStyle(capped ? Butter.berry : Butter.toastSoft)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Butter.toast.opacity(0.10)))
    }

    private var header: some View {
        HStack {
            Text("Ghee")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            Text(quips.tagline)
                .font(.system(.callout, design: .rounded)).italic()
                .foregroundStyle(Butter.toastSoft)
                .padding(.top, 8)
            Spacer()
            if engine.isRunning, let ms = engine.latencyMs {
                Label(String(format: "≈ %.1f ms round trip", ms), systemImage: "waveform")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(ms < 10 ? Butter.sage : ms < 20 ? Butter.deepGold : Butter.berry)
            } else {
                Text("Stopped").foregroundStyle(Butter.toastSoft)
            }
        }
    }

    private var devicePanel: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Input").foregroundStyle(Butter.toastSoft)
                Picker("Input device", selection: $engine.deviceName) {
                    Text("System Default").tag("")
                    ForEach(engine.interfaces) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
            }
            GridRow {
                Text("Buffer").foregroundStyle(Butter.toastSoft)
                Picker("Buffer size", selection: $engine.bufferFrames) {
                    ForEach(GuitarEngine.bufferOptions, id: \.self) { Text("\($0) samples").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    private var meter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Butter.toast.opacity(0.14))
                Capsule()
                    .fill(engine.level > 0.9 ? Butter.berry : engine.level > 0.6 ? Butter.deepGold : Butter.gold)
                    .frame(width: max(4, geo.size.width * CGFloat(min(engine.level, 1))))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(min(engine.level, 1) * 100)) percent")
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button(action: engine.toggle) {
                Text(engine.isRunning ? "Take Off the Heat" : "Heat the Pan")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(engine.isRunning ? Butter.berry : Butter.deepGold)
            .keyboardShortcut(.space, modifiers: [])

            if let error = engine.errorMessage {
                Text(error).font(.callout).foregroundStyle(Butter.berry).multilineTextAlignment(.center)
                if engine.needsMicPermission {
                    Button("Open Microphone Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                }
            } else {
                Text("Use headphones — speakers next to a live input will feed back.")
                    .font(.caption).foregroundStyle(Butter.toastSoft)
            }
        }
    }
}

/// Rotary knob: drag vertically to change, double-click to reset.
struct Knob: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    let format: (Double) -> String

    @EnvironmentObject private var quips: QuipBoard
    @GestureState private var dragStart: Double? = nil

    private var normalized: Double { (value - range.lowerBound) / (range.upperBound - range.lowerBound) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.62), Butter.butter, Butter.gold],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 2, endRadius: 44))
                    .overlay(Circle().stroke(Butter.toast.opacity(0.45), lineWidth: 1.5))
                    .shadow(color: Butter.toast.opacity(0.25), radius: 3, y: 2)
                Circle().trim(from: 0, to: 0.75)
                    .stroke(Butter.toast.opacity(0.18), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(135)).padding(-6)
                Circle().trim(from: 0, to: 0.75 * normalized)
                    .stroke(Butter.deepGold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(135)).padding(-6)
                Capsule().fill(Butter.toast)
                    .frame(width: 3.5, height: 16)
                    .offset(y: -14)
                    .rotationEffect(.degrees(-135 + 270 * normalized))
            }
            .frame(width: 56, height: 56)
            .padding(6)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .updating($dragStart) { _, state, _ in
                        if state == nil { state = value }
                    }
                    .onChanged { g in
                        let span = range.upperBound - range.lowerBound
                        let start = dragStart ?? value
                        let new = min(range.upperBound, max(range.lowerBound, start - g.translation.height / 150 * span))
                        value = new
                        quips.say(title, normalized: (new - range.lowerBound) / span)
                    }
            )
            .onTapGesture(count: 2) {
                value = defaultValue
                quips.say(title, normalized: (defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound))
            }

            VStack(spacing: 1) {
                Text(title).font(.system(.caption, design: .rounded).weight(.bold))
                Text(subtitle).font(.system(size: 9, weight: .semibold)).textCase(.uppercase).tracking(0.6)
                    .foregroundStyle(Butter.toastSoft)
            }
            Text(format(value)).font(.caption2.monospacedDigit()).foregroundStyle(Butter.toastSoft)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(subtitle) (\(title))")
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? step : -step)))
        }
    }
}
