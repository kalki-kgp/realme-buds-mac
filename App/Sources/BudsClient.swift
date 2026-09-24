// OPOv1 over RFCOMM for realme / OPPO / OnePlus earbuds.
// Command table from maniacx/BudsLink (src/lib/devices/opoBuds), verified against a Buds Air 7
// (product id 064812, firmware 1.1.0.66). Opcodes go on the wire little-endian.

import Foundation
import IOBluetooth
import SwiftUI

enum Cmd {
    static let handshake: UInt16 = 0x0100
    static let productID: UInt16 = 0x0103
    static let version: UInt16 = 0x0105
    static let battery: UInt16 = 0x0106
    static let keyFunction: UInt16 = 0x0108
    static let anc: UInt16 = 0x010C
    static let featureSwitch: UInt16 = 0x010D
    static let eq: UInt16 = 0x010F
    static let notificationEvent: UInt16 = 0x0204
    static let registerNotification: UInt16 = 0x0205
    static let findBuds: UInt16 = 0x0400
    static let setKeyFunction: UInt16 = 0x0401
    static let setFeatureSwitch: UInt16 = 0x0403
    static let setANC: UInt16 = 0x0404
    static let setEQ: UInt16 = 0x0406
    static let setSpatial: UInt16 = 0x041E
    static let multiConnectInfo: UInt16 = 0x0112
    static let operateMultiConnect: UInt16 = 0x040B
    static let featureEvent: UInt16 = 0x0503
    static let eqNotify: UInt16 = 0x0504
    static let keyFunctionNotify: UInt16 = 0x0508
    static let response: UInt16 = 0x8000
}

enum Bud: UInt8, CaseIterable, Identifiable {
    case left = 1, right = 2, enclosure = 3
    var id: UInt8 { rawValue }
    var label: String { switch self { case .left: "Left"; case .right: "Right"; case .enclosure: "Case" } }
    var short: String { switch self { case .left: "L"; case .right: "R"; case .enclosure: "Case" } }
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

enum NoiseMode: Equatable {
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
}

enum ANCLevel: UInt8, CaseIterable {
    case smart = 0x20, mild = 0x04, moderate = 0x10, max = 0x08
    var label: String { switch self { case .smart: "Smart"; case .mild: "Mild"; case .moderate: "Moderate"; case .max: "Max" } }
}

enum EQPreset: UInt8, CaseIterable {
    case original = 0, deepBass = 1, serenade = 2, clearBass = 3
    var label: String {
        switch self { case .original: "Original sound"; case .deepBass: "Deep bass"; case .serenade: "Serenade"; case .clearBass: "Clear bass" }
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
        Feature(id: 0x11, title: "Dual connection", detail: "Phone and Mac at the same time", symbol: "laptopcomputer.and.iphone", hue: 0),
        Feature(id: 0x06, title: "Game mode", detail: "Low-latency audio", symbol: "gamecontroller.fill", hue: 3),
        Feature(id: 0x1A, title: "Wind noise reduction", detail: "", symbol: "wind", hue: 2),
        Feature(id: 0x1B, title: "Spatial audio", detail: "", symbol: "dot.radiowaves.left.and.right", hue: 6),
        Feature(id: 0x1D, title: "Dynamic bass", detail: "", symbol: "waveform", hue: 1),
        Feature(id: 0x09, title: "Volume enhancer", detail: "", symbol: "speaker.wave.3.fill", hue: 7),
        Feature(id: 0x18, title: "High-res audio", detail: "LHDC", symbol: "hifispeaker.fill", hue: 8),
    ]
}

struct BatteryLevel: Equatable {
    var percent: Int?
    var charging = false
}

enum Placement: Equatable {
    case inCase, inEar, out, unknown(UInt8)
    init(_ v: UInt8) {
        switch v { case 0x00: self = .inCase; case 0x03: self = .inEar; case 0x01, 0x02: self = .out; default: self = .unknown(v) }
    }
    var label: String {
        switch self { case .inCase: "In case"; case .inEar: "In ear"; case .out: "Out"; case .unknown(let v): "State \(v)" }
    }
}

struct TouchEvent: Identifiable {
    let id = UUID()
    let date: Date
    let symbol: String
    let title: String
    let detail: String
    let isTouch: Bool
}

/// A device the buds remember pairing with. They hold two connections at once and keep
/// the rest on this list, from which any one can be brought back.
struct PairedDevice: Identifiable, Equatable {
    /// Bluetooth address as the buds send it (byte-reversed); sent back unchanged.
    let address: [UInt8]
    let name: String
    let isConnected: Bool
    /// The device this app is talking through, i.e. this Mac.
    let isThisDevice: Bool
    var id: [UInt8] { address }
}

struct GestureSlot: Hashable {
    let bud: Bud
    let gesture: Gesture
}

func trace(_ s: String) {
    guard ProcessInfo.processInfo.environment["BUDS_TRACE"] != nil else { return }
    FileHandle.standardError.write(Data("[buds] \(s)\n".utf8))
}

final class BudsClient: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {
    enum LinkState: Equatable { case noDevice, disconnected, connecting, connected }

