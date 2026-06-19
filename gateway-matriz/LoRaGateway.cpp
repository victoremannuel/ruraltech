/** @file LoRaGateway.cpp */
#include "LoRaGateway.h"
#include "Logger.h"
#include "config.h"
#include <cstring>
#include <SPI.h>

namespace {
constexpr uint32_t kReplayStateVersion = 2;

struct ReplayStateBlobV1 {
  uint32_t version = 0;
  uint32_t deviceIds[cfg::LORA_REPLAY_TRACKED_DEVICES]{};
  uint32_t lastSeq[cfg::LORA_REPLAY_TRACKED_DEVICES]{};
};

struct ReplayStateBlob {
  uint32_t version = 0;
  rtmatrix::antireplay::ReplayEntry entries[cfg::LORA_REPLAY_TRACKED_DEVICES]{};
};

inline void prepareSpiBusForLoRa() {
  pinMode(cfg::PIN_SD_CS, OUTPUT);
  digitalWrite(cfg::PIN_SD_CS, HIGH);
  pinMode(cfg::PIN_LORA_CS, OUTPUT);
  digitalWrite(cfg::PIN_LORA_CS, HIGH);
}

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

bool LoRaGateway::shouldEmitThrottledLog(
    uint32_t nowMs,
    uint32_t* windowStartedAtMs,
    uint16_t* windowCount) {
  if (!windowStartedAtMs || !windowCount) return true;
  constexpr uint32_t kLogWindowMs = 2000;
  constexpr uint16_t kVerboseBurst = 3;
  if (*windowStartedAtMs == 0 || (uint32_t)(nowMs - *windowStartedAtMs) >= kLogWindowMs) {
    *windowStartedAtMs = nowMs;
    *windowCount = 0;
  }
  (*windowCount)++;
  return *windowCount <= kVerboseBurst;
}

void LoRaGateway::loadReplayState() {
  if (cfg::DISABLE_LORA_REPLAY_FOR_TESTS) {
    memset(replayEntries_, 0, sizeof(replayEntries_));
    LOGW("ANTI_REPLAY_TEST_MODE=1; estado anti-replay ignorado na inicializacao");
    return;
  }
  if (!replayPrefsReady_) return;
  const size_t stateLen = replayPrefs_.getBytesLength("state");
  if (stateLen == 0) {
    LOGI("Anti-replay sem estado salvo; iniciando tabela vazia.");
    return;
  }
  if (stateLen == sizeof(ReplayStateBlobV1)) {
    ReplayStateBlobV1 legacyBlob;
    const size_t loaded =
        replayPrefs_.getBytes("state", &legacyBlob, sizeof(legacyBlob));
    if (loaded == sizeof(legacyBlob) && legacyBlob.version == 1) {
      LOGW(
          "ANTI_REPLAY_STATE_MIGRATION version=1 action=discard_legacy_device_only_state");
      replayPrefs_.remove("state");
      memset(replayEntries_, 0, sizeof(replayEntries_));
      return;
    }
  }
  if (stateLen != sizeof(ReplayStateBlob)) {
    LOGW("Tamanho anti-replay invalido: %u", (unsigned)stateLen);
    return;
  }

  ReplayStateBlob blob;
  const size_t loaded = replayPrefs_.getBytes("state", &blob, sizeof(blob));
  if (loaded != sizeof(blob)) {
    LOGW("Falha ao carregar estado anti-replay (%u bytes).",
         (unsigned)loaded);
    return;
  }
  if (blob.version != kReplayStateVersion) {
    LOGW("Versao anti-replay invalida: %lu", blob.version);
    return;
  }

  memcpy(replayEntries_, blob.entries, sizeof(replayEntries_));
}

void LoRaGateway::persistReplayState() {
  if (cfg::DISABLE_LORA_REPLAY_FOR_TESTS) return;
  if (!replayPrefsReady_) return;

  ReplayStateBlob blob;
  blob.version = kReplayStateVersion;
  memcpy(blob.entries, replayEntries_, sizeof(replayEntries_));

  const size_t saved = replayPrefs_.putBytes("state", &blob, sizeof(blob));
  if (saved != sizeof(blob)) {
    LOGW("Falha ao persistir estado anti-replay (%u bytes).",
         (unsigned)saved);
  }
}

int LoRaGateway::replayEntrySlot(
    uint32_t deviceId,
    uint64_t scopeId,
    uint16_t keyId) {
  return rtmatrix::antireplay::findEntrySlot(
      replayEntries_,
      cfg::LORA_REPLAY_TRACKED_DEVICES,
      deviceId,
      scopeId,
      keyId);
}

bool LoRaGateway::armContinuousReceive() {
  prepareSpiBusForLoRa();
  setRadioState("rx_arm");
  const int state = radio_.startReceive();
  lastReceiveCode_ = state;
  rxContinuousActive_ = (state == RADIOLIB_ERR_NONE);
  if (!rxContinuousActive_) {
    setRadioState("rx_arm_failed");
    LOGW("LoRa RX arm falhou=%d", state);
  } else {
    rxArmCount_++;
    setRadioState("rx_wait");
  }
  return rxContinuousActive_;
}

bool LoRaGateway::begin() {
  prepareSpiBusForLoRa();
  SPI.begin(cfg::PIN_SPI_SCK, cfg::PIN_SPI_MISO, cfg::PIN_SPI_MOSI, cfg::PIN_LORA_CS);
  setRadioState("begin");
  const int state = radio_.begin(cfg::LORA_FREQ_MHZ, 125, 9, 7, 0x12);
  if (state != RADIOLIB_ERR_NONE) {
    ready_ = false;
    setRadioState("begin_failed");
    LOGE("Falha LoRa begin=%d", state);
    return false;
  }
  ready_ = true;
  setRadioState("begin_ok");
  LOGI("LoRa begin ok freq=%.1f bw=125 sf=9 cr=7 sync=0x12", cfg::LORA_FREQ_MHZ);

  replayPrefsReady_ = replayPrefs_.begin("lora_rx", false);
  if (!replayPrefsReady_) {
    LOGW("NVS indisponivel para anti-replay do gateway (RAM only).");
    return armContinuousReceive();
  }
  loadReplayState();
  if (cfg::DISABLE_LORA_REPLAY_FOR_TESTS) {
    LOGW("ANTI_REPLAY_TEST_MODE=1 no gateway-matriz; replays serao aceitos temporariamente");
  }
  return armContinuousReceive();
}

bool LoRaGateway::receive(LoRaFrame& frame) {
  if (!ready_) return false;
  if (!rxContinuousActive_ && !armContinuousReceive()) return false;

  prepareSpiBusForLoRa();
  const uint16_t irqFlags = radio_.getIRQFlags();
  lastIrqFlags_ = irqFlags;
  if ((irqFlags & RADIOLIB_SX127X_CLEAR_IRQ_FLAG_RX_DONE) == 0) {
    if (irqFlags & RADIOLIB_SX127X_CLEAR_IRQ_FLAG_RX_TIMEOUT) {
      lastReceiveCode_ = RADIOLIB_ERR_RX_TIMEOUT;
      setRadioState("rx_timeout");
      armContinuousReceive();
    } else {
      lastReceiveCode_ = RADIOLIB_ERR_RX_TIMEOUT;
      setRadioState("rx_poll");
    }
    return false;
  }

  uint8_t buf[300];
  const size_t packetLen = radio_.getPacketLength();
  size_t len = packetLen;
  if (len > sizeof(buf)) {
    LOGW("LoRa RX maior que buffer len=%u", (unsigned)packetLen);
    len = sizeof(buf);
  }
  setRadioState("rx_read");
  prepareSpiBusForLoRa();
  int s = radio_.readData(buf, len);
  lastReceiveCode_ = s;
  lastReceiveLen_ = packetLen;
  lastRssi_ = (int)radio_.getRSSI();
  lastSnr_ = radio_.getSNR();
  lastRawRxAtMs_ = millis();
  armContinuousReceive();
  if (s != RADIOLIB_ERR_NONE) {
    if (s == RADIOLIB_ERR_CRC_MISMATCH) {
      setRadioState("rx_crc");
      LOGW("LoRa RX descartado: crc_mismatch len=%u", (unsigned)packetLen);
    } else {
      setRadioState("rx_read_failed");
      LOGW("LoRa RX falhou readData err=%d len=%u", s, (unsigned)packetLen);
    }
    return false;
  }
  if (len < 28) {
    setRadioState("rx_short");
    rtrdiag::noteRawRxSeen(
        &rawRxDiag_,
        static_cast<uint16_t>(packetLen),
        static_cast<int16_t>(lastRssi_),
        lastSnr_);
    rtrdiag::noteRawNoiseDrop(&rawRxDiag_, "frame_too_short", "");
    LOGW("LoRa RX curto len=%u", (unsigned)packetLen);
    return false;
  }
  rtrdiag::noteRawRxSeen(
      &rawRxDiag_,
      static_cast<uint16_t>(packetLen),
      static_cast<int16_t>(lastRssi_),
      lastSnr_);
  LOGI(
      "LoRa RX raw len=%u rssi=%d snr=%.1f",
      (unsigned)packetLen,
      lastRssi_,
      lastSnr_);

  const uint8_t* nonce = buf;
  const size_t cipherLen = len - 28;
  const uint8_t* cipher = buf + 12;
  const uint8_t* tag = buf + 12 + cipherLen;
  char noiseHeadHex[17] = {};
  bytesToHex(buf, len < 8 ? len : 8, noiseHeadHex, sizeof(noiseHeadHex));
  if (rtrdiag::looksLikeRawNoise(
          static_cast<uint16_t>(packetLen),
          static_cast<int16_t>(lastRssi_),
          lastSnr_,
          buf,
          len)) {
    setRadioState("rx_noise_drop");
    rtrdiag::noteRawNoiseDrop(&rawRxDiag_, "implausible_raw_signal", noiseHeadHex);
    if (shouldEmitThrottledLog(
            lastRawRxAtMs_,
            &rawNoiseLogWindowStartedAtMs_,
            &rawNoiseLogWindowCount_)) {
      LOGW(
          "LORA_RX_NOISE_DROP len=%u rssi=%d snr=%.1f reason=%s head=%s count=%lu",
          (unsigned)packetLen,
          lastRssi_,
          lastSnr_,
          rawRxDiag_.lastRawNoiseReason,
          rawRxDiag_.lastRawPatternHex,
          (unsigned long)rawRxDiag_.rawRxNoiseDropCount);
    } else if (rawNoiseLogWindowCount_ == 4) {
      LOGW(
          "LORA_RX_NOISE_DROP_SUMMARY windowMs=2000 noiseDrops=%u lastReason=%s head=%s",
          (unsigned)rawNoiseLogWindowCount_,
          rawRxDiag_.lastRawNoiseReason,
          rawRxDiag_.lastRawPatternHex);
    }
    return false;
  }
  if (rtrdiag::looksLikeInvalidRepeatedPattern(nonce, 12, cipher, cipherLen, tag, 8)) {
    setRadioState("rx_pattern_drop");
    rtrdiag::noteRawPatternDrop(&rawRxDiag_, "repeated_pattern", noiseHeadHex);
    if (shouldEmitThrottledLog(
            lastRawRxAtMs_,
            &rawPatternLogWindowStartedAtMs_,
            &rawPatternLogWindowCount_)) {
      LOGW(
          "LORA_RX_PATTERN_DROP len=%u rssi=%d snr=%.1f reason=%s head=%s count=%lu",
          (unsigned)packetLen,
          lastRssi_,
          lastSnr_,
          rawRxDiag_.lastRawNoiseReason,
          rawRxDiag_.lastRawPatternHex,
          (unsigned long)rawRxDiag_.rawRxInvalidPatternDropCount);
    } else if (rawPatternLogWindowCount_ == 4) {
      LOGW(
          "LORA_RX_PATTERN_DROP_SUMMARY windowMs=2000 patternDrops=%u lastReason=%s head=%s",
          (unsigned)rawPatternLogWindowCount_,
          rawRxDiag_.lastRawNoiseReason,
          rawRxDiag_.lastRawPatternHex);
    }
    return false;
  }
  rtrdiag::noteRawDecryptAttempt(&rawRxDiag_);
  LOGI(
      "LORA_RX_DECRYPT_ATTEMPT len=%u rssi=%d snr=%.1f attempts=%lu",
      (unsigned)packetLen,
      lastRssi_,
      lastSnr_,
      (unsigned long)rawRxDiag_.rawRxDecryptAttemptCount);
  uint8_t plain[256];
  if (!crypto_.verifyAndDecrypt(cipher, cipherLen, tag, plain, nonce)) {
    decryptFailCount_++;
    rtrdiag::noteRawDecryptFailed(&rawRxDiag_);
    setRadioState("rx_decrypt_failed");
    char nonceHex[25] = {};
    char tagHex[17] = {};
    char headHex[17] = {};
    bytesToHex(nonce, 12, nonceHex, sizeof(nonceHex));
    bytesToHex(cipher, cipherLen < 8 ? cipherLen : 8, headHex, sizeof(headHex));
    bytesToHex(tag, 8, tagHex, sizeof(tagHex));
    rtrdiag::noteDecryptFail(
        &lastDecryptFail_,
        lastRawRxAtMs_,
        decryptFailCount_,
        static_cast<uint16_t>(packetLen),
        static_cast<int16_t>(lastRssi_),
        lastSnr_,
        lastIrqFlags_,
        lastRadioState_,
        "decrypt_or_hmac_failed",
        headHex,
        nonceHex,
        tagHex);
    if (shouldEmitThrottledLog(
            lastRawRxAtMs_,
            &decryptFailLogWindowStartedAtMs_,
            &decryptFailLogWindowCount_)) {
      LOGW(
          "LoRa RX decrypt_failed len=%u cipher_len=%u irq=0x%04X state=%s rssi=%d snr=%.1f nonce=%s tag=%s head=%s fail_count=%lu",
          (unsigned)packetLen,
          (unsigned)cipherLen,
          (unsigned)lastIrqFlags_,
          lastRadioState_,
          lastRssi_,
          lastSnr_,
          nonceHex,
          tagHex,
          headHex,
          (unsigned long)decryptFailCount_);
      LOGW(
          "LORA_RX_DECRYPT_FAIL_CONTEXT millis=%lu len=%u rssi=%d snr=%.1f irq=0x%04X state=%s head=%s nonce=%s tag=%s reason=%s count=%lu",
          (unsigned long)lastDecryptFail_.atMs,
          (unsigned)lastDecryptFail_.len,
          (int)lastDecryptFail_.rssi,
          lastDecryptFail_.snr,
          (unsigned)lastDecryptFail_.irqFlags,
          lastDecryptFail_.radioState,
          lastDecryptFail_.headHex,
          lastDecryptFail_.nonceHex,
          lastDecryptFail_.tagHex,
          lastDecryptFail_.reason,
          (unsigned long)lastDecryptFail_.count);
    } else if (decryptFailLogWindowCount_ == 4) {
      LOGW(
          "LORA_RX_DECRYPT_FAIL_SUMMARY windowMs=2000 decryptFails=%u lastReason=%s head=%s",
          (unsigned)decryptFailLogWindowCount_,
          lastDecryptFail_.reason,
          lastDecryptFail_.headHex);
    }
    LOGW("LoRa RX descartado: decrypt_or_hmac_failed len=%u", (unsigned)len);
    return false;
  }
  memcpy(plain + cipherLen, tag, 16);
  if (!LoRaProtocol::decodePlain(plain, cipherLen + 16, frame)) {
    setRadioState("rx_decode_failed");
    LOGW("LoRa RX descartado: invalid_plain_frame len=%u", (unsigned)len);
    return false;
  }
  if (memcmp(frame.nonce, nonce, sizeof(frame.nonce)) != 0) {
    nonceMismatchCount_++;
    setRadioState("rx_nonce_mismatch");
    char externalHex[25] = {};
    char internalHex[25] = {};
    bytesToHex(nonce, sizeof(frame.nonce), externalHex, sizeof(externalHex));
    bytesToHex(frame.nonce, sizeof(frame.nonce), internalHex, sizeof(internalHex));
    LOGW(
        "nonce_mismatch external=%s internal=%s count=%lu",
        externalHex,
        internalHex,
        (unsigned long)nonceMismatchCount_);
    return false;
  }

  const uint16_t keyId = cfg::LORA_KEY_ID;
  const int idx = replayEntrySlot(frame.deviceId, frame.scopeId, keyId);
  if (!cfg::DISABLE_LORA_REPLAY_FOR_TESTS &&
      idx >= 0 &&
      frame.seq <= replayEntries_[idx].lastSeq) {
    replayRejectCount_++;
    setRadioState("rx_replay");
    lastBlockedUplink_.valid = true;
    lastBlockedUplink_.deviceId = frame.deviceId;
    lastBlockedUplink_.scopeId = frame.scopeId;
    lastBlockedUplink_.keyId = keyId;
    lastBlockedUplink_.rxSeq = frame.seq;
    lastBlockedUplink_.lastAcceptedSeq = replayEntries_[idx].lastSeq;
    lastBlockedUplink_.delta = rtmatrix::antireplay::signedSeqDelta(
        frame.seq, replayEntries_[idx].lastSeq);
    lastBlockedUplink_.frameType = static_cast<uint8_t>(frame.msgType);
    lastBlockedUplink_.protoVersion = cfg::LORA_PROTO_VERSION;
    lastBlockedUplink_.radioProfile = cfg::LORA_RADIO_PROFILE_ID;
    lastBlockedUplink_.atMs = millis();
    lastBlockedUplink_.reason = "replay_or_old_seq";
    char scopeHex[rtmatrix::antireplay::kScopeHexSize]{};
    rtmatrix::antireplay::scopeIdToHex(
        frame.scopeId, scopeHex, sizeof(scopeHex));
    LOGW(
        "ANTI_REPLAY_BLOCKED direction=uplink deviceId=%lu scopeId=%s keyId=%u rxSeq=%lu lastAcceptedSeq=%lu delta=%ld frameType=%u protoVersion=%u radioProfile=%u reason=replay_or_old_seq",
        (unsigned long)frame.deviceId,
        scopeHex,
        (unsigned)keyId,
        (unsigned long)frame.seq,
        (unsigned long)replayEntries_[idx].lastSeq,
        (long)lastBlockedUplink_.delta,
        (unsigned)frame.msgType,
        (unsigned)cfg::LORA_PROTO_VERSION,
        (unsigned)cfg::LORA_RADIO_PROFILE_ID);
    return false;
  }
  if (cfg::DISABLE_LORA_REPLAY_FOR_TESTS &&
      idx >= 0 &&
      frame.seq <= replayEntries_[idx].lastSeq) {
    LOGW(
        "ANTI_REPLAY_TEST_MODE=1 aceitando frame repetido device=%lu seq=%lu last_seq=%lu",
        (unsigned long)frame.deviceId,
        (unsigned long)frame.seq,
        (unsigned long)replayEntries_[idx].lastSeq);
  }
  setRadioState("rx_ok");
  rtrdiag::noteRawAccepted(&rawRxDiag_);
  LOGI(
      "LORA_RX_ACCEPT_CONTEXT device=%lu type=%u seq=%lu scope=%016llX accepted=%lu",
      (unsigned long)frame.deviceId,
      (unsigned)frame.msgType,
      (unsigned long)frame.seq,
      (unsigned long long)frame.scopeId,
      (unsigned long)rawRxDiag_.rawRxAcceptedCount);
  lastAcceptedRxAtMs_ = millis();
  lastAcceptedSeq_ = frame.seq;
  if (!cfg::DISABLE_LORA_REPLAY_FOR_TESTS && idx >= 0) {
    replayEntries_[idx].deviceId = frame.deviceId;
    replayEntries_[idx].scopeId = frame.scopeId;
    replayEntries_[idx].keyId = keyId;
    replayEntries_[idx].lastSeq = frame.seq;
    persistReplayState();
  }
  return true;
}

bool LoRaGateway::resetUplinkAntiReplayForDevice(
    uint32_t deviceId,
    uint64_t scopeId,
    uint16_t keyId,
    const char* source,
    AntiReplayResetResult* out) {
  AntiReplayResetResult local;
  local.deviceId = deviceId;
  local.scopeId = scopeId;
  local.keyId = keyId;
  local.reason = "unknown";
  char scopeHex[rtmatrix::antireplay::kScopeHexSize]{};
  rtmatrix::antireplay::scopeIdToHex(scopeId, scopeHex, sizeof(scopeHex));

  if (!cfg::DIAG_ANTI_REPLAY_RESET_ENABLED) {
    local.reason = "diag_mode_required";
    LOGW(
        "ANTI_REPLAY_RESET_DENIED direction=uplink deviceId=%lu scopeId=%s keyId=%u source=%s reason=diag_mode_required",
        (unsigned long)deviceId,
        scopeHex,
        (unsigned)keyId,
        source ? source : "unknown");
    if (out) *out = local;
    return false;
  }
  if (deviceId == 0 || scopeId == 0 || keyId == 0) {
    local.reason = "invalid_target";
    LOGW(
        "ANTI_REPLAY_RESET_DENIED direction=uplink deviceId=%lu scopeId=%s keyId=%u source=%s reason=invalid_target",
        (unsigned long)deviceId,
        scopeHex,
        (unsigned)keyId,
        source ? source : "unknown");
    if (out) *out = local;
    return false;
  }

  LOGI(
      "ANTI_REPLAY_RESET_BEGIN direction=uplink deviceId=%lu scopeId=%s keyId=%u source=%s",
      (unsigned long)deviceId,
      scopeHex,
      (unsigned)keyId,
      source ? source : "unknown");
  uint32_t lastBefore = 0;
  uint32_t lastAfter = 0;
  if (!rtmatrix::antireplay::resetEntry(
          replayEntries_,
          cfg::LORA_REPLAY_TRACKED_DEVICES,
          deviceId,
          scopeId,
          keyId,
          &lastBefore,
          &lastAfter)) {
    local.reason = "reset_failed";
    if (out) *out = local;
    return false;
  }
  persistReplayState();
  local.ok = true;
  local.lastSeqBefore = lastBefore;
  local.lastSeqAfter = lastAfter;
  local.reason = "ok";
  LOGI(
      "ANTI_REPLAY_RESET_DONE direction=uplink deviceId=%lu scopeId=%s keyId=%u lastSeqBefore=%lu lastSeqAfter=%lu source=%s",
      (unsigned long)deviceId,
      scopeHex,
      (unsigned)keyId,
      (unsigned long)lastBefore,
      (unsigned long)lastAfter,
      source ? source : "unknown");
  if (out) *out = local;
  return true;
}

bool LoRaGateway::send(LoRaFrame& frame) {
  prepareSpiBusForLoRa();
  uint8_t out[300];
  SecureWireMetrics metrics;
  if (!buildSecureWireMetrics(frame, &metrics, out, sizeof(out))) {
    setRadioState("tx_build_failed");
    LOGW(
        "LoRa TX build falhou device=%lu type=%u seq=%lu reason=%s payload=%u",
        (unsigned long)frame.deviceId,
        (unsigned)frame.msgType,
        (unsigned long)frame.seq,
        metrics.reason ? metrics.reason : "unknown",
        (unsigned)frame.payloadLen);
    return false;
  }
  char nonceHex[25] = {};
  char tagHex[17] = {};
  char headHex[17] = {};
  bytesToHex(frame.nonce, sizeof(frame.nonce), nonceHex, sizeof(nonceHex));
  bytesToHex(out + 12, metrics.cipherPayloadLen < 8 ? metrics.cipherPayloadLen : 8, headHex, sizeof(headHex));
  bytesToHex(out + 12 + metrics.cipherPayloadLen, 8, tagHex, sizeof(tagHex));
  LOGI(
      "LoRa TX detail device=%lu type=%u seq=%lu payload=%u packed=%u cipher=%u nonce=%s tag=%s head=%s",
      (unsigned long)frame.deviceId,
      (unsigned)frame.msgType,
      (unsigned long)frame.seq,
      (unsigned)metrics.plainPayloadLen,
      (unsigned)metrics.packedLen,
      (unsigned)metrics.cipherPayloadLen,
      nonceHex,
      tagHex,
      headHex);
  rxContinuousActive_ = false;
  setRadioState("tx_start");
  prepareSpiBusForLoRa();
  const int txState = radio_.transmit(out, metrics.wireLenFinal);
  armContinuousReceive();
  if (txState == RADIOLIB_ERR_NONE) {
    txCount_++;
    setRadioState("tx_ok");
    LOGI(
        "LoRa TX ok device=%lu type=%u seq=%lu scope=%016llX bytes=%u",
        (unsigned long)frame.deviceId,
        (unsigned)frame.msgType,
        (unsigned long)frame.seq,
        (unsigned long long)frame.scopeId,
        (unsigned)metrics.wireLenFinal);
    return true;
  }
  txFailCount_++;
  setRadioState("tx_failed");
  LOGW(
      "LoRa TX falhou device=%lu type=%u seq=%lu err=%d",
      (unsigned long)frame.deviceId,
      (unsigned)frame.msgType,
      (unsigned long)frame.seq,
      txState);
  return false;
}

bool LoRaGateway::buildSecureWireMetrics(
    const LoRaFrame& frame,
    SecureWireMetrics* metrics,
    uint8_t* outWireBuffer,
    size_t outWireBufferCap) {
  if (!metrics) return false;
  *metrics = SecureWireMetrics{};

  if (frame.payloadLen == 0) {
    metrics->reason = "empty_payload";
    return false;
  }

  uint8_t plain[256];
  LoRaFrame working = frame;
  memset(working.tag, 0, sizeof(working.tag));
  const size_t packedLen = LoRaProtocol::encodePlain(working, plain, sizeof(plain));
  if (!packedLen || packedLen < 16) {
    metrics->reason = "plain_encode_failed";
    return false;
  }

  const size_t cipherLen = packedLen - 16;
  const size_t wireLen = 12 + cipherLen + 16;
  if (wireLen > 0xFFFF) {
    metrics->reason = "wire_len_overflow";
    return false;
  }
  if (outWireBuffer && outWireBufferCap < wireLen) {
    metrics->reason = "wire_buffer_too_small";
    return false;
  }

  metrics->plainPayloadLen = working.payloadLen;
  metrics->packedLen = static_cast<uint16_t>(packedLen);
  metrics->cipherPayloadLen = static_cast<uint16_t>(cipherLen);
  metrics->wireLenFinal = static_cast<uint16_t>(wireLen);

  if (!outWireBuffer) {
    metrics->ok = true;
    return true;
  }

  memcpy(outWireBuffer, working.nonce, 12);
  crypto_.encryptAndSign(plain, cipherLen, outWireBuffer + 12, working.tag, working.nonce);
  memcpy(outWireBuffer + 12 + cipherLen, working.tag, 16);
  metrics->ok = true;
  return true;
}
