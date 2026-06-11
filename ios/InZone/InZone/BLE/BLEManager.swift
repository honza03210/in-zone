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

    var onAccessoryConfig: ((UUID, Data) -> Void)?
    var onUwbDidStart: ((UUID) -> Void)?
    var onUwbDidStop: ((UUID) -> Void)?
    var onDisconnect: ((UUID) -> Void)?

    struct CharSet {
        var rx: CBCharacteristic?
        var tx: CBCharacteristic?
        var anchorId: CBCharacteristic?
        var label: CBCharacteristic?
        var fwVersion: CBCharacteristic?
        var mode: CBCharacteristic?
        var identify: CBCharacteristic?
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
        send(to: anchorUUID, data: NIMessage.encodeInitialize())
    }

    func sendConfigure(to anchorUUID: UUID, shareableConfig: Data) {
        send(to: anchorUUID, data: NIMessage.encodeConfigure(shareableConfig: shareableConfig))
    }

    func sendStop(to anchorUUID: UUID) {
        send(to: anchorUUID, data: NIMessage.encodeStop())
    }

    func identify(_ anchorUUID: UUID, seconds: UInt8 = 5) {
        guard let cs = chars[anchorUUID], let c = cs.identify,
              let p = peripherals[anchorUUID] else { return }
        p.writeValue(Data([seconds]), for: c, type: .withResponse)
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

        if anchors[id] == nil {
            anchors[id] = Anchor(id: id, peripheralName: peripheral.name ?? "Unknown")
        }
        anchors[id]?.rssi = RSSI.intValue
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        peripheral.delegate = self
        anchors[id]?.state = .connected
        peripheral.discoverServices([BLE.transportService, BLE.infoService])
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
            case BLE.rxChar:        chars[id]?.rx = c
            case BLE.txChar:
                chars[id]?.tx = c
                peripheral.setNotifyValue(true, for: c)
            case BLE.anchorIdChar:
                chars[id]?.anchorId = c
                peripheral.readValue(for: c)
            case BLE.labelChar:
                chars[id]?.label = c
                peripheral.readValue(for: c)
            case BLE.fwVersionChar:
                chars[id]?.fwVersion = c
                peripheral.readValue(for: c)
            case BLE.modeChar:
                chars[id]?.mode = c
                peripheral.readValue(for: c)
            case BLE.identifyChar:  chars[id]?.identify = c
            default: break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let id = peripheral.identifier
        guard let data = characteristic.value, !data.isEmpty else { return }

        switch characteristic.uuid {
        case BLE.anchorIdChar:
            anchors[id]?.anchorId = data[0]
        case BLE.labelChar:
            anchors[id]?.label = BLE.decodeLabel(data)
        case BLE.fwVersionChar:
            anchors[id]?.firmwareVersion = String(data: data, encoding: .utf8) ?? ""
        case BLE.modeChar:
            anchors[id]?.mode = data[0]
        case BLE.txChar:
            handleNIMessage(from: id, data: data)
        default: break
        }
    }

    private func handleNIMessage(from anchorUUID: UUID, data: Data) {
        switch NIMessage.parse(data) {
        case .accessoryConfig(let payload):
            log.info("Accessory config from \(anchorUUID) (\(payload.count) bytes)")
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
