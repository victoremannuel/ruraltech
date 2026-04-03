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
  replayPrefsReady_ = replayPrefs_.begin("lora_rx", false);
  if (!replayPrefsReady_) {
    LOGW("NVS indisponivel para anti-replay da coleira (RAM only).");
    return true;
  }

  lastSeqSeen_ = replayPrefs_.getULong("last_seq", 0);
  LOGI("Anti-replay downlink restaurado last_seq=%lu", lastSeqSeen_);
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
  const int txState = radio_.transmit(out, 12 + cipherLen + 16);
  if (txState == RADIOLIB_ERR_NONE) {
    LOGI(
        "LoRa TX ok type=%u seq=%lu target=%lu scope=%016llX bytes=%u",
        (unsigned)frame.msgType,
        (unsigned long)frame.seq,
        (unsigned long)frame.deviceId,
        (unsigned long long)frame.scopeId,
        (unsigned)(12 + cipherLen + 16));
    return true;
  }
  LOGW(
      "LoRa TX falhou type=%u seq=%lu target=%lu err=%d",
      (unsigned)frame.msgType,
      (unsigned long)frame.seq,
      (unsigned long)frame.deviceId,
      txState);
  return false;
}

bool LoRaManager::receiveFrame(LoRaFrame& frame, uint32_t windowMs) {
  uint32_t start = millis();
  while (millis() - start < windowMs) {
    uint8_t buf[300];
    size_t len = sizeof(buf);
    int s = radio_.receive(buf, len);
    if (s == RADIOLIB_ERR_NONE) {
      const size_t packetLen = radio_.getPacketLength();
      if (packetLen == 0 || packetLen > sizeof(buf)) {
        LOGW("LoRa RX descartado: packet_len_invalido=%u", (unsigned)packetLen);
        continue;
      }
      len = packetLen;
      if (len < 28) continue;
      lastRssi_ = radio_.getRSSI();
      lastSnr_ = radio_.getSNR();
      LOGI(
          "LoRa RX raw len=%u rssi=%d snr=%.1f",
          (unsigned)len,
          (int)lastRssi_,
          lastSnr_);
      const uint8_t* nonce = buf;
      const size_t cipherLen = len - 28;
      const uint8_t* cipher = buf + 12;
      const uint8_t* tag = buf + 12 + cipherLen;
      uint8_t plain[256];
      if (!crypto_.verifyAndDecrypt(cipher, cipherLen, tag, plain, nonce)) {
        LOGW("LoRa RX descartado: decrypt_or_hmac_failed len=%u", (unsigned)len);
        continue;
      }
      memcpy(plain + cipherLen, tag, 16);
      if (!LoRaProtocol::decodePlain(plain, cipherLen + 16, frame)) {
        LOGW("LoRa RX descartado: invalid_plain_frame len=%u", (unsigned)len);
        continue;
      }

      // A coleira só deve consumir comandos destinados a ela (ou broadcast).
      const bool targetMatch = frame.deviceId == cfg::DEVICE_ID || frame.deviceId == 0;
      if (!targetMatch) {
        LOGI(
            "LoRa RX ignorado: target=%lu self=%lu",
            (unsigned long)frame.deviceId,
            (unsigned long)cfg::DEVICE_ID);
        continue;
      }

      const bool downlinkCommand =
          frame.msgType == MsgType::SET_FENCE ||
          frame.msgType == MsgType::SET_HERDING_PLAN ||
          frame.msgType == MsgType::SET_PARAMS ||
          frame.msgType == MsgType::PING;
      if (!downlinkCommand) {
        LOGI("LoRa RX ignorado: unsupported_type=%u", (unsigned)frame.msgType);
        continue;
      }

      if (frame.seq <= lastSeqSeen_) {
        LOGW("Replay detectado seq=%lu", frame.seq);
        continue;
      }
      LOGI(
          "LoRa RX aceito type=%u seq=%lu scope=%016llX",
          (unsigned)frame.msgType,
          (unsigned long)frame.seq,
          (unsigned long long)frame.scopeId);
      lastSeqSeen_ = frame.seq;
      if (replayPrefsReady_ &&
          replayPrefs_.putULong("last_seq", lastSeqSeen_) != sizeof(uint32_t)) {
        LOGW("Falha ao persistir anti-replay da coleira seq=%lu", lastSeqSeen_);
      }
      return true;
    }
    delay(5);
  }
  return false;
}
