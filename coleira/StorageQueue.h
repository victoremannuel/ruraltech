/**
 * @file StorageQueue.h
 * @brief Ring buffer em EEPROM para eventos críticos offline.
 */
#pragma once
#include <EEPROM.h>
#include "Types.h"

class StorageQueue {
 public:
  bool begin();
  void pushEvent(const EventRecord& ev);
  bool peekEvent(EventRecord& ev);
  bool ackEvent();
  bool popEvent(EventRecord& ev);
  uint8_t count() const;
  bool persistenceEnabled() const { return persistenceEnabled_; }

 private:
  void resetPersistentQueue();
  void resetRamQueue();
  uint16_t headAddr_ = 6;
  uint16_t tailAddr_ = 8;
  uint16_t slotAddr(uint8_t idx) const;
  bool persistenceEnabled_ = cfg::STORAGE_QUEUE_PERSISTENCE_ENABLED;
  bool initialized_ = false;
  EventRecord ramQueue_[cfg::EEPROM_EVENT_SLOTS]{};
  uint8_t ramHead_ = 0;
  uint8_t ramTail_ = 0;
};
