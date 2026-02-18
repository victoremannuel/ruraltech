/**
 * @file StorageQueue.cpp
 * @brief Persistência mínima para sobrevivência offline.
 */
#include "StorageQueue.h"
#include "config.h"

bool StorageQueue::begin() {
  if (!EEPROM.begin(cfg::EEPROM_SIZE)) return false;
  if (EEPROM.readUShort(headAddr_) >= cfg::EEPROM_EVENT_SLOTS) EEPROM.writeUShort(headAddr_, 0);
  if (EEPROM.readUShort(tailAddr_) >= cfg::EEPROM_EVENT_SLOTS) EEPROM.writeUShort(tailAddr_, 0);
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
