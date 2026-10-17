import Foundation
import CoreBluetooth

/// BLE connection state for the power meter.
enum BLEConnectionState: String {
    case disconnected
    case scanning
    case connecting
    case connected
}

/// A discovered peripheral, safe to store in @Published state.
struct ScannedPeripheral: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ScannedPeripheral, rhs: ScannedPeripheral) -> Bool {
        lhs.id == rhs.id
    }
}

/// Connects to a BLE Cycling Power meter (e.g. 4iiii Precision 3).
///
/// Parses the standard Cycling Power Measurement characteristic (0x2A63):
///   bytes[0..1] flags (UInt16 LE)
///   bytes[2..3] instantaneous power (Int16 LE, watts)
///   if flags bit 5 (0x0020) set:
///     bytes[4..5] cumulative crank revolutions (UInt16)
///     bytes[6..7] last crank event time (UInt16, 1/1024 s) -> cadence RPM
///
/// Delegate callbacks arrive on the main queue (central created with queue: nil
/// from the main thread), so @Published updates here are main-thread safe.
final class BLEPowerMeterManager: NSObject, ObservableObject {
    @Published var connectionState: BLEConnectionState = .disconnected
    @Published var discoveredDevices: [ScannedPeripheral] = []
    @Published var connectedDeviceName: String?
    @Published var powerWatts: Int?
    @Published var cadenceRpm: Double?

    private var centralManager: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var autoReconnect = false

    private let cyclingPowerService = CBUUID(string: "1818")
    private let powerMeasurementCharacteristic = CBUUID(string: "2A63")

    private var lastCrankRevs: UInt16?
    private var lastCrankEventTime: UInt16?

    override init() {
        super.init()
        // queue: nil -> delegate callbacks on the main queue.
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public control

    func startScan() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices = []
        peripherals = [:]
        // Keep any existing connection; scan only if not connected.
        if connectedPeripheral == nil {
            connectionState = .scanning
        }
        centralManager.scanForPeripherals(withServices: [cyclingPowerService], options: nil)
    }

    func stopScan() {
        centralManager.stopScan()
        if connectedPeripheral == nil {
            connectionState = .disconnected
        }
    }

    func connect(_ device: ScannedPeripheral) {
        guard let peripheral = peripherals[device.id] else { return }
        stopScan()
        autoReconnect = true
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        autoReconnect = false
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        } else {
            connectionState = .disconnected
            connectedDeviceName = nil
        }
    }

    // MARK: - Parsing helpers

    private func u16LE(_ data: Data, offset: Int) -> UInt16? {
        guard data.count >= offset + 2 else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func i16LE(_ data: Data, offset: Int) -> Int16? {
        guard let u = u16LE(data, offset: offset) else { return nil }
        return Int16(bitPattern: u)
    }

    private func handlePowerMeasurement(_ data: Data) {
        guard data.count >= 4 else { return }
        guard let flags = u16LE(data, offset: 0),
              let watts = i16LE(data, offset: 2) else { return }
        powerWatts = Int(watts)

        // Bit 5 (0x0020): crank revolution data present.
        if flags & 0x0020 != 0 {
            guard let revs = u16LE(data, offset: 4),
                  let eventTime = u16LE(data, offset: 6) else { return }
            if let prevRevs = lastCrankRevs, let prevTime = lastCrankEventTime {
                // UInt16 rollover-safe diffs via wrapping subtraction.
                let revDiff = revs &- prevRevs
                let timeDiff = eventTime &- prevTime
                if timeDiff > 0 && revDiff <= 20 {
                    // eventTime is in 1/1024 second units.
                    let seconds = Double(timeDiff) / 1024.0
                    cadenceRpm = (Double(revDiff) / seconds) * 60.0
                }
            }
            lastCrankRevs = revs
            lastCrankEventTime = eventTime
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEPowerMeterManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            connectionState = .disconnected
            connectedDeviceName = nil
            connectedPeripheral = nil
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        peripherals[peripheral.identifier] = peripheral
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Power Meter"
        let device = ScannedPeripheral(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
        }
        discoveredDevices.sort { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectedDeviceName = peripheral.name ?? "Power Meter"
        connectionState = .connected
        powerWatts = nil
        cadenceRpm = nil
        lastCrankRevs = nil
        lastCrankEventTime = nil
        peripheral.discoverServices([cyclingPowerService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        if peripheral.identifier == connectedPeripheral?.identifier {
            connectedPeripheral = nil
            connectedDeviceName = nil
            powerWatts = nil
            cadenceRpm = nil
            if autoReconnect {
                connectionState = .connecting
                // Brief delay before re-connect to let the radio settle.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self, self.autoReconnect else { return }
                    self.centralManager.connect(peripheral, options: nil)
                }
            } else {
                connectionState = .disconnected
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peripheral.identifier == connectedPeripheral?.identifier {
            connectedPeripheral = nil
            connectedDeviceName = nil
            if autoReconnect {
                connectionState = .connecting
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self, self.autoReconnect else { return }
                    self.centralManager.connect(peripheral, options: nil)
                }
            } else {
                connectionState = .disconnected
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEPowerMeterManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == cyclingPowerService {
            peripheral.discoverCharacteristics([powerMeasurementCharacteristic], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else { return }
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == powerMeasurementCharacteristic {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else { return }
        guard characteristic.uuid == powerMeasurementCharacteristic else { return }
        guard let data = characteristic.value else { return }
        handlePowerMeasurement(data)
    }
}
