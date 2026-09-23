// The iPhone side of the connection: CoreBluetooth to the buds' OPOv1 GATT service, kept up in
// the background (bluetooth-central) so battery events keep reaching the widget.

import CoreBluetooth
import SwiftUI
import WidgetKit

struct TouchEvent: Identifiable {
    let id = UUID()
    let date: Date
    let symbol: String
    let title: String
    let detail: String
    let isTouch: Bool
}

final class BudsModel: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum LinkState: Equatable {
        case bluetoothOff, searching, connecting
        /// Connected over BLE but the buds aren't answering: another device (a Mac running Buds,
        /// realme Link) holds their control session.
        case busy
        case connected
    }

    static let service = CBUUID(string: "000008A4-0000-1000-8000-00805F9B34FB")
    static let writeUUID = CBUUID(string: "00000001-0000-1000-8000-00805F9B34FB")
    static let notifyUUID = CBUUID(string: "00000002-0000-1000-8000-00805F9B34FB")
    private static let restoreID = "dev.kalki.buds.central"
    private static let peripheralKey = "peripheral.id"

    @Published private(set) var link: LinkState = .searching
    @Published private(set) var name = "realme Buds"
    @Published private(set) var firmware: String?
    @Published private(set) var battery: [Bud: BatteryReading] = [:]
    @Published private(set) var placement: [Bud: Placement] = [:]
    @Published private(set) var noiseMode: NoiseMode?
    @Published private(set) var eq: EQPreset?
    @Published private(set) var gestures: [GestureSlot: GestureAction] = [:]
    @Published private(set) var features: [UInt8: Bool] = [:]
    @Published private(set) var events: [TouchEvent] = []
    @Published private(set) var ringing = false
    @Published private(set) var lastAnswer: Date?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var framer = OPOFramer()
    private var queue: [Data] = []
    private var pumping = false
    private var helloTimer: Timer?
    private var lastWidgetPush: (snapshot: BudsSnapshot, at: Date)?

    override init() {
        super.init()
        if let saved = SharedStore.load() {
            name = saved.name
            battery = saved.battery
            placement = saved.placement
            noiseMode = saved.noiseMode
            lastAnswer = saved.updated
        }
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID])
    }

    // MARK: Finding the buds

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            link = .bluetoothOff
            return
        }
        if peripheral == nil { findBuds() }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first else { return }
        adopt(restored)
    }

    private func findBuds() {
        // Buds linked to the iPhone for audio usually have an LE link up already.
        if let connected = central.retrieveConnectedPeripherals(withServices: [Self.service]).first {
            adopt(connected)
            central.connect(connected)
            return
        }
        // Buds we've talked to before: a pending connect waits for them indefinitely, even in the background.
        if let saved = UserDefaults.standard.string(forKey: Self.peripheralKey).flatMap(UUID.init(uuidString:)),
           let known = central.retrievePeripherals(withIdentifiers: [saved]).first {
            adopt(known)
            central.connect(known)
            return
        }
        link = .searching
        central.scanForPeripherals(withServices: nil)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertised = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard advertised.localizedCaseInsensitiveContains("realme buds") || advertised.localizedCaseInsensitiveContains("enco") else { return }
        central.stopScan()
        adopt(peripheral)
        central.connect(peripheral)
    }

    private func adopt(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        name = p.name ?? name
        link = .connecting
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.peripheralKey)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        name = p.name ?? name
        p.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        central.connect(p)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        writeChar = nil
        queue.removeAll()
        ringing = false
        link = .connecting
        markStale()
        central.connect(p)   // reconnects whenever the buds come back
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = p.services?.first(where: { $0.uuid == Self.service }) else {
            link = .busy
            return
        }
        p.discoverCharacteristics([Self.writeUUID, Self.notifyUUID], for: service)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] {
            if ch.uuid == Self.writeUUID { writeChar = ch }
            if ch.uuid == Self.notifyUUID { p.setNotifyValue(true, for: ch) }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.notifyUUID, ch.isNotifying else { return }
        startSession()
    }

    // MARK: Session

    /// Hello, subscribe to pushed events, then read everything. If the hello goes unanswered,
    /// someone else holds the session; try again in a while.
    private func startSession() {
        framer.reset()
        send(Cmd.hello)
        let events: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x0D, 0x0E, 0x0F, 0x10, 0xF1, 0xF2]
        send(Cmd.subscribe, [UInt8(events.count)] + events)
        refresh()
        helloTimer?.invalidate()
        helloTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self, self.link != .connected else { return }
            self.link = .busy
            self.markStale()
            self.helloTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                guard let self, self.writeChar != nil, self.link == .busy else { return }
                self.startSession()
            }
        }
    }

    func refresh() {
        guard writeChar != nil else { findBuds(); return }
        send(Cmd.version)
        send(Cmd.battery)
        send(Cmd.anc, [0x01, 0x01])
        send(Cmd.eq)
        send(Cmd.keyFunction, [0x02, 0x01, 0x02])
        let ids = Feature.all.map(\.id)
        send(Cmd.featureSwitch, [UInt8(ids.count)] + ids)
    }

    private func send(_ cmd: UInt16, _ payload: [UInt8] = []) {
        queue.append(framer.frame(cmd, payload))
        pump()
    }

    /// One write at a time, each waiting for its acknowledgement.
    private func pump() {
        guard !pumping, let p = peripheral, let ch = writeChar, !queue.isEmpty else { return }
        pumping = true
        p.writeValue(queue.removeFirst(), for: ch, type: .withResponse)
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        pumping = false
        pump()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.notifyUUID, let value = ch.value else { return }
        for (cmd, payload) in framer.feed(value) { handle(cmd, payload) }
    }

    // MARK: Commands

    func setNoiseMode(_ mode: NoiseMode) {
        noiseMode = mode
        send(Cmd.setANC, [0x01, 0x01, mode.wire])
        pushWidget()
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

    // MARK: Replies and events

    private func handle(_ cmd: UInt16, _ p: [UInt8]) {
        if cmd & Cmd.reply != 0 {
            guard p.first == 0x00 else { return }
            if link != .connected {
                link = .connected
                helloTimer?.invalidate()
            }
            lastAnswer = .now
        }
        switch cmd {
        case Cmd.version | Cmd.reply:
            parseVersion(p)
        case Cmd.battery | Cmd.reply where p.count >= 2:
            parseBattery(p.dropFirst(1))
        case Cmd.anc | Cmd.reply where p.count >= 3:
            if p[1] == 0x01, let mode = NoiseMode(wire: p.count >= 4 ? p[3] : p[2]) { noiseMode = mode; pushWidget() }
        case Cmd.eq | Cmd.reply where p.count >= 2:
            eq = EQPreset(rawValue: p[1])
        case Cmd.eqNotify:
            if let v = (p.count >= 2 && p[0] == 0 ? p[1] : p.first) { eq = EQPreset(rawValue: v) }
        case Cmd.keyFunction | Cmd.reply where p.count >= 2:
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
        case Cmd.featureSwitch | Cmd.reply where p.count >= 2:
            for (id, v) in opoPairs(p.dropFirst(2), count: Int(p[1])) { features[id] = v == 1 }
        case Cmd.featureEvent where !p.isEmpty:
            for (id, v) in opoPairs(p.dropFirst(1), count: Int(p[0])) { features[id] = v == 1 }
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
            for (id, v) in opoPairs(d.dropFirst(1), count: Int(d[0])) {
                guard let bud = Bud(rawValue: id), bud != .enclosure else { continue }
                let new = Placement(v)
                if let old = placement[bud], old != new {
                    log(TouchEvent(date: .now, symbol: bud == .left ? "l.circle" : "r.circle",
                                   title: "\(bud.label) bud: \(new.label)", detail: "was \(old.label.lowercased())", isTouch: false))
                }
                placement[bud] = new
            }
            pushWidget()
        case 0x03 where d.count >= 3:
            if d[0] == 0x01, let mode = NoiseMode(wire: d[2]) { noiseMode = mode; pushWidget() }
        case 0xF1 where d.count >= 4:
            let bud = Bud(rawValue: d[0])
            let gesture = Gesture(rawValue: d[2])?.label ?? "Gesture \(d[2])"
            let action = GestureAction(rawValue: d[3])?.label ?? "action \(d[3])"
            log(TouchEvent(date: .now, symbol: "hand.tap.fill", title: "\(bud?.label ?? "Bud \(d[0])") · \(gesture)",
                           detail: action, isTouch: true))
        default:
            break
        }
    }

    private func parseBattery(_ b: ArraySlice<UInt8>) {
        guard let count = b.first else { return }
        for (id, raw) in opoPairs(b.dropFirst(), count: Int(count)) {
            guard let bud = Bud(rawValue: id) else { continue }
            let level = Int(raw & 0x7F)
            battery[bud] = BatteryReading(percent: level == 0 ? nil : level, charging: raw & 0x80 != 0)
        }
        pushWidget()
    }

    /// "1,1,111,1,2,1.1.0.66,…": triples of (bud, component, version); component 2 is the firmware.
    private func parseVersion(_ p: [UInt8]) {
        let parts = String(decoding: p.dropFirst(2), as: UTF8.self).split(separator: ",").map(String.init)
        for i in stride(from: 0, to: parts.count - 2, by: 3) where parts[i] == "1" && parts[i + 1] == "2" {
            firmware = parts[i + 2]
        }
    }

    private func log(_ event: TouchEvent) {
        withAnimation(.smooth(duration: 0.3)) {
            events.insert(event, at: 0)
            if events.count > 40 { events.removeLast(events.count - 40) }
        }
    }

    // MARK: Widget

    private var snapshot: BudsSnapshot {
        BudsSnapshot(name: name, battery: battery, placement: placement, noiseMode: noiseMode,
                     updated: lastAnswer ?? .now, live: link == .connected)
    }

    /// Saves the state for the widget and asks it to redraw. iOS rations widget reloads, so this
    /// only spends one when something visible changed or the last push is getting old.
    private func pushWidget() {
        let now = snapshot
        SharedStore.save(now)
        if let last = lastWidgetPush {
            let visibleChange = last.snapshot.battery != now.battery || last.snapshot.placement != now.placement
                || last.snapshot.noiseMode != now.noiseMode || last.snapshot.live != now.live
            guard visibleChange || Date.now.timeIntervalSince(last.at) > 15 * 60 else { return }
        }
        lastWidgetPush = (now, .now)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func markStale() {
        pushWidget()
    }
}
