/**
 * @file StorageQueue.cpp
 * @brief Persistência mínima para sobrevivência offline.
 */
#include "StorageQueue.h"
#include "Logger.h"
#include "config.h"

namespace {
constexpr uint32_t kQueueMagic = 0x52544532UL;
constexpr uint16_t kQueueVersion = 2;
constexpr uint16_t kMagicAddr = 0;
constexpr uint16_t kVersionAddr = 4;
}

static_assert(
    cfg::EEPROM_EVENT_START + cfg::EEPROM_EVENT_SLOTS * sizeof(EventRecord) <=
        cfg::EEPROM_LAST_GOOD_FIX_ADDR,
    "Event queue overlaps SmartGps persistence range");

void StorageQueue::resetPersistentQueue() {
  EEPROM.writeULong(kMagicAddr, kQueueMagic);
  EEPROM.writeUShort(kVersionAddr, kQueueVersion);
  EEPROM.writeUShort(headAddr_, 0);
  EEPROM.writeUShort(tailAddr_, 0);
}

void StorageQueue::resetRamQueue() {
  ramHead_ = 0;
  ramTail_ = 0;
  memset(ramQueue_, 0, sizeof(ramQueue_));
}

bool StorageQueue::begin() {
  initialized_ = true;
  resetRamQueue();

  if (!persistenceEnabled_) {
    LOGW("StorageQueue: persistencia EEPROM desabilitada; usando fila em RAM");
    return true;
  }

  if (!EEPROM.begin(cfg::EEPROM_SIZE)) {
    persistenceEnabled_ = false;
    LOGW("StorageQueue: EEPROM indisponivel; usando fila em RAM");
    return true;
  }

  const bool versionMismatch =
      EEPROM.readULong(kMagicAddr) != kQueueMagic ||
      EEPROM.readUShort(kVersionAddr) != kQueueVersion;
  if (versionMismatch) {
    resetPersistentQueue();
    if (!EEPROM.commit()) {
      persistenceEnabled_ = false;
      LOGW("StorageQueue: falha commit ao inicializar EEPROM; usando fila em RAM");
    }
    return true;
  }

  if (EEPROM.readUShort(headAddr_) >= cfg::EEPROM_EVENT_SLOTS ||
      EEPROM.readUShort(tailAddr_) >= cfg::EEPROM_EVENT_SLOTS) {
    resetPersistentQueue();
  }
  if (!EEPROM.commit()) {
    persistenceEnabled_ = false;
    LOGW("StorageQueue: falha commit ao validar EEPROM; usando fila em RAM");
  }
  return true;
}

uint16_t StorageQueue::slotAddr(uint8_t idx) const {
  return cfg::EEPROM_EVENT_START + idx * sizeof(EventRecord);
}

void StorageQueue::pushEvent(const EventRecord& ev) {
  if (!initialized_) return;
  if (!persistenceEnabled_) {
    ramQueue_[ramHead_] = ev;
    ramHead_ = (uint8_t)((ramHead_ + 1U) % cfg::EEPROM_EVENT_SLOTS);
    if (ramHead_ == ramTail_) {
      ramTail_ = (uint8_t)((ramTail_ + 1U) % cfg::EEPROM_EVENT_SLOTS);
    }
    return;
  }

  uint16_t head = EEPROM.readUShort(headAddr_);
  EEPROM.put(slotAddr(head), ev);
  head = (head + 1) % cfg::EEPROM_EVENT_SLOTS;
  EEPROM.writeUShort(headAddr_, head);
  if (head == EEPROM.readUShort(tailAddr_)) {
    EEPROM.writeUShort(tailAddr_, (head + 1) % cfg::EEPROM_EVENT_SLOTS);
  }
  if (!EEPROM.commit()) {
    LOGW("StorageQueue: falha commit ao gravar evento");
  }
}

bool StorageQueue::popEvent(EventRecord& ev) {
  if (!initialized_) return false;
  if (!persistenceEnabled_) {
    if (ramHead_ == ramTail_) return false;
    ev = ramQueue_[ramTail_];
    ramTail_ = (uint8_t)((ramTail_ + 1U) % cfg::EEPROM_EVENT_SLOTS);
    return true;
  }

  uint16_t head = EEPROM.readUShort(headAddr_);
  uint16_t tail = EEPROM.readUShort(tailAddr_);
  if (head == tail) return false;
  EEPROM.get(slotAddr(tail), ev);
  tail = (tail + 1) % cfg::EEPROM_EVENT_SLOTS;
  EEPROM.writeUShort(tailAddr_, tail);
  if (!EEPROM.commit()) {
    LOGW("StorageQueue: falha commit ao consumir evento");
  }
  return true;
}
