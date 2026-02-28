/** @file LoRaGateway.cpp */
#include "LoRaGateway.h"
#include "Logger.h"
#include <cstring>

namespace {
constexpr uint32_t kReplayStateVersion = 1;

struct ReplayStateBlob {
  uint32_t version = 0;
  uint32_t deviceIds[cfg::LORA_REPLAY_TRACKED_DEVICES]{};
  uint32_t lastSeq[cfg::LORA_REPLAY_TRACKED_DEVICES]{};
};
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

bool LoRaGateway::begin() {
  if (radio_.begin(cfg::LORA_FREQ_MHZ, 125, 9, 7, 0x12) != RADIOLIB_ERR_NONE) {
    return false;
  }

  replayPrefsReady_ = replayPrefs_.begin("lora_rx", false);
  if (!replayPrefsReady_) {
    LOGW("NVS indisponivel para anti-replay do gateway (RAM only).");
    return true;
  }
  loadReplayState();
  return true;
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
  persistReplayState();
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
