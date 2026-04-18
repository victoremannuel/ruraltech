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
  bool isReady() const { return ready_; }
  int lastReceiveCode() const { return lastReceiveCode_; }
  size_t lastReceiveLen() const { return lastReceiveLen_; }
  int lastRssi() const { return lastRssi_; }
  float lastSnr() const { return lastSnr_; }
  uint32_t lastRawRxAtMs() const { return lastRawRxAtMs_; }
  uint32_t lastAcceptedRxAtMs() const { return lastAcceptedRxAtMs_; }
  uint32_t rxArmCount() const { return rxArmCount_; }
  uint32_t txCount() const { return txCount_; }
  uint32_t txFailCount() const { return txFailCount_; }
  uint16_t lastIrqFlags() const { return lastIrqFlags_; }
  const char* lastRadioState() const { return lastRadioState_; }
  uint32_t decryptFailCount() const { return decryptFailCount_; }
  uint32_t nonceMismatchCount() const { return nonceMismatchCount_; }
  uint32_t replayRejectCount() const { return replayRejectCount_; }
  uint32_t lastAcceptedSeq() const { return lastAcceptedSeq_; }

 private:
  SX1276 radio_;
  CryptoEngine crypto_;
  Preferences replayPrefs_;
  bool replayPrefsReady_ = false;
  bool ready_ = false;
  bool rxContinuousActive_ = false;
  int lastReceiveCode_ = RADIOLIB_ERR_UNKNOWN;
  size_t lastReceiveLen_ = 0;
  int lastRssi_ = 0;
  float lastSnr_ = 0.0f;
  uint32_t lastRawRxAtMs_ = 0;
  uint32_t lastAcceptedRxAtMs_ = 0;
  uint32_t rxArmCount_ = 0;
  uint32_t txCount_ = 0;
  uint32_t txFailCount_ = 0;
  uint16_t lastIrqFlags_ = 0;
  const char* lastRadioState_ = "boot";
  uint32_t decryptFailCount_ = 0;
  uint32_t nonceMismatchCount_ = 0;
  uint32_t replayRejectCount_ = 0;
  uint32_t lastAcceptedSeq_ = 0;
  uint32_t lastSeqPerDevice_[cfg::LORA_REPLAY_TRACKED_DEVICES]{};
  uint32_t deviceIds_[cfg::LORA_REPLAY_TRACKED_DEVICES]{};
  void loadReplayState();
  void persistReplayState();
  uint8_t idxForDevice(uint32_t id);
  bool armContinuousReceive();
  void setRadioState(const char* state) { lastRadioState_ = state; }
};
