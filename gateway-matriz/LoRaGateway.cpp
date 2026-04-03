/** @file LoRaGateway.cpp */
#include "LoRaGateway.h"
#include "Logger.h"
#include "config.h"
#include <cstring>
#include <SPI.h>

namespace {
constexpr uint32_t kReplayStateVersion = 1;

struct ReplayStateBlob {
  uint32_t version = 0;
  uint32_t deviceIds[cfg::LORA_REPLAY_TRACKED_DEVICES]{};
  uint32_t lastSeq[cfg::LORA_REPLAY_TRACKED_DEVICES]{};
};

inline void prepareSpiBusForLoRa() {
  pinMode(cfg::PIN_SD_CS, OUTPUT);
  digitalWrite(cfg::PIN_SD_CS, HIGH);
  pinMode(cfg::PIN_LORA_CS, OUTPUT);
  digitalWrite(cfg::PIN_LORA_CS, HIGH);
}
}  // namespace

void LoRaGateway::loadReplayState() {
  if (!replayPrefsReady_) return;
  if (replayPrefs_.getBytesLength("state") != sizeof(ReplayStateBlob)) {
    LOGI("Anti-replay sem estado salvo; iniciando tabela vazia.");
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

  memcpy(deviceIds_, blob.deviceIds, sizeof(deviceIds_));
  memcpy(lastSeqPerDevice_, blob.lastSeq, sizeof(lastSeqPerDevice_));
}

void LoRaGateway::persistReplayState() {
  if (!replayPrefsReady_) return;

  ReplayStateBlob blob;
  blob.version = kReplayStateVersion;
  memcpy(blob.deviceIds, deviceIds_, sizeof(deviceIds_));
  memcpy(blob.lastSeq, lastSeqPerDevice_, sizeof(lastSeqPerDevice_));

  const size_t saved = replayPrefs_.putBytes("state", &blob, sizeof(blob));
  if (saved != sizeof(blob)) {
    LOGW("Falha ao persistir estado anti-replay (%u bytes).",
         (unsigned)saved);
  }
}

uint8_t LoRaGateway::idxForDevice(uint32_t id) {
  for (uint8_t i = 0; i < cfg::LORA_REPLAY_TRACKED_DEVICES; ++i) {
    if (deviceIds_[i] == id || deviceIds_[i] == 0) {
      deviceIds_[i] = id;
      return i;
    }
  }
  return 0;
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
    LOGW("LoRa RX curto len=%u", (unsigned)packetLen);
    return false;
  }
  LOGI(
      "LoRa RX raw len=%u rssi=%d snr=%.1f",
      (unsigned)packetLen,
      lastRssi_,
      lastSnr_);

  const uint8_t* nonce = buf;
  const size_t cipherLen = len - 28;
  const uint8_t* cipher = buf + 12;
  const uint8_t* tag = buf + 12 + cipherLen;
  uint8_t plain[256];
  if (!crypto_.verifyAndDecrypt(cipher, cipherLen, tag, plain, nonce)) {
    setRadioState("rx_decrypt_failed");
    LOGW("LoRa RX descartado: decrypt_or_hmac_failed len=%u", (unsigned)len);
    return false;
  }
  memcpy(plain + cipherLen, tag, 16);
  if (!LoRaProtocol::decodePlain(plain, cipherLen + 16, frame)) {
    setRadioState("rx_decode_failed");
    LOGW("LoRa RX descartado: invalid_plain_frame len=%u", (unsigned)len);
    return false;
  }

  const uint8_t idx = idxForDevice(frame.deviceId);
  if (frame.seq <= lastSeqPerDevice_[idx]) {
    setRadioState("rx_replay");
    LOGW("Replay bloqueado device=%lu seq=%lu", frame.deviceId, frame.seq);
    return false;
  }
  setRadioState("rx_ok");
  LOGI(
      "LoRa RX aceito device=%lu type=%u seq=%lu scope=%016llX",
      (unsigned long)frame.deviceId,
      (unsigned)frame.msgType,
      (unsigned long)frame.seq,
      (unsigned long long)frame.scopeId);
  lastAcceptedRxAtMs_ = millis();
  lastSeqPerDevice_[idx] = frame.seq;
  persistReplayState();
  return true;
}

bool LoRaGateway::send(LoRaFrame& frame) {
  prepareSpiBusForLoRa();
  uint8_t plain[256];
  memset(frame.tag, 0, sizeof(frame.tag));
  const size_t packedLen = LoRaProtocol::encodePlain(frame, plain, sizeof(plain));
  if (!packedLen || packedLen < 16) return false;
  const size_t cipherLen = packedLen - 16;

  uint8_t out[300];
  memcpy(out, frame.nonce, 12);
  crypto_.encryptAndSign(plain, cipherLen, out + 12, frame.tag, frame.nonce);
  memcpy(out + 12 + cipherLen, frame.tag, 16);
  rxContinuousActive_ = false;
  setRadioState("tx_start");
  prepareSpiBusForLoRa();
  const int txState = radio_.transmit(out, 12 + cipherLen + 16);
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
        (unsigned)(12 + cipherLen + 16));
    return true;
  }
  setRadioState("tx_failed");
  LOGW(
      "LoRa TX falhou device=%lu type=%u seq=%lu err=%d",
      (unsigned long)frame.deviceId,
      (unsigned)frame.msgType,
      (unsigned long)frame.seq,
      txState);
  return false;
}
