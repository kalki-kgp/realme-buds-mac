// Command-line control for realme / OPPO earbuds over OPOv1 (RFCOMM, service 0000079A-D102-11E1-9B23-00025B00A5A5).
// Protocol per maniacx/BudsLink (opoBuds) and anikket-b/Realme-TWS-Mac-Controller.
//
//   swift buds.swift                      read state, then log live events (tap the buds)
//   swift buds.swift left-off             every left gesture -> none
//   swift buds.swift set L double none    one slot: L|R  double|triple|hold  <action>
//   swift buds.swift restore <hex>        write back a "gestures:" hex printed earlier
//   swift buds.swift feature auto-answer off   (auto-answer | in-ear) on|off
//
// Never touches the BESOTA (firmware OTA) service.

import Foundation
import IOBluetooth

setvbuf(stdout, nil, _IOLBF, 0)

let serviceUUID: [UInt8] = [0x00, 0x00, 0x07, 0x9A, 0xD1, 0x02, 0x11, 0xE1,
                            0x9B, 0x23, 0x00, 0x02, 0x5B, 0x00, 0xA5, 0xA5]

enum Cmd {
    static let handshake: UInt16 = 0x0100, productID: UInt16 = 0x0103, version: UInt16 = 0x0105
    static let keyFunction: UInt16 = 0x0108, featureSwitch: UInt16 = 0x010D
    static let registerNotification: UInt16 = 0x0205, notificationEvent: UInt16 = 0x0204
    static let setKeyFunction: UInt16 = 0x0401, setFeatureSwitch: UInt16 = 0x0403
    static let keyFunctionNotify: UInt16 = 0x0508, featureEvent: UInt16 = 0x0503
}

let gestureTypes: [String: UInt8] = ["single": 0x01, "double": 0x02, "triple": 0x03, "hold": 0x04, "double-hold": 0x06]
let actions: [String: UInt8] = ["none": 0x00, "play-pause": 0x01, "voice-assistant": 0x04, "skip-back": 0x05,
                                "skip-forward": 0x06, "noise-control": 0x08, "device-switch": 0x0A, "game-mode": 0x11]
let features: [String: UInt8] = ["in-ear": 0x04, "game-mode": 0x06, "auto-answer": 0x08, "volume-enhancer": 0x09,
                                 "dual-device": 0x11, "high-res": 0x18, "wind-noise": 0x1A, "spatial": 0x1B,
                                 "dynamic-bass": 0x1D, "find-phone": 0x26]
let budNames: [UInt8: String] = [1: "L", 2: "R", 3: "case"]

func name<T: Equatable>(_ table: [String: T], _ value: T) -> String {
    table.first { $0.value == value }?.key ?? "?"
}
func hex(_ b: [UInt8], sep: String = " ") -> String { b.map { String(format: "%02x", $0) }.joined(separator: sep) }

let start = Date()
func log(_ s: String) { print(String(format: "[%7.2f] ", Date().timeIntervalSince(start)) + s) }

// MARK: - Framing

var seq: UInt8 = 0
func frame(_ cmd: UInt16, _ payload: [UInt8]) -> [UInt8] {
    seq = seq >= 250 ? 1 : seq + 1
    return [0xAA, UInt8(7 + payload.count), 0, 0, UInt8(cmd & 0xFF), UInt8(cmd >> 8), seq,
            UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)] + payload
}

var rx: [UInt8] = []
func drain() -> [(cmd: UInt16, payload: [UInt8])] {
    var out: [(UInt16, [UInt8])] = []
    while true {
        guard let s = rx.firstIndex(of: 0xAA) else { rx.removeAll(); break }
        if s > 0 { rx.removeFirst(s) }
        guard rx.count >= 9 else { break }
        let total = Int(rx[1]) + 2
        guard rx.count >= total else { break }
        let payLen = Int(rx[7]) | Int(rx[8]) << 8
        if total >= 9 && 9 + payLen == total {
            out.append((UInt16(rx[4]) | UInt16(rx[5]) << 8, Array(rx[9..<total])))
            rx.removeFirst(total)
        } else {
            rx.removeFirst()
        }
    }
    return out
}

// MARK: - Decoding

