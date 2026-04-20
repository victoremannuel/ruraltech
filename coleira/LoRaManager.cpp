/**
 * @file LoRaManager.cpp
 * @brief Implementação de envio/recepção segura no enlace LoRa.
 */
#include "LoRaManager.h"
#include "Logger.h"
#include "../firmware/shared/radio_transport_v1_reason_codes.h"
#include <cstring>

namespace {
constexpr uint32_t kReplayPersistStride = 16;

static void bytesToHex(
    const uint8_t* data,
    size_t len,
    char* out,
    size_t outSize) {
  if (!out || outSize == 0) return;
  out[0] = '\0';
  if (!data || len == 0) return;
  const char* hex = "0123456789ABCDEF";
  size_t pos = 0;
  for (size_t i = 0; i < len && (pos + 2) < outSize; ++i) {
    out[pos++] = hex[(data[i] >> 4) & 0x0F];
    out[pos++] = hex[data[i] & 0x0F];
  }
  out[pos] = '\0';
}
}  // namespace

bool LoRaManager::persistReplayCheckpoint(uint32_t seq) {
  if (!replayPrefsReady_) return false;
  if (seq == 0 || seq <= persistedSeqSeen_) return true;
  const bool shouldPersist =
      persistedSeqSeen_ == 0 ||
      seq - persistedSeqSeen_ >= kReplayPersistStride;
  if (!shouldPersist) return true;
  if (replayPrefs_.putULong("last_seq", seq) != sizeof(uint32_t)) {
    LOGW("Falha ao persistir anti-replay da coleira seq=%lu", seq);
    return false;
  }
  persistedSeqSeen_ = seq;
  return true;
}

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
  persistedSeqSeen_ = lastSeqSeen_;
  LOGI("Anti-replay downlink restaurado last_seq=%lu", lastSeqSeen_);
  return true;
}

