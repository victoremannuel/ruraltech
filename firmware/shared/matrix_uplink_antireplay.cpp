#include "matrix_uplink_antireplay.h"

#include <stdio.h>

namespace rtmatrix {
namespace antireplay {

namespace {
bool isEmptyEntry(const ReplayEntry& entry) {
  return entry.deviceId == 0 && entry.scopeId == 0 && entry.keyId == 0 &&
         entry.lastSeq == 0;
}
}  // namespace

int findEntry(
    const ReplayEntry* entries,
    size_t count,
    uint32_t deviceId,
    uint64_t scopeId,
    uint16_t keyId) {
  if (!entries || count == 0 || deviceId == 0 || scopeId == 0 || keyId == 0) {
    return -1;
  }
  for (size_t i = 0; i < count; ++i) {
    const ReplayEntry& entry = entries[i];
    if (entry.deviceId == deviceId && entry.scopeId == scopeId &&
        entry.keyId == keyId) {
      return static_cast<int>(i);
    }
  }
  return -1;
}

int findEntrySlot(
    ReplayEntry* entries,
    size_t count,
    uint32_t deviceId,
    uint64_t scopeId,
    uint16_t keyId) {
  const int existing = findEntry(entries, count, deviceId, scopeId, keyId);
  if (existing >= 0) return existing;
  if (!entries || count == 0 || deviceId == 0 || scopeId == 0 || keyId == 0) {
    return -1;
  }
  for (size_t i = 0; i < count; ++i) {
    if (isEmptyEntry(entries[i])) {
      return static_cast<int>(i);
    }
  }
  return 0;
}

bool resetEntry(
    ReplayEntry* entries,
    size_t count,
    uint32_t deviceId,
    uint64_t scopeId,
    uint16_t keyId,
    uint32_t* lastSeqBefore,
    uint32_t* lastSeqAfter) {
  if (lastSeqBefore) *lastSeqBefore = 0;
  if (lastSeqAfter) *lastSeqAfter = 0;
  if (!entries || count == 0 || deviceId == 0 || scopeId == 0 || keyId == 0) {
    return false;
  }
  const int idx = findEntry(entries, count, deviceId, scopeId, keyId);
  if (idx < 0) return true;
  if (lastSeqBefore) *lastSeqBefore = entries[idx].lastSeq;
  entries[idx] = ReplayEntry{};
  return true;
}

int32_t signedSeqDelta(uint32_t rxSeq, uint32_t lastAcceptedSeq) {
  return static_cast<int32_t>(
      static_cast<int64_t>(rxSeq) - static_cast<int64_t>(lastAcceptedSeq));
}

void scopeIdToHex(uint64_t scopeId, char* out, size_t outSize) {
  if (!out || outSize == 0) return;
  snprintf(out, outSize, "%016llX", (unsigned long long)scopeId);
}

}  // namespace antireplay
}  // namespace rtmatrix
