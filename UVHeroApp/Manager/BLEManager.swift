//BLEデバイスからUVインデックス値取得
//受信したUVデータをCoreDataに5分ごとに保存(最大値を保存)

import Foundation
import CoreBluetooth
import SwiftUI
import CoreData

final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // BLEスキャン・接続用
    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var uvCharacteristic: CBCharacteristic?
    // 最新の値
    @Published var currentUVIndexOut: Double = 0.0  // 外側UV
    @Published var currentUVIndexIn: Double = 0.0   // 内側UV
    
    //5分間で最大のUVインデックス値を保持するためのプロパティ
    private var maxUVIndexOut: Double = 0.0
    private var maxUVIndexIn: Double = 0.0
    // 最後に保存した時間
    private var lastSaveTime: Date? = nil
    
    //JSTタイムゾーン
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // デバイス探索
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if isWithinActiveHours(){
                startScanning()
            }else{
                print("⏸ BLE通信は停止中（時間外）")
            }
            
        } else {
            print("Bluetooth状態: \(central.state.rawValue)")
        }
    }
    
    private func startScanning(){
        print("Bluetooth ON: スキャン開始")
        let serviceUUID = CBUUID(string: "a86e5f7e-fa49-42a0-b02d-9cd533f66906")
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
    
    private func isWithinActiveHours() -> Bool {
       let now = Date()
       let calendar = Calendar.current
       var comps = calendar.dateComponents(in: jst, from: now)
       let hour = comps.hour ?? 0
       return (hour >= 5 && hour < 18)
    }
    
    // デバイス発見
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        print("デバイスを発見: \(peripheral.name ?? "名前なし")")
        targetPeripheral = peripheral
        targetPeripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    // 接続完了
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("接続完了: \(peripheral.name ?? "名前なし")")
        peripheral.discoverServices(nil)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        print("💡 データ受信関数が実行されました")
        service.characteristics?.forEach { characteristic in
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    // データ受信
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard isWithinActiveHours() else {
            // 時間外(5~18時以外)なら無視
            return
        }
        //5~18時の間は受信する
        guard let value = characteristic.value,
              let string = String(data: value, encoding: .utf8) else { return }

        DispatchQueue.main.async {
            var receivedOut: Double? = nil // varのままにして、後で値を代入可能にする（警告が出るならletにする）
            var receivedIn: Double? = nil
            
            let components = string.split(separator: ",")
            
            for component in components {
                let parts = component.split(separator: "=")
                if parts.count == 2,
                   let val = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                    
                    switch parts[0].trimmingCharacters(in: .whitespaces) {
                    case "UVindex_out":
                        self.currentUVIndexOut = val 
                        self.maxUVIndexOut = max(self.maxUVIndexOut, val) //最大値更新
                    case "UVindex_in":
                        self.currentUVIndexIn = val 
                        receivedIn = val
                        self.maxUVIndexIn = max(self.maxUVIndexIn, val)
                    case "ts": // 💡 新しくtsのケースを追加
                        break // タイムスタンプは無視
                    default:
                        break
                    }
                }
            }
            
            // 保存タイミング判定
            let now = Date()
            let interval: TimeInterval = 300 // 5分 = 300秒
            // CoreDataに保存すべきかどうかを判断する
            var shouldSave = false
            if let last = self.lastSaveTime {
                if now.timeIntervalSince(last) >= interval {
                    shouldSave = true
                }
            } else if receivedOut != nil || receivedIn != nil {
                // 初回はどちらかの値が受信されたら即保存
                shouldSave = true
            }
            if shouldSave {
                //履歴保存には、5分間で記録した最大値を使用
                self.saveToCoreData(out: self.maxUVIndexOut, inn: self.maxUVIndexIn, now: now)
                
                // 保存後、次の5分間の計測のために最大値をリセット
                self.maxUVIndexOut = 0.0
                self.maxUVIndexIn = 0.0
            }
        }
    }
    
    // CoreData 保存 (引数を Optional から Non-Optional に戻し、必ず最大値を渡すように変更)
    // CoreDataに入れる時はUTC
        private func saveToCoreData(out: Double, inn: Double, now: Date) {
            // Core Dataオブジェクトの定義が外部にあることを前提とします。
            //coredataの読み書きを行う作業場
            let context = PersistenceController.shared.container.viewContext
            
            //取得した作業場を使って、UVRecordのインスタンスを作成
            let record = UVRecord(context: context)
            record.timestamp = now
            record.uvOut = out // 5分間の最大値
            record.uvIn = inn   // 5分間の最大値
            
            do {
                try context.save()
                lastSaveTime = now
                print("✅ UV履歴（最大値）を保存: OUT=\(String(format: "%.1f", out)), IN=\(String(format: "%.1f", inn)) at \(self.formatJST(now))")
            } catch {
                print("❌ Core Data 保存失敗: \(error.localizedDescription)")
                // 保存失敗時はContextをロールバックすることが推奨されます
                context.rollback()
            }
        }
        private func formatJST(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.timeZone = jst
            formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
            return formatter.string(from: date)
        }
    }
