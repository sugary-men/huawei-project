// CampusPilot 自律魔方参考固件
// 目标硬件：ESP32-C3 SuperMini + MPU6050 + 3.7V 锂电池
// Arduino IDE 依赖：ESP32 board package、Adafruit MPU6050、Adafruit Unified Sensor
//
// BLE 协议与 HarmonyOS 端 FocusProtocol.ets 保持一致：
//   Service UUID:        0000ffe0-0000-1000-8000-00805f9b34fb
//   Notify UUID:         0000ffe1-0000-1000-8000-00805f9b34fb
//   Notification 数据:   "pitch,roll,yaw\n"，单位度，UTF-8
//
// 建议接线：MPU6050 SDA -> GPIO8，SCL -> GPIO9，VCC/3V3，GND -> GND。
// 实际引脚按开发板丝印调整。上传前先断开电池，避免串口与电源冲突。

#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define FOCUS_SDA 8
#define FOCUS_SCL 9
#define FOCUS_SERVICE_UUID "0000ffe0-0000-1000-8000-00805f9b34fb"
#define FOCUS_NOTIFY_UUID  "0000ffe1-0000-1000-8000-00805f9b34fb"
#define DEVICE_NAME "CampusCube"

Adafruit_MPU6050 mpu;
BLEServer* server = nullptr;
BLECharacteristic* notifyCharacteristic = nullptr;
bool clientConnected = false;
uint32_t lastSampleAt = 0;

class FocusServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    clientConnected = true;
    Serial.println("BLE client connected");
  }

  void onDisconnect(BLEServer*) override {
    clientConnected = false;
    Serial.println("BLE client disconnected; advertising again");
    delay(200);
    BLEDevice::startAdvertising();
  }
};

class FocusCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    String value = characteristic->getValue().c_str();
    value.trim();
    if (value == "PING") {
      notifyCharacteristic->setValue("PONG\n");
      notifyCharacteristic->notify();
    }
  }
};

void setup() {
  Serial.begin(115200);
  delay(300);
  Wire.begin(FOCUS_SDA, FOCUS_SCL);

  if (!mpu.begin()) {
    Serial.println("MPU6050 not found; check SDA/SCL and power");
    while (true) delay(1000);
  }
  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
  mpu.setGyroRange(MPU6050_RANGE_500_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

  BLEDevice::init(DEVICE_NAME);
  server = BLEDevice::createServer();
  server->setCallbacks(new FocusServerCallbacks());

  BLEService* service = server->createService(FOCUS_SERVICE_UUID);
  notifyCharacteristic = service->createCharacteristic(
    FOCUS_NOTIFY_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY |
    BLECharacteristic::PROPERTY_WRITE
  );
  notifyCharacteristic->addDescriptor(new BLE2902());
  notifyCharacteristic->setCallbacks(new FocusCharacteristicCallbacks());
  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(FOCUS_SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("CampusCube advertising; service 0000ffe0");
}

void loop() {
  if (!clientConnected || notifyCharacteristic == nullptr) {
    delay(50);
    return;
  }

  uint32_t now = millis();
  if (now - lastSampleAt < 100) return;
  lastSampleAt = now;

  sensors_event_t acceleration;
  sensors_event_t gyro;
  sensors_event_t temperature;
  mpu.getEvent(&acceleration, &gyro, &temperature);

  float pitch = atan2(acceleration.acceleration.y, acceleration.acceleration.z) * 180.0 / PI;
  float roll = atan2(-acceleration.acceleration.x,
    sqrt(acceleration.acceleration.y * acceleration.acceleration.y +
      acceleration.acceleration.z * acceleration.acceleration.z)) * 180.0 / PI;
  float yaw = gyro.gyro.z * 180.0 / PI;

  String payload = String(pitch, 2) + "," + String(roll, 2) + "," + String(yaw, 2) + "\n";
  notifyCharacteristic->setValue(payload.c_str());
  notifyCharacteristic->notify();
}
