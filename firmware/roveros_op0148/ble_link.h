// BLE peripheral speaking the Nordic UART Service — the same UUIDs
// lib/core/constants/app_config.dart hard-codes on the app side, and the
// same characteristic roles lib/services/transport/bluetooth_transport.dart
// expects: RX is written by the phone, TX is subscribed to and notified.
#pragma once

#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

#include <functional>

#include "wire_protocol.h"

#ifndef DEVICE_NAME
#define DEVICE_NAME "ROVEROS-OPTIMUS"
#endif

static const char* const kNusServiceUuid =
    "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
static const char* const kNusRxUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
static const char* const kNusTxUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

class BleLink {
 public:
  using LineHandler = std::function<void(const String&)>;

  void begin(LineHandler onLine) {
    onLine_ = onLine;

    BLEDevice::init(DEVICE_NAME);
    BLEDevice::setMTU(247);  // >= AppConfig.preferredMtu (185) on the app side.

    server_ = BLEDevice::createServer();
    server_->setCallbacks(new ServerCallbacks(this));

    BLEService* service = server_->createService(kNusServiceUuid);

    rxChar_ = service->createCharacteristic(
        kNusRxUuid, BLECharacteristic::PROPERTY_WRITE |
                        BLECharacteristic::PROPERTY_WRITE_NR);
    rxChar_->setCallbacks(new RxCallbacks(this));

    txChar_ = service->createCharacteristic(
        kNusTxUuid, BLECharacteristic::PROPERTY_NOTIFY);
    txChar_->addDescriptor(new BLE2902());

    service->start();

    BLEAdvertising* advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(kNusServiceUuid);
    advertising->setScanResponse(true);
    BLEDevice::startAdvertising();
  }

  bool isConnected() const { return connected_; }

  void send(const String& frame) {
    if (!connected_ || txChar_ == nullptr) return;
    txChar_->setValue((uint8_t*)frame.c_str(), frame.length());
    txChar_->notify();
  }

 private:
  class ServerCallbacks : public BLEServerCallbacks {
   public:
    explicit ServerCallbacks(BleLink* owner) : owner_(owner) {}
    void onConnect(BLEServer*) override { owner_->connected_ = true; }
    void onDisconnect(BLEServer*) override {
      owner_->connected_ = false;
      owner_->rxBuffer_ = "";
      // A dropped BLE link must not leave motors latched on; the caller's
      // watchdog is a backstop, but re-advertising promptly matters too.
      BLEDevice::startAdvertising();
    }

   private:
    BleLink* owner_;
  };

  class RxCallbacks : public BLECharacteristicCallbacks {
   public:
    explicit RxCallbacks(BleLink* owner) : owner_(owner) {}
    void onWrite(BLECharacteristic* characteristic) override {
      std::string value = characteristic->getValue();
      owner_->ingest(value.data(), value.length());
    }

   private:
    BleLink* owner_;
  };

  // Reassembles frames split across BLE packets — the firmware-side twin of
  // `_ingest()` in bluetooth_transport.dart.
  void ingest(const char* data, size_t length) {
    for (size_t i = 0; i < length; i++) {
      char c = data[i];
      if (c == Proto::kTerminator) {
        if (rxBuffer_.length() > 0 && onLine_) onLine_(rxBuffer_);
        rxBuffer_ = "";
        continue;
      }
      if (rxBuffer_.length() < Proto::kMaxFrameLength) rxBuffer_ += c;
    }
  }

  BLEServer* server_ = nullptr;
  BLECharacteristic* rxChar_ = nullptr;
  BLECharacteristic* txChar_ = nullptr;
  volatile bool connected_ = false;
  String rxBuffer_;
  LineHandler onLine_;
};
