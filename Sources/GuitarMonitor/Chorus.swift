import AVFoundation
import AudioToolbox

/// Stereo chorus as an in-process Audio Unit: two voices of a short, slowly
/// modulated delay mixed with the dry signal. The dry path is untouched, so it
/// adds no latency to what you hear first. `amount` (0...1) sets mix, depth and rate.
final class ChorusAU: AUAudioUnit {
    final class State {
        var amount: Float = 0
        var sampleRate: Float = 48000
        static let size = 8192                       // power of two, > 50 ms at 96 kHz
        var buffers: [UnsafeMutablePointer<Float>] = (0..<2).map { _ in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: State.size)
            p.initialize(repeating: 0, count: State.size); return p
        }
        var write = 0
        var phase: Float = 0
        deinit { buffers.forEach { $0.deallocate() } }
        func reset() { buffers.forEach { $0.update(repeating: 0, count: State.size) }; write = 0; phase = 0 }
    }

    let state = State()
    var amount: Float {
        get { state.amount }
        set { state.amount = min(max(newValue, 0), 1) }
    }

    private var inBus: AUAudioUnitBus!
    private var outBus: AUAudioUnitBus!
    private var inBusses: AUAudioUnitBusArray!
    private var outBusses: AUAudioUnitBusArray!

    static let description = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x6763_6872,        // 'gchr'
        componentManufacturer: 0x4768_6565,   // 'Ghee'
        componentFlags: 0, componentFlagsMask: 0)

    static let registration: Void = {
        AUAudioUnit.registerSubclass(ChorusAU.self, as: description, name: "Ghee: Chorus", version: 1)
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

            let amount = state.amount
            if amount < 0.01 { return noErr }

            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            let channels = min(buffers.count, 2)
            let frames = Int(frameCount)
            let sr = state.sampleRate
            let mask = State.size - 1

            let rate = 0.4 + 0.8 * amount                 // Hz
            let baseDelay = 0.014 * sr                    // 14 ms
            let depth = (0.002 + 0.004 * amount) * sr     // 2-6 ms swing
            let mix = 0.7 * amount
            let norm = 1 / (1 + 0.5 * mix)
            let phaseStep = rate / sr

            var write = state.write
            var phase = state.phase
            for i in 0..<frames {
                for c in 0..<channels {
                    guard let p = buffers[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let buf = state.buffers[c]
                    let dry = p[i]
                    buf[write & mask] = dry

                    // Voices sit a quarter-cycle apart per channel for stereo width.
                    let lfo = sinf(2 * .pi * (phase + 0.25 * Float(c)))
                    let readPos = Float(write) - (baseDelay + depth * lfo)
                    let i0 = Int(floorf(readPos))
                    let frac = readPos - Float(i0)
                    let wet = buf[i0 & mask] * (1 - frac) + buf[(i0 + 1) & mask] * frac

                    p[i] = (dry + wet * mix) * norm
                }
                write &+= 1
                phase += phaseStep
                if phase >= 1 { phase -= 1 }
            }
            state.write = write & mask
            state.phase = phase
            return noErr
        }
    }
}
