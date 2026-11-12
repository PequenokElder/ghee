import AVFoundation
import AudioToolbox

/// Zero-latency feed-forward compressor, packaged as an in-process Audio Unit.
/// No lookahead: it reacts to the signal as it arrives, so it adds no delay.
/// A single `amount` (0...1) sets threshold, ratio and make-up gain together.
final class CompressorAU: AUAudioUnit {
    /// Shared with the render thread. Plain floats; a torn read is harmless here.
    final class State {
        var amount: Float = 0
        var sampleRate: Float = 48000
        var envelope: Float = 0
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
        componentSubType: 0x6763_6D70,        // 'gcmp'
        componentManufacturer: 0x4768_6565,   // 'Ghee'
        componentFlags: 0, componentFlagsMask: 0)

    static let registration: Void = {
        AUAudioUnit.registerSubclass(CompressorAU.self, as: description, name: "Ghee: Compressor", version: 1)
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
        state.envelope = 0
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
            let frames = Int(frameCount)
            let channels = buffers.count

            // Time constants: fast attack, medium release.
            let sr = state.sampleRate
            let attack = 1 - expf(-1 / (0.004 * sr))
            let release = 1 - expf(-1 / (0.200 * sr))

            // One knob -> threshold, ratio, make-up gain.
            let threshold: Float = -10 - 25 * amount
            let ratio: Float = 1 + 3 * amount
            let makeup: Float = -threshold * (1 - 1 / ratio) * 0.5
            let knee: Float = 6

            var env = state.envelope
            for i in 0..<frames {
                var peak: Float = 0
                for c in 0..<channels {
                    if let p = buffers[c].mData?.assumingMemoryBound(to: Float.self) { peak = max(peak, abs(p[i])) }
                }
                env += (peak > env ? attack : release) * (peak - env)

                let db = 20 * log10f(max(env, 1e-6))
                let over = db - threshold
                let out: Float
                if over <= -knee / 2 { out = db }
                else if over >= knee / 2 { out = threshold + over / ratio }
                else { let x = over + knee / 2; out = db + (1 / ratio - 1) * x * x / (2 * knee) }
                let gain = powf(10, (out - db + makeup) / 20)

                for c in 0..<channels {
                    if let p = buffers[c].mData?.assumingMemoryBound(to: Float.self) { p[i] *= gain }
                }
            }
            state.envelope = env
            return noErr
        }
    }
}
