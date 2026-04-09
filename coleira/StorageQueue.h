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
  bool popEvent(EventRecord& ev);

 private:
  void resetQueue();
  uint16_t headAddr_ = 6;
  uint16_t tailAddr_ = 8;
  uint16_t slotAddr(uint8_t idx) const;
};
