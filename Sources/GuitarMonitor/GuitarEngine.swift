import AVFoundation
import CoreAudio
import Foundation

struct AudioInterface: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let inputChannels: Int
    let outputChannels: Int
}

/// Real-time guitar monitor: input -> sum to mono -> drive -> 3-band EQ -> output.
/// Latency is kept low by requesting a tiny hardware I/O buffer from Core Audio
/// and keeping the processing graph to a handful of cheap nodes.
final class GuitarEngine: ObservableObject {
    // MARK: Published state
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var interfaces: [AudioInterface] = []
    @Published private(set) var latencyMs: Double?
    @Published private(set) var actualBufferFrames: Int?
    @Published private(set) var level: Float = 0
    @Published private(set) var needsMicPermission = false

    // MARK: Settings (persisted)
    @Published var deviceName: String = UserDefaults.standard.string(forKey: "deviceName") ?? "" {
        didSet { UserDefaults.standard.set(deviceName, forKey: "deviceName"); restartIfRunning() }
    }
    @Published var bufferFrames: Int = GuitarEngine.load("bufferFrames", 64) {
        didSet { UserDefaults.standard.set(bufferFrames, forKey: "bufferFrames"); restartIfRunning() }
    }
    @Published var inputGain: Double = GuitarEngine.load("inputGain", 1.0) {
        didSet { save("inputGain", inputGain); applyParameters() }
    }
    @Published var compression: Double = GuitarEngine.load("compression", 0.0) {
        didSet { save("compression", compression); applyParameters() }
    }
    @Published var chorusMix: Double = GuitarEngine.load("chorusMix", 0.0) {
        didSet { save("chorusMix", chorusMix); applyParameters() }
    }
    @Published var reverbMix: Double = GuitarEngine.load("reverbMix", 0.0) {
        didSet { save("reverbMix", reverbMix); applyParameters() }
    }
    @Published var drive: Double = GuitarEngine.load("drive", 0.0) {
        didSet { save("drive", drive); applyParameters() }
    }
    @Published var bass: Double = GuitarEngine.load("bass", 0.0) {
        didSet { save("bass", bass); applyParameters() }
    }
    @Published var mid: Double = GuitarEngine.load("mid", 0.0) {
        didSet { save("mid", mid); applyParameters() }
    }
    @Published var treble: Double = GuitarEngine.load("treble", 0.0) {
        didSet { save("treble", treble); applyParameters() }
    }
    @Published var volume: Double = GuitarEngine.load("volume", 0.7) {
        didSet { save("volume", volume); applyParameters() }
    }

    static let bufferOptions = [32, 64, 128, 256]

    // MARK: Audio graph (rebuilt on every start)
    private var engine = AVAudioEngine()
    private var sumMixer = AVAudioMixerNode()      // N input channels -> mono, input gain
    private var spreadMixer = AVAudioMixerNode()   // mono -> centred stereo
    private var distortion = AVAudioUnitDistortion()
    private var compressor = CompressorAU.makeNode()
    private var chorus = ChorusAU.makeNode()
    private var reverb = AVAudioUnitReverb()
    private var eq = AVAudioUnitEQ(numberOfBands: 3)
    private var tapInstalled = false
    private var configObserver: NSObjectProtocol?
    private var restartWork: DispatchWorkItem?

