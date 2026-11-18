// A tiny long-lived sound player for the chatter sounds (lua/sounds/chatter.lua).
//
// `afplay` takes about 850 ms to exit even for an 8 ms file, so one process per
// keystroke would pile up. This stays alive, keeps every WAV decoded in memory,
// and plays overlapping sounds through a pool of AVAudioEngine player nodes.
// It can also run a *train*: a steady, precisely timed series of ticks (a clock, a
// watch), scheduled ahead on the audio clock, so the rhythm doesn't depend on how
// busy Neovim is.
//
//   stdin  (one command per line)
//     play <volume 0..1> <absolute path.wav>         one sound, now
//     trainset<TAB>name<TAB>ntick<TAB>path...        define a set: the first `ntick` paths
//                                                    are the ticks (random pick), the rest
//                                                    the tocks; ticks and tocks alternate
//     train <set> <rate per s> <volume> <jitter ms>  start, or change, the train
//     train_stop                                     stop it
//     quit
//   stdout
//     ready                    engine is running
//     done <path> / tick <t>   only with PLAYER_DEBUG=1: a sound / a train tick was played
//   stderr                     error messages
//
// It exits when stdin closes, so it never outlives Neovim.
//
// Build:  swiftc -O -o <out> player.swift   (done by lua/sounds/player.lua)
import AVFoundation
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let debug = ProcessInfo.processInfo.environment["PLAYER_DEBUG"] == "1"

let engine = AVAudioEngine()
let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
var nodes: [AVAudioPlayerNode] = []
for _ in 0..<16 {
    let node = AVAudioPlayerNode()
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: format)
    nodes.append(node)
}
do {
    try engine.start()
} catch {
    FileHandle.standardError.write("cannot start the audio engine: \(error)\n".data(using: .utf8)!)
    exit(1)
}
// every node runs (silently) from the start, so a buffer can be scheduled at an exact future time
for node in nodes { node.play() }
print("ready")

// Everything below is touched by the main thread (commands) and the train timer.
let lock = NSLock()
var cache: [String: AVAudioPCMBuffer] = [:]
var next = 0

func load(_ path: String) -> AVAudioPCMBuffer? {
    if let hit = cache[path] { return hit }
    guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else {
        FileHandle.standardError.write("cannot open \(path)\n".data(using: .utf8)!)
        return nil
    }
    guard file.processingFormat.sampleRate == format.sampleRate,
          file.processingFormat.channelCount == format.channelCount,
          let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
    else {
        FileHandle.standardError.write("\(path): expected 44.1 kHz mono\n".data(using: .utf8)!)
        return nil
    }
    do { try file.read(into: buf) } catch { return nil }
    cache[path] = buf
    return buf
}

func nextNode() -> AVAudioPlayerNode {
    let node = nodes[next]
    next = (next + 1) % nodes.count
    return node
}

func play(_ path: String, volume: Float) {
    lock.lock(); defer { lock.unlock() }
    guard let buf = load(path) else { return }
    let node = nextNode()
    node.volume = volume
    if debug {
        node.scheduleBuffer(buf, at: nil, options: .interrupts, completionCallbackType: .dataPlayedBack) { _ in
            print("done \(path)")
        }
    } else {
        node.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
    }
    if !node.isPlaying { node.play() }
}

// ---- trains ---------------------------------------------------------------

struct TrainSet { var tick: [AVAudioPCMBuffer]; var tock: [AVAudioPCMBuffer] }
struct Train { var set: String; var rate: Double; var volume: Float; var jitter: Double }
var sets: [String: TrainSet] = [:]
var train: Train? = nil
var nextTick = 0.0 // host time, in seconds, of the next tick to schedule
var flip = false

func hostNow() -> Double { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }

/// Called every 20 ms: schedule every tick that falls in the next 120 ms.
func scheduleTrain() {
    lock.lock(); defer { lock.unlock() }
    guard let t = train, let set = sets[t.set], !set.tick.isEmpty else { nextTick = 0; return }
    let now = hostNow()
    let step = 1.0 / t.rate
    if nextTick < now { nextTick = now + 0.02 }
    while nextTick < now + 0.12 {
        let pool = (flip && !set.tock.isEmpty) ? set.tock : set.tick
        let buf = pool[Int.random(in: 0..<pool.count)]
        // a mechanical movement is never perfectly even: a little timing and strength variation
        let when = max(nextTick + Double.random(in: -1.0...1.0) * t.jitter / 1000.0, now + 0.005)
        let node = nextNode()
        node.volume = t.volume * Float.random(in: 0.82...1.0)
        let at = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: when))
        if debug {
            node.scheduleBuffer(buf, at: at, options: [], completionCallbackType: .dataPlayedBack) { _ in
                print("tick \(Date().timeIntervalSince1970)")
            }
        } else {
            node.scheduleBuffer(buf, at: at, options: [], completionHandler: nil)
        }
        flip.toggle()
        nextTick += step
    }
}

let trainQueue = DispatchQueue(label: "train", qos: .userInteractive)
let trainTimer = DispatchSource.makeTimerSource(queue: trainQueue)
trainTimer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(1))
trainTimer.setEventHandler { scheduleTrain() }
trainTimer.resume()

func defineSet(_ name: String, ntick: Int, paths: [String]) {
    lock.lock(); defer { lock.unlock() }
    var ticks: [AVAudioPCMBuffer] = [], tocks: [AVAudioPCMBuffer] = []
    for (i, p) in paths.enumerated() {
        guard let b = load(p) else { continue }
        if i < ntick { ticks.append(b) } else { tocks.append(b) }
    }
    sets[name] = TrainSet(tick: ticks, tock: tocks)
}

func startTrain(_ t: Train) {
    lock.lock(); defer { lock.unlock() }
    // changing only the volume, rate or set keeps the rhythm; starting from nothing begins now
    if train == nil { nextTick = 0; flip = false }
    train = t
}

func stopTrain() {
    lock.lock(); defer { lock.unlock() }
    train = nil
    nextTick = 0
}

// ---- command loop ----------------------------------------------------------

while let line = readLine() {
    if line == "quit" { break }
    if line.hasPrefix("trainset\t") {
        let f = line.components(separatedBy: "\t")
        if f.count >= 4, let nt = Int(f[2]) { defineSet(f[1], ntick: nt, paths: Array(f[3...])) }
        continue
    }
    let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
    guard let cmd = parts.first else { continue }
    switch cmd {
    case "play":
        if parts.count == 3, let vol = Float(parts[1]) { play(String(parts[2]), volume: max(0, min(1, vol))) }
    case "train":
        let a = line.split(separator: " ", omittingEmptySubsequences: true)
        if a.count == 5, let rate = Double(a[2]), let vol = Float(a[3]), let jit = Double(a[4]), rate > 0 {
            startTrain(Train(set: String(a[1]), rate: rate, volume: max(0, min(1, vol)), jitter: max(0, jit)))
        }
    case "train_stop":
        stopTrain()
    default:
        break
    }
}
trainTimer.cancel()
engine.stop()