func describeGestures(_ p: [UInt8]) {
    guard p.count >= 2, p[0] == 0 else { log("gesture query rejected: \(hex(p))"); return }
    let count = Int(p[1])
    let slots = Array(p.dropFirst(2).prefix(count * 4))
    log("gestures: \(hex(slots, sep: ""))   <- keep this to restore")
    for i in stride(from: 0, to: slots.count - 3, by: 4) {
        log(String(format: "  %@ %-11@ -> %@", budNames[slots[i]] ?? "dev\(slots[i])",
                   name(gestureTypes, slots[i + 2]), name(actions, slots[i + 3]) + String(format: " (0x%02x)", slots[i + 3])))
    }
}

func describeFeatures(_ pairs: ArraySlice<UInt8>) {
    var it = pairs.makeIterator()
    while let f = it.next(), let v = it.next() {
        log("  feature \(name(features, f)) (0x\(String(format: "%02x", f))) = \(v == 1 ? "ON" : v == 0 ? "off" : "\(v)")")
    }
}

func handle(_ cmd: UInt16, _ p: [UInt8]) {
    switch cmd {
    case 0x8103 where p.count >= 4:
        log(String(format: "product id: %02X%02X%02X (Air 7 = 064812)", p[3], p[2], p[1]))
    case 0x8105:
        log("version: \(String(decoding: p.dropFirst().filter { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self)) [\(hex(p))]")
    case 0x8108: describeGestures(p)
    case 0x810D:
        log("features:"); if p.first == 0 { describeFeatures(p.dropFirst(2)) }
    case Cmd.featureEvent:
        log("feature changed:"); describeFeatures(p.dropFirst(1))
    case 0x8401, 0x8403:
        log("\(cmd == 0x8401 ? "set gesture" : "set feature"): \(p.first == 0 ? "ACCEPTED" : "REJECTED (\(hex(p)))")")
    case Cmd.keyFunctionNotify:
        log("gestures changed elsewhere (phone?): \(hex(p))"); send(Cmd.keyFunction, [0x02, 0x01, 0x02])
    case Cmd.notificationEvent:
        guard let code = p.first else { return }
        let d = Array(p.dropFirst())
        switch code {
        case 0xF1 where d.count >= 4:
            log(">>> TOUCH  bud=\(budNames[d[0]] ?? "\(d[0])") gesture=\(name(gestureTypes, d[2])) action=\(name(actions, d[3]))"
                + (d.count >= 5 ? " scene=\(d[4])" : "") + "  [\(hex(d))]")
        case 0xF2: log(">>> BUTTON event [\(hex(d))]")
        case 0x01: log("battery [\(hex(d))]")
        case 0x02: log("wear/placement [\(hex(d))]")
        case 0x03: log("noise mode [\(hex(d))]")
        default: log("event 0x\(String(format: "%02x", code)) [\(hex(d))]")
        }
    case 0x8100, 0x8205: break
    default: log("rx cmd=0x\(String(format: "%04x", cmd)) [\(hex(p))]")
    }
}

// MARK: - Transport

var channel: IOBluetoothRFCOMMChannel?
var queue: [[UInt8]] = []

func send(_ cmd: UInt16, _ payload: [UInt8]) { queue.append(frame(cmd, payload)) }

final class Delegate: NSObject, IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelOpenComplete(_ ch: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        log(status == kIOReturnSuccess ? "channel \(ch.getID()) open" : "open FAILED (\(status))")
        if status != kIOReturnSuccess { exit(1) }
    }
    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data: UnsafeMutableRawPointer!, length: Int) {
        rx += Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: length))
        for f in drain() { handle(f.cmd, f.payload) }
    }
    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) { log("channel closed"); exit(0) }
}

// BUDS_ADDRESS picks a device; otherwise the first connected paired device offering the OPOv1 service.
let uuid = IOBluetoothSDPUUID(data: Data(serviceUUID))
func controlRecord(_ d: IOBluetoothDevice) -> IOBluetoothSDPServiceRecord? {
    d.getServiceRecord(for: uuid)
        ?? ((d.services as? [IOBluetoothSDPServiceRecord]) ?? []).first { $0.getServiceName() == "oppointeraction" }
}
let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
let found = ProcessInfo.processInfo.environment["BUDS_ADDRESS"].flatMap { IOBluetoothDevice(addressString: $0) }
    ?? paired.first { $0.isConnected() && controlRecord($0) != nil }
