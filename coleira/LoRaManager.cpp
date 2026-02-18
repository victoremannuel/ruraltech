/**
 * @file LoRaManager.cpp
 * @brief Implementação de envio/recepção segura no enlace LoRa.
 */
#include "LoRaManager.h"
#include "Logger.h"

bool LoRaManager::begin() {
  const int state = radio_.begin(cfg::LORA_FREQ_MHZ, cfg::LORA_BW, cfg::LORA_SF, cfg::LORA_CR, cfg::LORA_SYNC_WORD);
  if (state != RADIOLIB_ERR_NONE) {
    LOGE("Falha LoRa begin=%d", state);
    return false;
  }
  return true;
}

bool LoRaManager::sendFrame(LoRaFrame& frame) {
  uint8_t plain[256];
  memset(frame.tag, 0, sizeof(frame.tag));
  const size_t packedLen = LoRaProtocol::encodePlain(frame, plain, sizeof(plain));
  if (!packedLen || packedLen < 16) return false;
  const size_t cipherLen = packedLen - 16;

  uint8_t out[300];
  memcpy(out, frame.nonce, 12);  // nonce em claro para verificação HMAC
  crypto_.encryptAndSign(plain, cipherLen, out + 12, frame.tag, frame.nonce);
  memcpy(out + 12 + cipherLen, frame.tag, 16);
  return radio_.transmit(out, 12 + cipherLen + 16) == RADIOLIB_ERR_NONE;
}

bool LoRaManager::receiveFrame(LoRaFrame& frame, uint32_t windowMs) {
  uint32_t start = millis();
  while (millis() - start < windowMs) {
    uint8_t buf[300];
    size_t len = sizeof(buf);
    int s = radio_.receive(buf, len);
    if (s == RADIOLIB_ERR_NONE) {
      if (len < 28) return false;
      lastRssi_ = radio_.getRSSI();
      lastSnr_ = radio_.getSNR();
      const uint8_t* nonce = buf;
      const size_t cipherLen = len - 28;
      const uint8_t* cipher = buf + 12;
      const uint8_t* tag = buf + 12 + cipherLen;
      uint8_t plain[256];
      if (!crypto_.verifyAndDecrypt(cipher, cipherLen, tag, plain, nonce)) return false;
      memcpy(plain + cipherLen, tag, 16);
      if (!LoRaProtocol::decodePlain(plain, cipherLen + 16, frame)) return false;
      if (frame.seq <= lastSeqSeen_) {
        LOGW("Replay detectado seq=%lu", frame.seq);
        return false;
      }
      lastSeqSeen_ = frame.seq;
      return true;
    }
    delay(5);
  }
  return false;
}