    static let serviceUUID = IOBluetoothSDPUUID(data: Data([0x00, 0x00, 0x07, 0x9A, 0xD1, 0x02, 0x11, 0xE1,
                                                            0x9B, 0x23, 0x00, 0x02, 0x5B, 0x00, 0xA5, 0xA5]))

    /// The control service record: by UUID, or by the name realme gives it.
    static func controlRecord(_ device: IOBluetoothDevice) -> IOBluetoothSDPServiceRecord? {
        if let record = device.getServiceRecord(for: serviceUUID) { return record }
        let records = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
        return records.first { $0.getServiceName() == "oppointeraction" }
    }

    @Published private(set) var link: LinkState = .noDevice
    @Published private(set) var deviceName = "realme Buds"
    @Published private(set) var firmware: String?
    @Published private(set) var battery: [Bud: BatteryLevel] = [:]
    @Published private(set) var placement: [Bud: Placement] = [:]
    @Published private(set) var noiseMode: NoiseMode?
    @Published private(set) var eq: EQPreset?
    @Published private(set) var gestures: [GestureSlot: GestureAction] = [:]
    @Published private(set) var features: [UInt8: Bool] = [:]
    @Published private(set) var events: [TouchEvent] = []
    @Published private(set) var ringing = false
    @Published private(set) var devices: [PairedDevice] = []
    /// Devices a connect or disconnect was just sent for, until the buds report back.
    @Published private(set) var switching: Set<[UInt8]> = []
    @Published var lastError: String?

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var rx: [UInt8] = []
    private var queue: [[UInt8]] = []
    private var seq: UInt8 = 0
    private var connecting = false
    private var timers: [Timer] = []
    private var listWaiters: [([PairedDevice]) -> Void] = []

