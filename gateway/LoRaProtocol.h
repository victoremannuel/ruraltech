/**
 * @file LoRaProtocol.h
 * @brief Contrato binário LoRa com nonce, tag e proteção anti-replay.
 */
#pragma once
#include <Arduino.h>
#include "Types.h"

struct LoRaFrame {
  uint32_t deviceId = 0;
  MsgType msgType = MsgType::HEARTBEAT;
  uint32_t seq = 0;
  uint32_t timestamp = 0;
  uint8_t nonce[12]{};
  uint8_t payloadLen = 0;
  uint8_t payload[128]{};
  uint8_t tag[16]{};
};

class LoRaProtocol {
 public:
  static size_t encodePlain(const LoRaFrame& f, uint8_t* out, size_t outMax);
  static bool decodePlain(const uint8_t* in, size_t len, LoRaFrame& f);
};