    init() {
        refreshInterfaces()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.isRunning, (note.object as? AVAudioEngine) === self.engine else { return }
            self.restartIfRunning()
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    // MARK: Start / stop

    func toggle() { isRunning ? stop() : start() }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted { self.startEngine() } else { self.needsMicPermission = true; self.fail("Microphone access was denied.") }
                }
            }
        default:
            needsMicPermission = true
            fail("Microphone access is off. Enable Ghee under Privacy & Security › Microphone.")
        }
    }

    func stop() {
        restartWork?.cancel()
        teardown()
        isRunning = false
        latencyMs = nil
        actualBufferFrames = nil
        level = 0
    }

    private func restartIfRunning() {
        guard isRunning else { return }
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.startEngine() }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func fail(_ message: String) {
        teardown()
        isRunning = false
        latencyMs = nil
        errorMessage = message
    }

    private func teardown() {
        if tapInstalled, sumMixer.engine != nil { sumMixer.removeTap(onBus: 0) }
        tapInstalled = false
        if engine.isRunning { engine.stop() }
    }

    private func startEngine() {
        teardown()
        errorMessage = nil
        needsMicPermission = false
        refreshInterfaces()

        // Fresh engine + nodes each time so device/format changes are always picked up.
        engine = AVAudioEngine()
        sumMixer = AVAudioMixerNode()
        spreadMixer = AVAudioMixerNode()
        distortion = AVAudioUnitDistortion()
        compressor = CompressorAU.makeNode()
        chorus = ChorusAU.makeNode()
        reverb = AVAudioUnitReverb()
        eq = AVAudioUnitEQ(numberOfBands: 3)

        // Pick devices. An interface with both inputs and outputs is used for both directions.
        let chosen = interfaces.first { $0.name == deviceName }
        let inputID = chosen?.id ?? Self.defaultDevice(input: true)
        var outputID = Self.defaultDevice(input: false)
        if let chosen {
            Self.setUnitDevice(engine.inputNode.audioUnit, chosen.id)
            if chosen.outputChannels > 0 {
                outputID = chosen.id
                Self.setUnitDevice(engine.outputNode.audioUnit, chosen.id)
            }
        }

        // Ask the hardware for a small I/O buffer — the biggest lever on latency.
        Self.setBufferFrames(inputID, bufferFrames)
        Self.setBufferFrames(outputID, bufferFrames)

        let inFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            fail("No audio input found. Plug in your interface and choose it above.")
            return
        }
        let sr = inFormat.sampleRate
        let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let stereo = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!

        configureEffects()

        [sumMixer, spreadMixer, compressor, distortion, eq, chorus, reverb].forEach { engine.attach($0) }
        engine.connect(engine.inputNode, to: sumMixer, format: inFormat)
        engine.connect(sumMixer, to: spreadMixer, format: mono)
        engine.connect(spreadMixer, to: compressor, format: stereo)
        engine.connect(compressor, to: distortion, format: stereo)
        engine.connect(distortion, to: eq, format: stereo)
        engine.connect(eq, to: chorus, format: stereo)
        engine.connect(chorus, to: reverb, format: stereo)
        engine.connect(reverb, to: engine.mainMixerNode, format: stereo)
        applyParameters()

        // Level meter taps the signal in parallel; it adds no latency to the audio path.
        sumMixer.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            guard let data = buffer.floatChannelData?[0] else { return }
            var peak: Float = 0
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[i])) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.level = max(peak, self.level * 0.8)
            }
        }

        tapInstalled = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            // -10875 (failed initialization) is what Core Audio reports when macOS
            // withholds microphone access from this app.
            if (error as NSError).code == -10875 {
                needsMicPermission = true
                fail("macOS is blocking audio input for Ghee. Allow it under Privacy & Security › Microphone, then quit and reopen the app.")
            } else {
                fail("Couldn't start audio: \(error.localizedDescription)")
            }
            return
        }
        isRunning = true
        actualBufferFrames = Self.bufferFrames(inputID)
        let effectsMs = ([compressor, reverb, distortion, eq] as [AVAudioUnit])
            .filter { !$0.auAudioUnit.shouldBypassEffect }
            .reduce(0.0) { $0 + $1.latency * 1000 }
        latencyMs = Self.roundTripLatencyMs(input: inputID, output: outputID, sampleRate: sr) + effectsMs
    }

    // MARK: Effects

    private func configureEffects() {
        distortion.loadFactoryPreset(.multiDistortedCubed)
        reverb.loadFactoryPreset(.mediumHall)

        let low = eq.bands[0]
        low.filterType = .lowShelf; low.frequency = 120; low.bypass = false
        let midBand = eq.bands[1]
        midBand.filterType = .parametric; midBand.frequency = 800; midBand.bandwidth = 1.5; midBand.bypass = false
        let high = eq.bands[2]
        high.filterType = .highShelf; high.frequency = 4000; high.bypass = false
    }

    private func applyParameters() {
        sumMixer.outputVolume = Float(inputGain)
        engine.mainMixerNode.outputVolume = Float(volume)

        distortion.bypass = drive < 0.01
        distortion.wetDryMix = Float(drive * 100)
        distortion.preGain = Float(drive * 20)

        // Compression: one knob sets threshold, ratio and make-up gain together.
        compressor.bypass = compression < 0.01
        (compressor.auAudioUnit as? CompressorAU)?.amount = Float(compression)

        chorus.bypass = chorusMix < 0.01
        (chorus.auAudioUnit as? ChorusAU)?.amount = Float(chorusMix)

        reverb.bypass = reverbMix < 0.01
        reverb.wetDryMix = Float(reverbMix * 60)

        eq.bands[0].gain = Float(bass)
        eq.bands[1].gain = Float(mid)
        eq.bands[2].gain = Float(treble)
    }

    // MARK: Persistence

    private static func load(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }
    private static func load(_ key: String, _ fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }
    private func save(_ key: String, _ value: Double) { UserDefaults.standard.set(value, forKey: key) }

    // MARK: Core Audio helpers

    func refreshInterfaces() {
        interfaces = Self.allDevices().filter { $0.inputChannels > 0 }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func allDevices() -> [AudioInterface] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map {
            AudioInterface(id: $0, name: deviceName($0),
                           inputChannels: channelCount($0, kAudioObjectPropertyScopeInput),
                           outputChannels: channelCount($0, kAudioObjectPropertyScopeOutput))
        }
    }

    private static func deviceName(_ dev: AudioDeviceID) -> String {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &name) == noErr, let name else { return "Unknown" }
        return name.takeRetainedValue() as String
    }

    private static func channelCount(_ dev: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func defaultDevice(input: Bool) -> AudioDeviceID {
        var addr = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        return dev
    }

    private static func setUnitDevice(_ unit: AudioUnit?, _ dev: AudioDeviceID) {
        guard let unit else { return }
        var d = dev
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                             &d, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    private static func setBufferFrames(_ dev: AudioDeviceID, _ frames: Int) {
        guard dev != 0 else { return }
        var addr = address(kAudioDevicePropertyBufferFrameSize)
        var value = UInt32(frames)
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private static func uint32(_ dev: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                               _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32 {
        var addr = address(selector, scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value)
        return value
    }

    private static func bufferFrames(_ dev: AudioDeviceID) -> Int {
        Int(uint32(dev, kAudioDevicePropertyBufferFrameSize))
    }

    /// Estimated in-to-out delay: (device latency + safety offset + buffer) on each side.
    private static func roundTripLatencyMs(input: AudioDeviceID, output: AudioDeviceID, sampleRate: Double) -> Double {
        func frames(_ dev: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> UInt32 {
            uint32(dev, kAudioDevicePropertyLatency, scope)
                + uint32(dev, kAudioDevicePropertySafetyOffset, scope)
                + uint32(dev, kAudioDevicePropertyBufferFrameSize)
        }
        let total = frames(input, kAudioObjectPropertyScopeInput) + frames(output, kAudioObjectPropertyScopeOutput)
        return Double(total) / sampleRate * 1000
    }
}
