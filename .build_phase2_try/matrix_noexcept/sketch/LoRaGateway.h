#line 1 "/Users/victor/Downloads/code/ruraltech/gateway-matriz/LoRaGateway.h"
/**
 * @file LoRaGateway.h
 * @brief Ponte LoRa <-> app com criptografia e anti-replay.
 */
#pragma once
#include <RadioLib.h>
#include <Preferences.h>
#include "config.h"
#include "LoRaProtocol.h"
#include "CryptoEngine.h"

class LoRaGateway {
 public:
  LoRaGateway() : radio_(new Module(cfg::PIN_LORA_CS, cfg::PIN_LORA_DIO0, cfg::PIN_LORA_RST, cfg::PIN_LORA_DIO1)) {}
  bool begin();
  bool receive(LoRaFrame& frame);
  bool send(LoRaFrame& frame);

 private:
  SX1276 radio_;
  CryptoEngine crypto_;
  Preferences replayPrefs_;
  bool replayPrefsReady_ = false;
  uint32_t lastSeqPerDevice_[cfg::LORA_REPLAY_TRACKED_DEVICES]{};
  uint32_t deviceIds_[cfg::LORA_REPLAY_TRACKED_DEVICES]{};
  void loadReplayState();
  void persistReplayState();
  uint8_t idxForDevice(uint32_t id);
};
