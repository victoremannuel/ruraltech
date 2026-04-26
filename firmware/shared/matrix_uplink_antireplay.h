#pragma once

#include <stddef.h>
#include <stdint.h>

namespace rtmatrix {
namespace antireplay {

constexpr size_t kScopeHexSize = 17;

struct ReplayEntry {
  uint32_t deviceId = 0;
  uint64_t scopeId = 0;
  uint16_t keyId = 0;
  uint32_t lastSeq = 0;
};

int findEntry(
    const ReplayEntry* entries,
    size_t count,
    uint32_t deviceId,
    uint64_t scopeId,
    uint16_t keyId);

int findEntrySlot(
    ReplayEntry* entries,
    size_t count,
    uint32_t deviceId,
    uint64_t scopeId,
    uint16_t keyId);

bool resetEntry(
    ReplayEntry* entries,
    size_t count,
    uint32_t deviceId,
    uint64_t scopeId,
    uint16_t keyId,
    uint32_t* lastSeqBefore,
    uint32_t* lastSeqAfter);

int32_t signedSeqDelta(uint32_t rxSeq, uint32_t lastAcceptedSeq);
void scopeIdToHex(uint64_t scopeId, char* out, size_t outSize);

}  // namespace antireplay
}  // namespace rtmatrix
