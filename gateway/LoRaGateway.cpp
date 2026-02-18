/** @file LoRaGateway.cpp */
#include "LoRaGateway.h"
#include "Logger.h"

uint8_t LoRaGateway::idxForDevice(uint32_t id) {
  for (uint8_t i = 0; i < 8; ++i) {
    if (deviceIds_[i] == id || deviceIds_[i] == 0) {
      deviceIds_[i] = id;
      return i;
    }
  }
  return 0;
}

bool LoRaGateway::begin() {
  return radio_.begin(cfg::LORA_FREQ_MHZ, 125, 9, 7, 0x12) == RADIOLIB_ERR_NONE;
}

bool LoRaGateway::receive(LoRaFrame& frame) {
  uint8_t buf[300];
  size_t len = sizeof(buf);
  int s = radio_.receive(buf, len);
  if (s != RADIOLIB_ERR_NONE || len < 28) return false;

  const uint8_t* nonce = buf;
  const size_t cipherLen = len - 28;
  const uint8_t* cipher = buf + 12;
  const uint8_t* tag = buf + 12 + cipherLen;
  uint8_t plain[256];
  if (!crypto_.verifyAndDecrypt(cipher, cipherLen, tag, plain, nonce)) return false;
  memcpy(plain + cipherLen, tag, 16);
  if (!LoRaProtocol::decodePlain(plain, cipherLen + 16, frame)) return false;

  const uint8_t idx = idxForDevice(frame.deviceId);
  if (frame.seq <= lastSeqPerDevice_[idx]) {
    LOGW("Replay bloqueado device=%lu seq=%lu", frame.deviceId, frame.seq);
    return false;
  }
  lastSeqPerDevice_[idx] = frame.seq;
  return true;
}

bool LoRaGateway::send(LoRaFrame& frame) {
  uint8_t plain[256];
  memset(frame.tag, 0, sizeof(frame.tag));
  const size_t packedLen = LoRaProtocol::encodePlain(frame, plain, sizeof(plain));
  if (!packedLen || packedLen < 16) return false;
  const size_t cipherLen = packedLen - 16;

  uint8_t out[300];
  memcpy(out, frame.nonce, 12);
  crypto_.encryptAndSign(plain, cipherLen, out + 12, frame.tag, frame.nonce);
  memcpy(out + 12 + cipherLen, frame.tag, 16);
  return radio_.transmit(out, 12 + cipherLen + 16) == RADIOLIB_ERR_NONE;
}
