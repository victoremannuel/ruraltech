/**
 * @file StorageQueue.cpp
 * @brief Persistência mínima para sobrevivência offline.
 */
#include "StorageQueue.h"
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

void StorageQueue::resetQueue() {
  EEPROM.writeULong(kMagicAddr, kQueueMagic);
  EEPROM.writeUShort(kVersionAddr, kQueueVersion);
  EEPROM.writeUShort(headAddr_, 0);
  EEPROM.writeUShort(tailAddr_, 0);
}

bool StorageQueue::begin() {
  if (!EEPROM.begin(cfg::EEPROM_SIZE)) return false;

  const bool versionMismatch =
      EEPROM.readULong(kMagicAddr) != kQueueMagic ||
      EEPROM.readUShort(kVersionAddr) != kQueueVersion;
  if (versionMismatch) {
    resetQueue();
    EEPROM.commit();
    return true;
  }

  if (EEPROM.readUShort(headAddr_) >= cfg::EEPROM_EVENT_SLOTS ||
      EEPROM.readUShort(tailAddr_) >= cfg::EEPROM_EVENT_SLOTS) {
    resetQueue();
  }
  EEPROM.commit();
  return true;
}

uint16_t StorageQueue::slotAddr(uint8_t idx) const {
  return cfg::EEPROM_EVENT_START + idx * sizeof(EventRecord);
}

void StorageQueue::pushEvent(const EventRecord& ev) {
  uint16_t head = EEPROM.readUShort(headAddr_);
  EEPROM.put(slotAddr(head), ev);
  head = (head + 1) % cfg::EEPROM_EVENT_SLOTS;
  EEPROM.writeUShort(headAddr_, head);
  if (head == EEPROM.readUShort(tailAddr_)) {
    EEPROM.writeUShort(tailAddr_, (head + 1) % cfg::EEPROM_EVENT_SLOTS);
  }
  EEPROM.commit();
}

bool StorageQueue::popEvent(EventRecord& ev) {
  uint16_t head = EEPROM.readUShort(headAddr_);
  uint16_t tail = EEPROM.readUShort(tailAddr_);
  if (head == tail) return false;
  EEPROM.get(slotAddr(tail), ev);
  tail = (tail + 1) % cfg::EEPROM_EVENT_SLOTS;
  EEPROM.writeUShort(tailAddr_, tail);
  EEPROM.commit();
  return true;
}
