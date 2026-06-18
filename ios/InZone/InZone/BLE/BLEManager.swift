import Foundation
import CoreBluetooth
import os

class BLEManager: NSObject, ObservableObject {
    @Published var anchors: [UUID: Anchor] = [:]
    @Published var isScanning = false
    @Published var bluetoothState: CBManagerState = .unknown

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var chars: [UUID: CharSet] = [:]
    private let log = Logger(subsystem: "com.inzone", category: "BLE")

    // QANI firmware exposes no anchor-id characteristic, so we assign a small
    // logical id to each board the first time we see it (stable within a run).
    private var anchorIdMap: [UUID: UInt8] = [:]
    private var nextAnchorId: UInt8 = 0

    var onAccessoryConfig: ((UUID, Data) -> Void)?
    var onUwbDidStart: ((UUID) -> Void)?
    var onUwbDidStop: ((UUID) -> Void)?
    var onDisconnect: ((UUID) -> Void)?

    struct CharSet {
        var rx: CBCharacteristic?   // write: phone -> accessory
        var tx: CBCharacteristic?   // notify: accessory -> phone
        var sec: CBCharacteristic?  // read (just-works): triggers pairing
    }

    var bluetoothStateText: String {
        switch bluetoothState {
        case .poweredOn:    return "On"
        case .poweredOff:   return "Off"
        case .unauthorized: return "Unauthorized"
        case .unsupported:  return "Unsupported"
        default:            return "Unknown"
        }
    }

    var connectedAnchorIds: [UUID] {
        anchors.values.filter(\.isConnected).map(\.id)
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func startScanning() {
        guard central.state == .poweredOn else { return }
        isScanning = true
        central.scanForPeripherals(
            withServices: [BLE.transportService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        log.info("Scanning started")
    }

    func stopScanning() {
        central.stopScan()
        isScanning = false
        log.info("Scanning stopped")
    }

    func connect(_ anchorUUID: UUID) {
        guard let peripheral = peripherals[anchorUUID] else { return }
        anchors[anchorUUID]?.state = .connecting
        central.connect(peripheral, options: nil)
    }

    func disconnect(_ anchorUUID: UUID) {
        guard let peripheral = peripherals[anchorUUID] else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    func sendInitialize(to anchorUUID: UUID) {
        NIDiagnostics.shared.noteInitSent()
        send(to: anchorUUID, data: NIMessage.encodeInitialize())
    }

    func sendConfigure(to anchorUUID: UUID, shareableConfig: Data) {
        NIDiagnostics.shared.noteConfigureSent()
        send(to: anchorUUID, data: NIMessage.encodeConfigure(shareableConfig: shareableConfig))
    }

    func sendStop(to anchorUUID: UUID) {
        send(to: anchorUUID, data: NIMessage.encodeStop())
    }

    func identify(_ anchorUUID: UUID, seconds: UInt8 = 5) {
        // No identify characteristic on the QANI firmware; nothing to do.
    }

    private func send(to anchorUUID: UUID, data: Data) {
        guard let cs = chars[anchorUUID], let rx = cs.rx,
              let p = peripherals[anchorUUID] else {
            log.warning("Cannot send to \(anchorUUID): no RX characteristic")
            return
        }
        p.writeValue(data, for: rx, type: .withResponse)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state != .poweredOn { isScanning = false }
        log.info("Bluetooth state: \(self.bluetoothStateText)")
    }

    func centralManager(_ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        peripherals[id] = peripheral

        // QANI advertises its full name (e.g. "DWM3001CDK (1A2B3C4D)") in the
        // scan response. With no anchor-id characteristic, assign a small
        // logical id per board on first sight.
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? "DWM3001CDK"

        if anchors[id] == nil {
            if anchorIdMap[id] == nil {
                anchorIdMap[id] = nextAnchorId
                nextAnchorId &+= 1
            }
            var a = Anchor(id: id, peripheralName: name)
            a.anchorId = anchorIdMap[id] ?? 0
            a.label = name
            anchors[id] = a
        }
        anchors[id]?.rssi = RSSI.intValue
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        peripheral.delegate = self
        anchors[id]?.state = .connected
        peripheral.discoverServices([BLE.transportService])
        log.info("Connected to \(peripheral.name ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager,
                         didFailToConnect peripheral: CBPeripheral, error: Error?) {
        anchors[peripheral.identifier]?.state = .discovered
        log.error("Connect failed: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager,
                         didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        let name = anchors[id]?.displayName ?? "unknown"
        anchors[id]?.state = .discovered
        anchors[id]?.distance = nil
        anchors[id]?.direction = nil
        chars[id] = nil
        onDisconnect?(id)
        log.info("Disconnected from \(name)")
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for svc in services {
            peripheral.discoverCharacteristics(nil, for: svc)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let id = peripheral.identifier
        if chars[id] == nil { chars[id] = CharSet() }

        for c in service.characteristics ?? [] {
            switch c.uuid {
            case BLE.rxChar:
                chars[id]?.rx = c
            case BLE.txChar:
                chars[id]?.tx = c
                peripheral.setNotifyValue(true, for: c)
            case BLE.secChar:
                chars[id]?.sec = c
                // Reading the just-works-secured characteristic triggers BLE
                // pairing, which the QANI firmware expects before ranging.
                peripheral.readValue(for: c)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let id = peripheral.identifier
        guard let data = characteristic.value, !data.isEmpty else { return }

        switch characteristic.uuid {
        case BLE.txChar:
            handleNIMessage(from: id, data: data)
        default:
            break // SEC read response (pairing) — content unused
        }
    }

    private func handleNIMessage(from anchorUUID: UUID, data: Data) {
        switch NIMessage.parse(data) {
        case .accessoryConfig(let payload):
            log.info("Accessory config from \(anchorUUID) (\(payload.count) bytes)")
            NIDiagnostics.shared.noteCfgReceived()
            onAccessoryConfig?(anchorUUID, payload)
        case .uwbDidStart:
            log.info("UWB started on \(anchorUUID)")
            anchors[anchorUUID]?.state = .ranging
            onUwbDidStart?(anchorUUID)
        case .uwbDidStop:
            log.info("UWB stopped on \(anchorUUID)")
            if anchors[anchorUUID]?.state == .ranging {
                anchors[anchorUUID]?.state = .connected
            }
            onUwbDidStop?(anchorUUID)
        case .unknown(let msgId):
            log.warning("Unknown NI message 0x\(String(msgId, radix: 16))")
        case nil:
            break
        }
    }
}
