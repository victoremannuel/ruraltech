/**
 * @file LoRaManager.h
 * @brief Enlace LoRa RFM95 com ACK/NACK e retransmissão simples.
 */
#pragma once
#include <RadioLib.h>
#include <Preferences.h>
#include "config.h"
#include "LoRaProtocol.h"
#include "CryptoEngine.h"

class LoRaManager {
 public:
  LoRaManager() : radio_(new Module(cfg::PIN_LORA_CS, cfg::PIN_LORA_DIO0, cfg::PIN_LORA_RST, cfg::PIN_LORA_DIO1)) {}
  bool begin();
  bool sendFrame(LoRaFrame& frame);
  bool receiveFrame(LoRaFrame& frame, uint32_t windowMs);
  void prepareForDeepSleep();
  int16_t lastRssi() const { return lastRssi_; }
  float lastSnr() const { return lastSnr_; }
  uint32_t txCount() const { return txCount_; }
  uint32_t txFailCount() const { return txFailCount_; }
  uint32_t decryptFailCount() const { return decryptFailCount_; }
  uint32_t nonceMismatchCount() const { return nonceMismatchCount_; }
  uint32_t replayRejectCount() const { return replayRejectCount_; }
  uint32_t lastAcceptedSeq() const { return lastAcceptedSeq_; }

 private:
  SX1276 radio_;
  CryptoEngine crypto_;
  Preferences replayPrefs_;
  bool replayPrefsReady_ = false;
  uint32_t lastSeqSeen_ = 0;
  uint32_t persistedSeqSeen_ = 0;
  uint32_t txCount_ = 0;
  uint32_t txFailCount_ = 0;
  uint32_t decryptFailCount_ = 0;
  uint32_t nonceMismatchCount_ = 0;
  uint32_t replayRejectCount_ = 0;
  uint32_t lastAcceptedSeq_ = 0;
  int16_t lastRssi_ = -120;
  float lastSnr_ = 0.0f;
  bool persistReplayCheckpoint(uint32_t seq);
};
