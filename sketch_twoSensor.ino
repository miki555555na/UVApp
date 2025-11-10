#include <M5StickCPlus2.h>
#include <NimBLEDevice.h>
#include <NimBLEUtils.h>       // UUID変換などのユーティリティ
#include <NimBLEServer.h>      // サーバー管理用
#include "DFRobot_UVIndex240370Sensor.h"
#include "ClosedCube_TCA9548A.h"
#include <Wire.h>

#define PaHub_I2C_ADDRESS (0x70)
#define FRONT    (1)
#define X_LOCAL  (100)
#define Y_LOCAL  (35)
#define X_OFFSET (160)
#define Y_OFFSET (30)
#define SAMPLE_RATE_HZ 20
#define BUFFER_SIZE (SAMPLE_RATE_HZ * 60) 
#define LED_PIN 19

#define SERVICE_UUID "a86e5f7e-fa49-42a0-b02d-9cd533f66906" //サーバーのサービスのID
#define CHARACTERISTIC_UUID "3ec97e0d-2780-4cc2-9ff5-1c4ad04786fe"//サービス内のCharacteristicのID


NimBLECharacteristic *pCharacteristic;
NimBLEAdvertisementData scanResponseData;
bool deviceConnected = false;

ClosedCube::Wired::TCA9548A tca9548a;

// UVセンサーのインスタンス（Wire と Wire1をそれぞれ使用）
DFRobot_UVIndex240370Sensor UVIndex240370Outer(&Wire);  // Wire (Grove Cポート)
DFRobot_UVIndex240370Sensor UVIndex240370Inner(&Wire); // Wire1 (Grove Aポート)

float damage = 0; //積算ダメージ
const uint32_t intervalSec = 5;       // 紫外線測定間隔（秒）
float az_buffer[BUFFER_SIZE];//1分間で20x60=1200個のデータ、Z軸加速度データを保持
int buffer_index = 0;//書き込み位置
bool buffer_filled = false;//最初の１分(1200個のデータに)達しているか
unsigned long lastSampleTime = 0;//最後にセンサ値を呼んだ時刻(ミリ秒)
const int interval_ms = 1000 / SAMPLE_RATE_HZ; //サンプリング間隔、毎回50msおきに実行するタイマー

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override {
    Serial.println("✅ BLE Connected");

    // UVセンサなどの再初期化処理
    Wire.begin();
    tca9548a.address(PaHub_I2C_ADDRESS);
    tca9548a.selectChannel(1);
    UVIndex240370Outer.begin();
    tca9548a.selectChannel(2);
    UVIndex240370Inner.begin();
  }

  void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override {
    Serial.print("⚠️ BLE Disconnected. Reason code: ");
    Serial.println(reason);

    // 再度広告開始して再接続を待つ
    NimBLEDevice::startAdvertising();
  }
};




void setup() {
 
  M5.begin();
  pinMode(LED_PIN, OUTPUT);
  
  

  // シリアルモニタの初期化(Arduinoとパソコン間でのシリアル通信)
  Serial.begin(115200);
  M5.Imu.begin();

  // I2Cの初期化
  Wire.begin(); // Grove Aポート: SDA=32, SCL=33
  delay(500);
  tca9548a.address(PaHub_I2C_ADDRESS);

  tca9548a.selectChannel(1);
  tca9548a.selectChannel(2);

  //センサー1の初期化
  while (UVIndex240370Outer.begin() != true) {
    M5.Lcd.println("Sensor1 initialize failed!!");
    delay(1000);
  }

  //センサー2の初期化
  while (UVIndex240370Inner.begin() != true) {
    M5.Lcd.println("Sensor2 initialize failed!!");
    Serial.println("Sensor2 initialization failed!");
    delay(2000);
  }
 M5.Lcd.println("All Sensors initialized successfully!");
  NimBLEDevice::init("M5_UV_Device");//クライアントがBLEスキャンした時に表示される

  NimBLEServer *pServer = NimBLEDevice::createServer();//BLEのサーバーオブジェクトを生成し、そのサーバーへのポインタ
  pServer->setCallbacks(new ServerCallbacks()); //pServerに接続、切断のイベントを受け取るコールバックを登録
  NimBLEService *pService = pServer->createService(SERVICE_UUID);//新しいサービスを作成
  pCharacteristic = pService->createCharacteristic(
                    CHARACTERISTIC_UUID,
                    NIMBLE_PROPERTY::READ |
                    NIMBLE_PROPERTY::NOTIFY
                  );//指定したCharacteristicを作成、
                    //プロパティとして、READ(クライアントから読み取り可能)、NOTIFY(サーバーから通知可能)
  // 通知用CCCDの値 初期は通知無効
  static uint8_t cccd_value[2] = {0x00, 0x00};

  NimBLEDescriptor* cccd = new NimBLEDescriptor(
    "2902",                      // UUID文字列
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE,  // 読み書き可能
    2,                          // サイズ2バイト
    pCharacteristic             // 関連付けるCharacteristic
  );


  cccd->setValue(cccd_value, 2);

  pCharacteristic->addDescriptor(cccd);

  pService->start();//サービスの開始処理
  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();//BLEサーバーは、自分が接続可能であることを周囲に「宣伝」する(BLEデバイスの広告を管理するオブジェクトを取得)
  pAdvertising->addServiceUUID(SERVICE_UUID);  // 明示的にサービスUUIDを追加
  scanResponseData.setName("M5_UV_Device");
  pAdvertising->setScanResponseData(scanResponseData);
  pAdvertising->start();//実際にスキャン可能状態を開始
  
}

void displaySensorData(int yStart,  uint16_t index,const char* label) {
  M5.Lcd.fillRect(0, yStart, 320, 70, BLACK); // 表示位置をクリア
  M5.Lcd.setCursor(0, yStart, 1);
  M5.Lcd.printf("[%s]\n", label);
  M5.Lcd.printf("index: %d\n", index);
}

void loop() {
  tca9548a.selectChannel(1);
  // 外側データ取得
  //uint16_t voltage_out = UVIndex240370Outer.readUvOriginalData();
  uint16_t index_out = UVIndex240370Outer.readUvIndexData();
  uint16_t level_out = UVIndex240370Outer.readRiskLevelData();
  
  tca9548a.selectChannel(2);
  // 内側データ取得
  //uint16_t voltage_in = UVIndex240370Inner.readUvOriginalData();
  uint16_t index_in = UVIndex240370Inner.readUvIndexData();
  uint16_t level_in = UVIndex240370Inner.readRiskLevelData();

 


 if (index_out >= 3 & index_in >=3){
   // センサーのデータを表示
     displaySensorData(60, index_out, "Outer");
     displaySensorData(150, index_in, "Inner");
 }else{
      M5.Lcd.fillRect(0, 60, 320, 70, BLACK);
      M5.Lcd.fillRect(0, 150, 320, 70, BLACK);

 }

  //データを送る
  // 送信用データを構築
  String bleData = "UVindex_out=" + String(index_out) +
                   ",UVindex_in=" + String(index_in) +
                   ",ts=" + String(millis());


  pCharacteristic->setValue(bleData.c_str());
  pCharacteristic->notify();


  M5.Lcd.setCursor(0, 0);
  M5.Lcd.printf("Battery Level = %3d %%\n", M5.Power.getBatteryLevel());
  // 表示を塗りつぶして更新
  M5.Lcd.fillRect(10, 240, 100, 16, BLACK);
  M5.Lcd.setCursor(10, 10);
  M5.Lcd.setTextColor(WHITE, BLACK);
  delay(intervalSec * 1000); 
}

