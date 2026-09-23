// OPOv1, the realme / OPPO / OnePlus earbud control protocol, as the buds speak it over BLE:
// service 000008A4, write 00000001, notify 00000002. Same frames as the Mac app's RFCOMM link.
//
//   aa <len> 00 00 <cmd lo> <cmd hi> <seq> <payload len u16le> <payload…>
//
// Replies set the command's high bit and put a status byte (00 = ok) first.

import Foundation

enum Cmd {
    static let hello: UInt16 = 0x0100
    static let productID: UInt16 = 0x0103
    static let version: UInt16 = 0x0105
    static let battery: UInt16 = 0x0106
    static let keyFunction: UInt16 = 0x0108
    static let anc: UInt16 = 0x010C
    static let featureSwitch: UInt16 = 0x010D
    static let eq: UInt16 = 0x010F
    static let notificationEvent: UInt16 = 0x0204
    static let subscribe: UInt16 = 0x0205
    static let findBuds: UInt16 = 0x0400
    static let setKeyFunction: UInt16 = 0x0401
    static let setFeatureSwitch: UInt16 = 0x0403
    static let setANC: UInt16 = 0x0404
    static let setEQ: UInt16 = 0x0406
    static let setSpatial: UInt16 = 0x041E
    static let featureEvent: UInt16 = 0x0503
    static let eqNotify: UInt16 = 0x0504
    static let keyFunctionNotify: UInt16 = 0x0508
    static let reply: UInt16 = 0x8000
}

enum Bud: UInt8, CaseIterable, Identifiable, Codable {
    case left = 1, right = 2, enclosure = 3
    var id: UInt8 { rawValue }
    var label: String { switch self { case .left: "Left"; case .right: "Right"; case .enclosure: "Case" } }
    var short: String { switch self { case .left: "L"; case .right: "R"; case .enclosure: "Case" } }
    var symbol: String { switch self { case .left: "airpod.left"; case .right: "airpod.right"; case .enclosure: "earbuds.case" } }
}

enum Gesture: UInt8, CaseIterable, Identifiable {
    case single = 1, double = 2, triple = 3, hold = 4, doubleHold = 6
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .single: "Tap"; case .double: "Double tap"; case .triple: "Triple tap"
        case .hold: "Touch & hold"; case .doubleHold: "Tap then hold"
        }
    }
    /// What realme Link offers for each gesture on the Air 7.
    var choices: [GestureAction] {
        switch self {
        case .double, .triple: [.playPause, .skipForward, .skipBack, .voiceAssistant, .gameMode, .none]
        case .hold: [.noiseControl, .voiceAssistant, .gameMode, .deviceSwitch, .none]
        case .single, .doubleHold: [.none]
        }
    }
    static let configurable: [Gesture] = [.double, .triple, .hold]
}

enum GestureAction: UInt8, CaseIterable {
    case none = 0x00, playPause = 0x01, voiceAssistant = 0x04, skipBack = 0x05, skipForward = 0x06
    case noiseControl = 0x08, deviceSwitch = 0x0A, gameMode = 0x11
    var label: String {
        switch self {
        case .none: "None"; case .playPause: "Play / pause"; case .voiceAssistant: "Voice assistant"
        case .skipBack: "Previous track"; case .skipForward: "Next track"; case .noiseControl: "Noise control"
        case .deviceSwitch: "Switch device"; case .gameMode: "Game mode"
        }
    }
}

enum ANCLevel: UInt8, CaseIterable, Codable {
    case smart = 0x20, mild = 0x04, moderate = 0x10, max = 0x08
    var label: String { switch self { case .smart: "Smart"; case .mild: "Mild"; case .moderate: "Moderate"; case .max: "Max" } }
}

enum NoiseMode: Equatable, Codable {
    case off, transparency, anc(ANCLevel)
    init?(wire: UInt8) {
        switch wire {
        case 0x01: self = .off
        case 0x02: self = .transparency
        default: guard let l = ANCLevel(rawValue: wire) else { return nil }; self = .anc(l)
        }
    }
    var wire: UInt8 {
        switch self { case .off: 0x01; case .transparency: 0x02; case .anc(let l): l.rawValue }
    }
    var label: String {
        switch self { case .off: "Off"; case .transparency: "Transparency"; case .anc(let l): "ANC · \(l.label)" }
    }
    var symbol: String {
        switch self { case .off: "circle.slash"; case .transparency: "ear.and.waveform"; case .anc: "waveform.slash" }
    }
}

