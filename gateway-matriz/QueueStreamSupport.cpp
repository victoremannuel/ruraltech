#include "QueueStreamSupport.h"

#include <string.h>

namespace rtmatrix {

QueueStreamParser::QueueStreamParser() {
  reset();
}

void QueueStreamParser::reset() {
  line_[0] = '\0';
  lineLen_ = 0;
  pendingEvent_[0] = '\0';
  pendingPresence_ = QueueStreamDataPresence::kUnknown;
}

QueueStreamNotification QueueStreamParser::push(char ch) {
  QueueStreamNotification out;
  if (ch == '\r') return out;
  if (ch != '\n') {
    if (lineLen_ + 1 < sizeof(line_)) {
      line_[lineLen_++] = ch;
      line_[lineLen_] = '\0';
    }
    return out;
  }

  processLine(out);
  line_[0] = '\0';
  lineLen_ = 0;
  return out;
}

bool QueueStreamParser::isWhitespace(char ch) {
  return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
}

void QueueStreamParser::trimInPlace(char* text) {
  if (text == nullptr || text[0] == '\0') return;
  size_t start = 0;
  while (text[start] != '\0' && isWhitespace(text[start])) {
    ++start;
  }
  size_t end = strlen(text);
  while (end > start && isWhitespace(text[end - 1])) {
    --end;
  }
  if (start > 0) {
    memmove(text, text + start, end - start);
  }
  text[end - start] = '\0';
}

bool QueueStreamParser::startsWith(const char* text, const char* prefix) {
  if (!text || !prefix) return false;
  return strncmp(text, prefix, strlen(prefix)) == 0;
}

QueueStreamDataPresence QueueStreamParser::mergePresence(
    QueueStreamDataPresence current,
    QueueStreamDataPresence next) {
  if (next == QueueStreamDataPresence::kUnknown) return current;
  if (next == QueueStreamDataPresence::kNonNull) return next;
  if (current == QueueStreamDataPresence::kNonNull) return current;
  return next;
}

void QueueStreamParser::processLine(QueueStreamNotification& out) {
  trimInPlace(line_);
  if (line_[0] == '\0') {
    finishEvent(out);
    return;
  }
  if (line_[0] == ':') return;

  if (startsWith(line_, "event:")) {
    char* text = line_ + strlen("event:");
    trimInPlace(text);
    strncpy(pendingEvent_, text, sizeof(pendingEvent_) - 1);
    pendingEvent_[sizeof(pendingEvent_) - 1] = '\0';
    return;
  }

  if (startsWith(line_, "data:")) {
    char* text = line_ + strlen("data:");
    trimInPlace(text);
    pendingPresence_ = mergePresence(pendingPresence_, detectDataPresence(text));
  }
}

void QueueStreamParser::finishEvent(QueueStreamNotification& out) {
  if (pendingEvent_[0] == '\0' &&
      pendingPresence_ == QueueStreamDataPresence::kUnknown) {
    return;
  }

  out.completed = true;
  strncpy(out.eventType, pendingEvent_, sizeof(out.eventType) - 1);
  out.eventType[sizeof(out.eventType) - 1] = '\0';
  out.dataPresence = pendingPresence_;
  out.dataNonNull = pendingPresence_ == QueueStreamDataPresence::kNonNull;
  out.queueChanged =
      (strcmp(out.eventType, "put") == 0 || strcmp(out.eventType, "patch") == 0) &&
      out.dataNonNull;

  pendingEvent_[0] = '\0';
  pendingPresence_ = QueueStreamDataPresence::kUnknown;
}

QueueStreamDataPresence QueueStreamParser::detectDataPresence(const char* text) const {
  if (!text) return QueueStreamDataPresence::kUnknown;
  char scratch[256];
  strncpy(scratch, text, sizeof(scratch) - 1);
  scratch[sizeof(scratch) - 1] = '\0';
  trimInPlace(scratch);
  if (scratch[0] == '\0') return QueueStreamDataPresence::kUnknown;
  if (strcmp(scratch, "null") == 0) return QueueStreamDataPresence::kNull;

  const char* marker = strstr(scratch, "\"data\"");
  if (marker) {
    marker = strchr(marker, ':');
    if (marker) {
      ++marker;
      while (*marker != '\0' && isWhitespace(*marker)) {
        ++marker;
      }
      if (strncmp(marker, "null", 4) == 0) {
        return QueueStreamDataPresence::kNull;
      }
      if (*marker != '\0') {
        return QueueStreamDataPresence::kNonNull;
      }
    }
  }

  const char first = scratch[0];
  if (first == '{' || first == '[' || first == '"' ||
      (first >= '0' && first <= '9') || first == '-' ||
      first == 't' || first == 'f') {
    return QueueStreamDataPresence::kNonNull;
  }
  return QueueStreamDataPresence::kUnknown;
}

void QueueStreamRuntimeState::reset() {
  connected = false;
  dispatchRequested = false;
  lastEventAtMs = 0;
  reconnectAtMs = 0;
  lastError[0] = '\0';
}

void QueueStreamRuntimeState::markConnected() {
  connected = true;
  reconnectAtMs = 0;
  lastError[0] = '\0';
}

void QueueStreamRuntimeState::markEvent(uint32_t nowMs) {
  dispatchRequested = true;
  lastEventAtMs = nowMs;
}

void QueueStreamRuntimeState::markDisconnect(
    uint32_t nowMs,
    uint32_t retryMs,
    const char* reason) {
  connected = false;
  reconnectAtMs = nowMs + retryMs;
  dispatchRequested = false;
  if (reason && reason[0] != '\0') {
    strncpy(lastError, reason, sizeof(lastError) - 1);
    lastError[sizeof(lastError) - 1] = '\0';
  } else {
    lastError[0] = '\0';
  }
}

bool QueueStreamRuntimeState::fallbackPollingActive() const {
  return !connected;
}

}  // namespace rtmatrix