void LoRaManager::prepareForDeepSleep() {
  LOGI("LoRa prepare_for_sleep begin");

  const int16_t finishState = radio_.finishTransmit();
  if (finishState == RADIOLIB_ERR_NONE) {
    LOGI("LoRa prepare_for_sleep finish_transmit ok");
  }

  int16_t state = radio_.sleep();
  if (state == RADIOLIB_ERR_NONE) {
    LOGI("LoRa prepare_for_sleep radio_sleep ok");
  } else {
    LOGW("LoRa prepare_for_sleep radio_sleep err=%d", state);
    state = radio_.standby();
    if (state == RADIOLIB_ERR_NONE) {
      LOGI("LoRa prepare_for_sleep fallback_standby ok");
    } else {
      LOGW("LoRa prepare_for_sleep fallback_standby err=%d", state);
    }
  }

  pinMode(cfg::PIN_LORA_CS, OUTPUT);
  digitalWrite(cfg::PIN_LORA_CS, HIGH);
  delay(cfg::DEEP_SLEEP_PREPARE_DELAY_MS);
  LOGI("LoRa prepare_for_sleep done");
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
  char nonceHex[25] = {};
  char tagHex[17] = {};
  char headHex[17] = {};
  bytesToHex(frame.nonce, sizeof(frame.nonce), nonceHex, sizeof(nonceHex));
  bytesToHex(out + 12, cipherLen < 8 ? cipherLen : 8, headHex, sizeof(headHex));
  bytesToHex(frame.tag, 8, tagHex, sizeof(tagHex));
  LOGI(
      "LoRa TX detail type=%u seq=%lu payload=%u packed=%u cipher=%u nonce=%s tag=%s head=%s",
      (unsigned)frame.msgType,
      (unsigned long)frame.seq,
      (unsigned)frame.payloadLen,
      (unsigned)packedLen,
      (unsigned)cipherLen,
      nonceHex,
      tagHex,
      headHex);
  const int txState = radio_.transmit(out, 12 + cipherLen + 16);
  if (txState == RADIOLIB_ERR_NONE) {
    txCount_++;
    LOGI(
        "LoRa TX ok type=%u seq=%lu target=%lu scope=%016llX bytes=%u",
        (unsigned)frame.msgType,
        (unsigned long)frame.seq,
        (unsigned long)frame.deviceId,
        (unsigned long long)frame.scopeId,
        (unsigned)(12 + cipherLen + 16));
      return true;
  }
  txFailCount_++;
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
        decryptFailCount_++;
        char nonceHex[25] = {};
        char tagHex[17] = {};
        char headHex[17] = {};
        bytesToHex(nonce, 12, nonceHex, sizeof(nonceHex));
        bytesToHex(cipher, cipherLen < 8 ? cipherLen : 8, headHex, sizeof(headHex));
        bytesToHex(tag, 8, tagHex, sizeof(tagHex));
        LOGW(
            "LoRa RX decrypt_failed len=%u cipher_len=%u rssi=%d snr=%.1f nonce=%s tag=%s head=%s fail_count=%lu",
            (unsigned)len,
            (unsigned)cipherLen,
            (int)lastRssi_,
            lastSnr_,
            nonceHex,
            tagHex,
            headHex,
            (unsigned long)decryptFailCount_);
        LOGW(
            "RTR_RAW_DOWNLINK_DROP rawLen=%u msgType=0 rssi=%d snr=%.1f targetDeviceId=0 scopeId=0 reason=%s",
            (unsigned)len,
            (int)lastRssi_,
            lastSnr_,
            rtrv1::rawDropReasonLabel(rtrv1::RawDropReason::DECRYPT_FAILED));
        LOGW("LoRa RX descartado: decrypt_or_hmac_failed len=%u", (unsigned)len);
        continue;
      }
      memcpy(plain + cipherLen, tag, 16);
      if (!LoRaProtocol::decodePlain(plain, cipherLen + 16, frame)) {
        LOGW(
            "RTR_RAW_DOWNLINK_DROP rawLen=%u msgType=0 rssi=%d snr=%.1f targetDeviceId=0 scopeId=0 reason=%s",
            (unsigned)len,
            (int)lastRssi_,
            lastSnr_,
            rtrv1::rawDropReasonLabel(rtrv1::RawDropReason::INVALID_HEADER));
        LOGW("LoRa RX descartado: invalid_plain_frame len=%u", (unsigned)len);
        continue;
      }
      if (memcmp(frame.nonce, nonce, sizeof(frame.nonce)) != 0) {
        nonceMismatchCount_++;
        char externalHex[25] = {};
        char internalHex[25] = {};
        bytesToHex(nonce, sizeof(frame.nonce), externalHex, sizeof(externalHex));
        bytesToHex(frame.nonce, sizeof(frame.nonce), internalHex, sizeof(internalHex));
        LOGW(
            "nonce_mismatch external=%s internal=%s count=%lu",
            externalHex,
            internalHex,
            (unsigned long)nonceMismatchCount_);
        continue;
      }

      // A coleira só deve consumir comandos destinados a ela (ou broadcast).
      const bool targetMatch = frame.deviceId == cfg::DEVICE_ID || frame.deviceId == 0;
      LOGI(
          "RTR_RAW_DOWNLINK_RX rawLen=%u msgType=%u rssi=%d snr=%.1f targetDeviceId=%lu scopeId=%016llX",
          (unsigned)len,
          (unsigned)frame.msgType,
          (int)lastRssi_,
          lastSnr_,
          (unsigned long)frame.deviceId,
          (unsigned long long)frame.scopeId);
      if (!targetMatch) {
        LOGW(
            "RTR_RAW_DOWNLINK_DROP rawLen=%u msgType=%u rssi=%d snr=%.1f targetDeviceId=%lu scopeId=%016llX reason=%s",
            (unsigned)len,
            (unsigned)frame.msgType,
            (int)lastRssi_,
            lastSnr_,
            (unsigned long)frame.deviceId,
            (unsigned long long)frame.scopeId,
            rtrv1::rawDropReasonLabel(rtrv1::RawDropReason::TARGET_MISMATCH));
        LOGI(
            "LoRa RX ignorado: target=%lu self=%lu",
            (unsigned long)frame.deviceId,
            (unsigned long)cfg::DEVICE_ID);
        continue;
      }

      const bool downlinkCommand =
          frame.msgType == MsgType::RTR_CONTROL ||
          frame.msgType == MsgType::SET_FENCE ||
          frame.msgType == MsgType::SET_HERDING_PLAN ||
          frame.msgType == MsgType::SET_PARAMS ||
          frame.msgType == MsgType::PING ||
          frame.msgType == MsgType::RTR_CONTROL;
      if (!downlinkCommand) {
        LOGW(
            "RTR_RAW_DOWNLINK_DROP rawLen=%u msgType=%u rssi=%d snr=%.1f targetDeviceId=%lu scopeId=%016llX reason=%s",
            (unsigned)len,
            (unsigned)frame.msgType,
            (int)lastRssi_,
            lastSnr_,
            (unsigned long)frame.deviceId,
            (unsigned long long)frame.scopeId,
            rtrv1::rawDropReasonLabel(rtrv1::RawDropReason::UNKNOWN_TYPE));
        LOGI("LoRa RX ignorado: unsupported_type=%u", (unsigned)frame.msgType);
        continue;
      }

      if (frame.seq <= lastSeqSeen_) {
        replayRejectCount_++;
        LOGW(
            "RTR_RAW_DOWNLINK_DROP rawLen=%u msgType=%u rssi=%d snr=%.1f targetDeviceId=%lu scopeId=%016llX reason=%s",
            (unsigned)len,
            (unsigned)frame.msgType,
            (int)lastRssi_,
            lastSnr_,
            (unsigned long)frame.deviceId,
            (unsigned long long)frame.scopeId,
            rtrv1::rawDropReasonLabel(rtrv1::RawDropReason::REPLAY_BLOCKED));
        LOGW("Replay detectado seq=%lu", frame.seq);
        continue;
      }
      LOGI(
          "RTR_RAW_DOWNLINK_ACCEPT rawLen=%u msgType=%u rssi=%d snr=%.1f targetDeviceId=%lu scopeId=%016llX reason=accepted",
          (unsigned)len,
          (unsigned)frame.msgType,
          (int)lastRssi_,
          lastSnr_,
          (unsigned long)frame.deviceId,
          (unsigned long long)frame.scopeId);
      LOGI(
          "LoRa RX aceito type=%u seq=%lu scope=%016llX",
          (unsigned)frame.msgType,
          (unsigned long)frame.seq,
          (unsigned long long)frame.scopeId);
      lastSeqSeen_ = frame.seq;
      lastAcceptedSeq_ = frame.seq;
      persistReplayCheckpoint(lastSeqSeen_);
      return true;
    }
    delay(5);
  }
  return false;
}
