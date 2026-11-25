import Foundation

/// Note lengths for the tempo-synced delay, measured in quarter-note beats.
enum DelayDivision: Int, CaseIterable, Identifiable {
    case quarter, dottedQuarter, eighth, dottedEighth, tripletEighth, sixteenth, dottedSixteenth, tripletSixteenth

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .quarter: "1/4"
        case .dottedQuarter: "Dotted 1/4"
        case .eighth: "1/8"
        case .dottedEighth: "Dotted 1/8"
        case .tripletEighth: "1/8 Triplet"
        case .sixteenth: "1/16"
        case .dottedSixteenth: "Dotted 1/16"
        case .tripletSixteenth: "1/16 Triplet"
        }
    }

    var beats: Double {
        switch self {
        case .quarter: 1
        case .dottedQuarter: 1.5
        case .eighth: 0.5
        case .dottedEighth: 0.75
        case .tripletEighth: 1.0 / 3
        case .sixteenth: 0.25
        case .dottedSixteenth: 0.375
        case .tripletSixteenth: 1.0 / 6
        }
    }

    /// Delay time in seconds at the given tempo.
    func seconds(bpm: Double) -> Double { 60 / max(bpm, 1) * beats }
}

enum DelayLimits {
    static let bpmRange: ClosedRange<Double> = 40...240
    /// Apple's delay unit tops out at 2 seconds.
    static let maxSeconds = 2.0
}

import AVFoundation
import AudioToolbox

/// Tempo-synced delay as an in-process Audio Unit. Unlike Apple's delay unit, the dry
/// signal is never reduced: echoes are *added* on top of it, so your live guitar stays
/// at full level. Time changes glide so retiming doesn't click.
final class DelayAU: AUAudioUnit {
    final class State {
        var time: Float = 0.375        // seconds
        var feedback: Float = 0.3      // 0...0.9
        var mix: Float = 0             // 0...1, level of echoes added over the dry signal
        var sampleRate: Float = 48000
        static let size = 1 << 18      // 262,144 samples: > 2 s even at 96 kHz
        var buffers: [UnsafeMutablePointer<Float>] = (0..<2).map { _ in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: State.size)
            p.initialize(repeating: 0, count: State.size); return p
        }
        var damp: [Float] = [0, 0]
        var write = 0
        var currentDelay: Float = 0
        deinit { buffers.forEach { $0.deallocate() } }
        func reset() {
            buffers.forEach { $0.update(repeating: 0, count: State.size) }
            damp = [0, 0]; write = 0; currentDelay = time * sampleRate
        }
    }

    let state = State()
    var time: Float {
        get { state.time }
        set { state.time = min(max(newValue, 0.001), Float(DelayLimits.maxSeconds)) }
    }
    var feedback: Float {
        get { state.feedback }
        set { state.feedback = min(max(newValue, 0), 0.9) }
    }
    var mix: Float {
        get { state.mix }
        set { state.mix = min(max(newValue, 0), 1) }
    }

    private var inBus: AUAudioUnitBus!
    private var outBus: AUAudioUnitBus!
    private var inBusses: AUAudioUnitBusArray!
    private var outBusses: AUAudioUnitBusArray!

    static let description = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x6764_6C79,        // 'gdly'
        componentManufacturer: 0x4768_6565,   // 'Ghee'
        componentFlags: 0, componentFlagsMask: 0)

    static let registration: Void = {
        AUAudioUnit.registerSubclass(DelayAU.self, as: description, name: "Ghee: Delay", version: 1)
    }()

    static func makeNode() -> AVAudioUnitEffect {
        _ = registration
        return AVAudioUnitEffect(audioComponentDescription: description)
    }

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        inBus = try AUAudioUnitBus(format: format)
        outBus = try AUAudioUnitBus(format: format)
        inBusses = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inBus])
        outBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outBus])
        maximumFramesToRender = 4096
    }

    override var inputBusses: AUAudioUnitBusArray { inBusses }
    override var outputBusses: AUAudioUnitBusArray { outBusses }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        state.sampleRate = Float(outBus.format.sampleRate)
        state.reset()
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        let state = self.state
        return { actionFlags, timestamp, frameCount, _, outputData, _, pullInput in
            guard let pullInput else { return kAudioUnitErr_NoConnection }
            let status = pullInput(actionFlags, timestamp, frameCount, 0, outputData)
            if status != noErr { return status }

            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            let channels = min(buffers.count, 2)
            let frames = Int(frameCount)
            let sr = state.sampleRate
            let mask = State.size - 1

            let target = max(state.time * sr, 2)
            let glide = 1 - expf(-1 / (0.05 * sr))        // ~50 ms retime glide
            let damping = 1 - expf(-2 * .pi * 4500 / sr)  // warm the repeats (~4.5 kHz)
            let feedback = state.feedback
            let wetGain = state.mix * 0.9

            var write = state.write
            var delay = state.currentDelay
            var damp0 = state.damp[0], damp1 = state.damp[1]

            for i in 0..<frames {
                delay += (target - delay) * glide
                for c in 0..<channels {
                    guard let p = buffers[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let buf = state.buffers[c]
                    let dry = p[i]

                    let readPos = Float(write) - delay
                    let i0 = Int(floorf(readPos))
                    let frac = readPos - Float(i0)
                    let wet = buf[i0 & mask] * (1 - frac) + buf[(i0 + 1) & mask] * frac

                    // Feedback path is low-passed, and soft-limited so it can never run away.
                    var d = c == 0 ? damp0 : damp1
                    d += damping * (wet - d)
                    if c == 0 { damp0 = d } else { damp1 = d }
                    let fb = d * feedback
                    buf[write & mask] = dry + fb / (1 + abs(fb))

                    p[i] = dry + wet * wetGain          // dry stays at full level
                }
                write &+= 1
            }
            state.write = write & mask
            state.currentDelay = delay
            state.damp[0] = damp0; state.damp[1] = damp1
            return noErr
        }
    }
}