    override init() {
        super.init()
        timers.append(Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.tick() })
        timers.append(Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.pump() })
        tick()
    }

    // MARK: Connection

    private func findDevice() -> IOBluetoothDevice? {
        if let address = ProcessInfo.processInfo.environment["BUDS_ADDRESS"] {
            return IOBluetoothDevice(addressString: address)
        }
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let speaking = paired.filter { Self.controlRecord($0) != nil }
        return speaking.first { $0.isConnected() } ?? speaking.first
            ?? paired.first { $0.isConnected() && ($0.name ?? "").localizedCaseInsensitiveContains("buds") }
    }

    private func tick() {
        if let channel, channel.isOpen() { return }
        if device == nil || !(device?.isConnected() ?? false) { device = findDevice() }
        guard let device else { link = .noDevice; return }
        deviceName = device.name ?? deviceName
        guard device.isConnected() else { link = .disconnected; return }
        guard !connecting else { return }
        trace("opening channel on \(device.addressString ?? "?")")
        openChannel(device)
    }

    private func openChannel(_ device: IOBluetoothDevice) {
        connecting = true
        link = .connecting
        // The channel open never completes unless this process has fetched the SDP records.
        device.performSDPQuery(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            var id: BluetoothRFCOMMChannelID = 0
            guard let record = Self.controlRecord(device),
                  record.getRFCOMMChannelID(&id) == kIOReturnSuccess else {
                self.connecting = false
                self.lastError = "These buds don't advertise the OPOv1 control service"
                trace("no OPOv1 record")
                return
            }
            var ch: IOBluetoothRFCOMMChannel?
            let r = device.openRFCOMMChannelAsync(&ch, withChannelID: id, delegate: self)
            trace("openRFCOMMChannelAsync ch\(id) -> \(r)")
            if r != kIOReturnSuccess { self.connecting = false }
        }
    }

    /// Asks macOS to bring the buds' audio link up, for when they're paired but idle.
    func connectAudio() {
        guard let device = device ?? findDevice() else { return }
        link = .connecting
        device.openConnection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.tick() }
    }

    func rfcommChannelOpenComplete(_ ch: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        connecting = false
        trace("open complete status \(status)")
        guard status == kIOReturnSuccess else {
            link = .disconnected
            lastError = "Couldn't open the control channel (\(status)). Is another app holding it?"
            return
        }
        channel = ch
        link = .connected
        lastError = nil
        rx.removeAll()
        queue.removeAll()
        send(Cmd.handshake)
        let events: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x0D, 0x0E, 0x0F, 0x10, 0xF1, 0xF2]
        send(Cmd.registerNotification, [UInt8(events.count)] + events)
        refresh()
    }

    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) {
        channel = nil
        connecting = false
        ringing = false
        listWaiters.removeAll()
        switching.removeAll()
        link = (device?.isConnected() ?? false) ? .connecting : .disconnected
    }

    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data: UnsafeMutableRawPointer!, length: Int) {
        rx += Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: length))
        trace("rx \(length) bytes")
        drain()
    }

    // MARK: Sending

    private func send(_ cmd: UInt16, _ payload: [UInt8] = []) {
        seq = seq >= 250 ? 1 : seq + 1
        queue.append([0xAA, UInt8(7 + payload.count), 0, 0, UInt8(cmd & 0xFF), UInt8(cmd >> 8), seq,
                      UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)] + payload)
    }

    /// One frame per tick: the buds drop commands that arrive back to back.
    private func pump() {
        guard let channel, channel.isOpen(), !queue.isEmpty else { return }
        var frame = queue.removeFirst()
        if channel.writeSync(&frame, length: UInt16(frame.count)) != kIOReturnSuccess {
            lastError = "Write to the buds failed"
        }
    }

    func refresh() {
        send(Cmd.version)
        send(Cmd.battery)
        send(Cmd.anc, [0x01, 0x01])
        send(Cmd.eq)
        send(Cmd.keyFunction, [0x02, 0x01, 0x02])
        let ids = Feature.all.map(\.id)
        send(Cmd.featureSwitch, [UInt8(ids.count)] + ids)
        send(Cmd.multiConnectInfo)
    }

    /// Connects `device`, first dropping `replacing` if both connections are in use.
    ///
    /// Asked to connect a third device, the buds make room by dropping this Mac. The app's
    /// list can be stale (the buds send nothing when a device comes or goes on its own), so
    /// every connect starts from a fresh read, and a switch waits until the buds confirm the
    /// dropped device is gone before connecting the new one.
    func connect(_ device: PairedDevice, replacing: PairedDevice? = nil) {
        switching.insert(device.id)
        if let replacing { switching.insert(replacing.id) }
        readDevices { [weak self] list in
            guard let self else { return }
            let connected = list.filter(\.isConnected)
            if connected.contains(where: { $0.id == device.id }) { return self.finishSwitch() }
            if connected.count < 2 { return self.sendConnect(device) }
            guard let replacing, connected.contains(where: { $0.id == replacing.id }), !replacing.isThisDevice else {
                self.lastError = "Both connections are in use. Pick one to disconnect."
                return self.finishSwitch()
            }
            self.send(Cmd.operateMultiConnect, [0x01] + replacing.address + [0x00])
            self.waitUntilGone(replacing, attempts: 8) { gone in
                if gone {
                    self.sendConnect(device)
                } else {
                    self.lastError = "\(replacing.name) didn't disconnect, so nothing was switched."
                    self.finishSwitch()
                }
            }
        }
    }

    private func sendConnect(_ device: PairedDevice) {
        send(Cmd.operateMultiConnect, [0x01] + device.address + [0x01])
        recheckDevices()
    }

    /// Re-reads the list about once a second until `device` shows as disconnected.
    private func waitUntilGone(_ device: PairedDevice, attempts: Int, then: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.readDevices { list in
                let stillOn = list.contains { $0.id == device.id && $0.isConnected }
                if !stillOn { then(true) } else if attempts > 1 {
                    self?.waitUntilGone(device, attempts: attempts - 1, then: then)
                } else { then(false) }
            }
        }
    }

    private func finishSwitch() {
        switching.removeAll()
        send(Cmd.multiConnectInfo)
    }

    /// Asks the buds for the device list and hands the answer to `then`.
    private func readDevices(_ then: @escaping ([PairedDevice]) -> Void) {
        listWaiters.append(then)
        send(Cmd.multiConnectInfo)
    }

    func disconnect(_ device: PairedDevice) {
        switching.insert(device.id)
        send(Cmd.operateMultiConnect, [0x01] + device.address + [0x00])
        recheckDevices()
    }

    /// The buds send no event when a device comes or goes, and a reconnect took about seven
    /// seconds on a Buds Air 7, so poll the list until then and a little past it.
    private func recheckDevices() {
        let delays = [2.0, 5.0, 8.0, 12.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.send(Cmd.multiConnectInfo)
                if delay == delays.last { self?.switching.removeAll() }
            }
        }
    }

    func setNoiseMode(_ mode: NoiseMode) {
        noiseMode = mode
        send(Cmd.setANC, [0x01, 0x01, mode.wire])
    }

    func setEQ(_ preset: EQPreset) {
        eq = preset
        send(Cmd.setEQ, [preset.rawValue])
    }

    func setGesture(_ action: GestureAction, for slots: [GestureSlot]) {
        var payload: [UInt8] = [UInt8(slots.count)]
        for slot in slots {
            gestures[slot] = action
            payload += [slot.bud.rawValue, 0x01, slot.gesture.rawValue, action.rawValue]
        }
        send(Cmd.setKeyFunction, payload)
        send(Cmd.keyFunction, [0x02, 0x01, 0x02])
    }

    func setFeature(_ id: UInt8, _ on: Bool) {
        features[id] = on
        send(Cmd.setFeatureSwitch, [id, on ? 1 : 0])
        if id == 0x1B { send(Cmd.setSpatial, [on ? 1 : 0]) }
    }

    func setRinging(_ on: Bool) {
        ringing = on
        send(Cmd.findBuds, [on ? 1 : 0])
    }

    func clearEvents() { events.removeAll() }

    // MARK: Receiving

    private func drain() {
        while true {
            guard let start = rx.firstIndex(of: 0xAA) else { rx.removeAll(); return }
            if start > 0 { rx.removeFirst(start) }
            guard rx.count >= 9 else { return }
            let total = Int(rx[1]) + 2
            guard rx.count >= total else { return }
            let payloadLength = Int(rx[7]) | Int(rx[8]) << 8
            if total >= 9 && 9 + payloadLength == total {
                let cmd = UInt16(rx[4]) | UInt16(rx[5]) << 8
                let payload = Array(rx[9..<total])
                rx.removeFirst(total)
                handle(cmd, payload)
            } else {
                rx.removeFirst()
            }
        }
    }

    private func pairs(_ bytes: ArraySlice<UInt8>, count: Int) -> [(UInt8, UInt8)] {
        var out: [(UInt8, UInt8)] = []
        var i = bytes.startIndex
        while out.count < count, i + 1 < bytes.endIndex {
            out.append((bytes[i], bytes[i + 1]))
            i += 2
        }
        return out
    }

    private func handle(_ cmd: UInt16, _ p: [UInt8]) {
        let isReply = cmd & Cmd.response != 0
        if isReply, p.first != 0x00 {   // rejected
            if cmd == Cmd.operateMultiConnect | Cmd.response {
                lastError = "The buds turned that switch down"
                switching.removeAll()
            }
            return
        }
        switch cmd {
        case Cmd.version | Cmd.response:
            parseVersion(p)
        case Cmd.battery | Cmd.response where p.count >= 2:
            parseBattery(p.dropFirst(1))
        case Cmd.anc | Cmd.response where p.count >= 3:
            if p[1] == 0x01, let mode = NoiseMode(wire: p.count >= 4 ? p[3] : p[2]) { noiseMode = mode }
        case Cmd.eq | Cmd.response where p.count >= 2:
            eq = EQPreset(rawValue: p[1])
        case Cmd.eqNotify:
            if let v = (p.count >= 2 && p[0] == 0 ? p[1] : p.first) { eq = EQPreset(rawValue: v) }
        case Cmd.keyFunction | Cmd.response where p.count >= 2:
            var next: [GestureSlot: GestureAction] = [:]
            let slots = Array(p.dropFirst(2).prefix(Int(p[1]) * 4))
            for i in stride(from: 0, to: slots.count - 3, by: 4) {
                if let bud = Bud(rawValue: slots[i]), let g = Gesture(rawValue: slots[i + 2]),
                   let a = GestureAction(rawValue: slots[i + 3]) {
                    next[GestureSlot(bud: bud, gesture: g)] = a
                }
            }
            gestures = next
        case Cmd.keyFunctionNotify:
            send(Cmd.keyFunction, [0x02, 0x01, 0x02])
        case Cmd.featureSwitch | Cmd.response where p.count >= 2:
            for (id, v) in pairs(p.dropFirst(2), count: Int(p[1])) { features[id] = v == 1 }
        case Cmd.featureEvent where p.count >= 1:
            for (id, v) in pairs(p.dropFirst(1), count: Int(p[0])) { features[id] = v == 1 }
        case Cmd.findBuds | Cmd.response:
            break
        case Cmd.multiConnectInfo | Cmd.response where p.count >= 2:
            parseDevices(p)
        case Cmd.operateMultiConnect | Cmd.response:
            break
        case Cmd.notificationEvent where !p.isEmpty:
            handleEvent(p[0], Array(p.dropFirst()))
        default:
            break
        }
    }

    private func handleEvent(_ code: UInt8, _ d: [UInt8]) {
        switch code {
        case 0x01 where !d.isEmpty:
            parseBattery(d[...])
        case 0x02 where !d.isEmpty:
            for (id, v) in pairs(d.dropFirst(1), count: Int(d[0])) {
                guard let bud = Bud(rawValue: id), bud != .enclosure else { continue }
                let new = Placement(v)
                if let old = placement[bud], old != new {
                    log(TouchEvent(date: Date(), symbol: bud == .left ? "l.circle" : "r.circle",
                                   title: "\(bud.label) bud: \(new.label)", detail: "was \(old.label.lowercased())",
                                   isTouch: false))
                }
                placement[bud] = new
            }
        case 0x06, 0x0D, 0x12, 0x13, 0x16:
            send(Cmd.multiConnectInfo)
        case 0x03 where d.count >= 3:
            if d[0] == 0x01, let mode = NoiseMode(wire: d[2]) { noiseMode = mode }
        case 0xF1 where d.count >= 4:
            let bud = Bud(rawValue: d[0])
            let gesture = Gesture(rawValue: d[2])?.label ?? "Gesture \(d[2])"
            let action = GestureAction(rawValue: d[3])?.label ?? "action \(d[3])"
            log(TouchEvent(date: Date(), symbol: "hand.tap.fill",
                           title: "\(bud?.label ?? "Bud \(d[0])") · \(gesture)",
                           detail: action, isTouch: true))
        case 0xF2:
            // Not a button: the buds push their remembered-device names here when the list changes.
            send(Cmd.multiConnectInfo)
        default:
            break
        }
    }

    /// `00 <count>` then per device: address(6) <len> then <len> bytes of
    /// state, flags, name length, name. State 1/2 is connected; flag bit 0 marks this device.
    private func parseDevices(_ p: [UInt8]) {
        var list: [PairedDevice] = []
        var pos = 2
        for _ in 0..<Int(p[1]) where pos + 10 <= p.count {
            let address = Array(p[pos..<pos + 6])
            let length = Int(p[pos + 6])
            let state = p[pos + 7], flags = p[pos + 8], nameLength = Int(p[pos + 9])
            let nameEnd = min(p.count, pos + 10 + nameLength)
            let name = String(decoding: p[(pos + 10)..<nameEnd], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            list.append(PairedDevice(address: address, name: name.isEmpty ? "Unnamed device" : name,
                                     isConnected: state == 1 || state == 2, isThisDevice: flags & 0x01 != 0))
            pos += 7 + length
        }
        // Settled devices leave the switching set as soon as their state changes.
        for device in list {
            if let old = devices.first(where: { $0.id == device.id }), old.isConnected != device.isConnected {
                switching.remove(device.id)
            }
        }
        devices = list
        let waiters = listWaiters
        listWaiters.removeAll()
        waiters.forEach { $0(list) }
    }

    private func parseBattery(_ b: ArraySlice<UInt8>) {
        guard let count = b.first else { return }
        for (id, raw) in pairs(b.dropFirst(), count: Int(count)) {
            guard let bud = Bud(rawValue: id) else { continue }
            let level = Int(raw & 0x7F)
            battery[bud] = BatteryLevel(percent: level == 0 ? nil : level, charging: raw & 0x80 != 0)
        }
    }

    /// "1,1,111,1,2,1.1.0.66,…": triples of (bud, component, version); component 2 is the firmware.
    private func parseVersion(_ p: [UInt8]) {
        let text = String(decoding: p.dropFirst(2), as: UTF8.self).split(separator: ",").map(String.init)
        for i in stride(from: 0, to: text.count - 2, by: 3) where text[i] == "1" && text[i + 1] == "2" {
            firmware = text[i + 2]
        }
    }

    private func log(_ event: TouchEvent) {
        withAnimation(.smooth(duration: 0.3)) {
            events.insert(event, at: 0)
            if events.count > 40 { events.removeLast(events.count - 40) }
        }
    }
}
