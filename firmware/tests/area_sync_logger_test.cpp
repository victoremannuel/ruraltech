#include <cassert>
#include <cstdarg>
#include <cstdio>
#include <cstring>

#include "arduino_compat/Arduino.h"

struct TestSerial {
  char output[512]{};

  int printf(const char* format, ...) {
    va_list args;
    va_start(args, format);
    const int written = std::vsnprintf(output, sizeof(output), format, args);
    va_end(args);
    return written;
  }
};

TestSerial Serial;

#include "../shared/AreaSyncLogger.h"

int main() {
  assert(std::strcmp(AS_SAFE_STR(nullptr), "") == 0);

  AS_COLLAR_RX_FENCE_COMMAND(
      nullptr, nullptr, nullptr, nullptr, nullptr, 3222380545UL);
  assert(std::strstr(Serial.output, "commandId= areaId=") != nullptr);
  assert(std::strstr(Serial.output, "originDocType= originDocId=") != nullptr);
  assert(std::strstr(Serial.output, "scopeId=") != nullptr);

  AS_COLLAR_NACK_SENT(nullptr, nullptr, nullptr);
  assert(std::strstr(Serial.output, "commandId= status= reason=") != nullptr);
  return 0;
}