enum EQPreset: UInt8, CaseIterable {
    case original = 0, deepBass = 1, serenade = 2, clearBass = 3
    var label: String {
        switch self { case .original: "Original sound"; case .deepBass: "Deep bass"; case .serenade: "Serenade"; case .clearBass: "Clear bass" }
    }
    var symbol: String {
        switch self { case .original: "music.note"; case .deepBass: "speaker.wave.3"; case .serenade: "music.mic"; case .clearBass: "waveform.path" }
    }
}

struct Feature: Identifiable {
    let id: UInt8
    let title: String
    let detail: String
    let symbol: String
    let hue: Int

    static let all: [Feature] = [
        Feature(id: 0x04, title: "In-ear detection", detail: "Pause when a bud comes out", symbol: "ear", hue: 5),
        Feature(id: 0x08, title: "Auto-answer calls", detail: "", symbol: "phone.fill", hue: 4),
        Feature(id: 0x11, title: "Dual connection", detail: "Two devices at the same time", symbol: "laptopcomputer.and.iphone", hue: 0),
        Feature(id: 0x06, title: "Game mode", detail: "Low-latency audio", symbol: "gamecontroller.fill", hue: 3),
        Feature(id: 0x1A, title: "Wind noise reduction", detail: "", symbol: "wind", hue: 2),
        Feature(id: 0x1B, title: "Spatial audio", detail: "", symbol: "dot.radiowaves.left.and.right", hue: 6),
        Feature(id: 0x1D, title: "Dynamic bass", detail: "", symbol: "waveform", hue: 1),
        Feature(id: 0x09, title: "Volume enhancer", detail: "", symbol: "speaker.wave.3.fill", hue: 7),
        Feature(id: 0x18, title: "High-res audio", detail: "LHDC", symbol: "hifispeaker.fill", hue: 8),
    ]
}

enum Placement: Equatable, Codable {
    case inCase, inEar, out, unknown(UInt8)
    init(_ v: UInt8) {
        switch v { case 0x00: self = .inCase; case 0x03: self = .inEar; case 0x01, 0x02: self = .out; default: self = .unknown(v) }
    }
    var label: String {
        switch self { case .inCase: "In case"; case .inEar: "In ear"; case .out: "Out"; case .unknown(let v): "State \(v)" }
    }
}

struct GestureSlot: Hashable {
    let bud: Bud
    let gesture: Gesture
}

/// Builds outgoing frames and splits the incoming byte stream into (command, payload) pairs.
struct OPOFramer {
    private var seq: UInt8 = 0
    private var rx: [UInt8] = []

    mutating func frame(_ cmd: UInt16, _ payload: [UInt8] = []) -> Data {
        seq = seq >= 250 ? 1 : seq + 1
        return Data([0xAA, UInt8(7 + payload.count), 0, 0, UInt8(cmd & 0xFF), UInt8(cmd >> 8), seq,
                     UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)] + payload)
    }

    mutating func feed(_ data: Data) -> [(cmd: UInt16, payload: [UInt8])] {
        rx += data
        var out: [(UInt16, [UInt8])] = []
        while true {
            guard let start = rx.firstIndex(of: 0xAA) else { rx.removeAll(); break }
            if start > 0 { rx.removeFirst(start) }
            guard rx.count >= 9 else { break }
            let total = Int(rx[1]) + 2
            guard rx.count >= total else { break }
            let payloadLength = Int(rx[7]) | Int(rx[8]) << 8
            if total >= 9 && 9 + payloadLength == total {
                out.append((UInt16(rx[4]) | UInt16(rx[5]) << 8, Array(rx[9..<total])))
                rx.removeFirst(total)
            } else {
                rx.removeFirst()
            }
        }
        return out
    }

    mutating func reset() { rx.removeAll() }
}

/// Pairs out of an OPOv1 tagged list.
func opoPairs(_ bytes: ArraySlice<UInt8>, count: Int) -> [(UInt8, UInt8)] {
    var out: [(UInt8, UInt8)] = []
    var i = bytes.startIndex
    while out.count < count, i + 1 < bytes.endIndex {
        out.append((bytes[i], bytes[i + 1]))
        i += 2
    }
    return out
}
