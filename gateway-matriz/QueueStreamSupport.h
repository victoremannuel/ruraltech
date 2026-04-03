#pragma once

#include <stddef.h>
#include <stdint.h>

namespace rtmatrix {

enum class QueueStreamDataPresence : uint8_t {
  kUnknown = 0,
  kNull = 1,
  kNonNull = 2,
};

struct QueueStreamNotification {
  bool completed = false;
  bool queueChanged = false;
  bool dataNonNull = false;
  char eventType[16]{};
  QueueStreamDataPresence dataPresence = QueueStreamDataPresence::kUnknown;
};

class QueueStreamParser {
 public:
  QueueStreamParser();

  void reset();
  QueueStreamNotification push(char ch);

 private:
  static bool isWhitespace(char ch);
  static void trimInPlace(char* text);
  static bool startsWith(const char* text, const char* prefix);
  static QueueStreamDataPresence mergePresence(
      QueueStreamDataPresence current,
      QueueStreamDataPresence next);

  void processLine(QueueStreamNotification& out);
  void finishEvent(QueueStreamNotification& out);
  QueueStreamDataPresence detectDataPresence(const char* text) const;

  char line_[256]{};
  size_t lineLen_ = 0;
  char pendingEvent_[16]{};
  QueueStreamDataPresence pendingPresence_ = QueueStreamDataPresence::kUnknown;
};

struct QueueStreamRuntimeState {
  bool connected = false;
  bool dispatchRequested = false;
  uint32_t lastEventAtMs = 0;
  uint32_t reconnectAtMs = 0;
  char lastError[64]{};

  void reset();
  void markConnected();
  void markEvent(uint32_t nowMs);
  void markDisconnect(uint32_t nowMs, uint32_t retryMs, const char* reason);
  bool fallbackPollingActive() const;
};

}  // namespace rtmatrix