guard let device = found else { log("no connected earbuds offering the OPOv1 service — connect them to the Mac"); exit(1) }
guard device.isConnected() else { log("\(device.name ?? "buds") not connected — connect them to the Mac"); exit(1) }
log("device: \(device.name ?? "?")")

device.performSDPQuery(nil)
RunLoop.current.run(until: Date().addingTimeInterval(2.5))

var channelID: BluetoothRFCOMMChannelID = 0
guard let record = controlRecord(device), record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
    log("OPOv1 service not found in SDP records"); exit(1)
}
if let n = record.getServiceName(), n.uppercased().contains("OTA") { log("refusing OTA channel"); exit(1) }
log("OPOv1 service '\(record.getServiceName() ?? "?")' on channel \(channelID)")

let delegate = Delegate()
guard device.openRFCOMMChannelAsync(&channel, withChannelID: channelID, delegate: delegate) == kIOReturnSuccess else {
    log("openRFCOMMChannelAsync failed"); exit(1)
}

// Session setup + full state read, always — so the original gestures are on screen before any write.
send(Cmd.handshake, [])
let events: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x0D, 0x0E, 0x0F, 0x10, 0xF1, 0xF2]
send(Cmd.registerNotification, [UInt8(events.count)] + events)
send(Cmd.productID, [])
send(Cmd.version, [])
send(Cmd.keyFunction, [0x02, 0x01, 0x02])
let featureIDs = features.values.sorted()
send(Cmd.featureSwitch, [UInt8(featureIDs.count)] + featureIDs)

// MARK: - Commands

var args = Array(CommandLine.arguments.dropFirst())
let verb = args.first ?? "monitor"
var writes = false

func setSlots(_ slots: [(UInt8, UInt8, UInt8)]) {   // (device, type, action)
    var payload: [UInt8] = [UInt8(slots.count)]
    for (d, t, a) in slots { payload += [d, 0x01, t, a] }
    send(Cmd.setKeyFunction, payload); writes = true
}

switch verb {
case "monitor": break
case "left-off":
    setSlots(["double", "triple", "hold"].map { (0x01, gestureTypes[$0]!, 0x00) })
case "set":
    guard args.count == 4, let d: UInt8 = ["L": 1, "R": 2][args[1].uppercased()],
          let t = gestureTypes[args[2]], let a = actions[args[3]] else {
        print("usage: set L|R double|triple|hold \(actions.keys.sorted().joined(separator: "|"))"); exit(2)
    }
    setSlots([(d, t, a)])
case "restore":
    guard args.count == 2, args[1].count % 8 == 0 else { print("usage: restore <gestures hex>"); exit(2) }
    let s = args[1]; var bytes: [UInt8] = []
    var i = s.startIndex
    while i < s.endIndex { let j = s.index(i, offsetBy: 2); bytes.append(UInt8(s[i..<j], radix: 16)!); i = j }
    setSlots(stride(from: 0, to: bytes.count, by: 4).map { (bytes[$0], bytes[$0 + 2], bytes[$0 + 3]) })
case "feature":
    guard args.count == 3, let f = features[args[1]], ["on", "off"].contains(args[2]) else {
        print("usage: feature \(features.keys.sorted().joined(separator: "|")) on|off"); exit(2)
    }
    send(Cmd.setFeatureSwitch, [f, args[2] == "on" ? 1 : 0]); writes = true
default:
    print("unknown command \(verb)"); exit(2)
}
if writes {   // read back what the buds actually hold now
    send(Cmd.keyFunction, [0x02, 0x01, 0x02])
    send(Cmd.featureSwitch, [UInt8(featureIDs.count)] + featureIDs)
}

// Pace writes: one frame every 350 ms once the channel is open.
Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { t in
    guard let ch = channel, ch.isOpen(), !queue.isEmpty else { return }
    var f = queue.removeFirst()
    let r = ch.writeSync(&f, length: UInt16(f.count))
    if r != kIOReturnSuccess { log("write failed (\(r)) for \(hex(f))") }
    if queue.isEmpty && verb == "monitor" { log("listening for touch events — tap the buds, Ctrl-C to quit") }
}

let runFor = verb == "monitor" ? (Double(ProcessInfo.processInfo.environment["SECONDS"] ?? "") ?? .infinity) : 6
RunLoop.current.run(until: runFor.isInfinite ? .distantFuture : Date().addingTimeInterval(runFor))
channel?.close()
