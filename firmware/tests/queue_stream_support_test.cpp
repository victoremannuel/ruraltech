#include <assert.h>
#include <string.h>

#include "../../gateway-matriz/QueueStreamSupport.h"

static rtmatrix::QueueStreamNotification feedText(
    rtmatrix::QueueStreamParser& parser,
    const char* text) {
  rtmatrix::QueueStreamNotification out;
  for (const char* cursor = text; *cursor != '\0'; ++cursor) {
    const rtmatrix::QueueStreamNotification notification = parser.push(*cursor);
    if (notification.completed) {
      out = notification;
    }
  }
  return out;
}

int main() {
  {
    rtmatrix::QueueStreamParser parser;
    const rtmatrix::QueueStreamNotification notification = feedText(
        parser,
        "event: put\n"
        "data: {\"path\":\"/\",\"data\":{\"cmd-1\":{\"command\":\"PING\"}}}\n\n");
    assert(notification.completed);
    assert(notification.queueChanged);
    assert(notification.dataNonNull);
    assert(strcmp(notification.eventType, "put") == 0);
  }

  {
    rtmatrix::QueueStreamParser parser;
    const rtmatrix::QueueStreamNotification notification = feedText(
        parser,
        "event: patch\n"
        "data: {\"path\":\"/cmd-1\",\"data\":{\"status\":\"queued\"}}\n\n");
    assert(notification.completed);
    assert(notification.queueChanged);
    assert(notification.dataPresence == rtmatrix::QueueStreamDataPresence::kNonNull);
  }

  {
    rtmatrix::QueueStreamParser parser;
    const rtmatrix::QueueStreamNotification notification = feedText(
        parser,
        ": keep-alive\n"
        "event: put\n"
        "data: {\"path\":\"/cmd-1\",\"data\":null}\n\n");
    assert(notification.completed);
    assert(!notification.queueChanged);
    assert(notification.dataPresence == rtmatrix::QueueStreamDataPresence::kNull);
  }

  {
    rtmatrix::QueueStreamRuntimeState state;
    state.markConnected();
    assert(state.connected);
    state.markEvent(1234U);
    assert(state.dispatchRequested);
    assert(state.lastEventAtMs == 1234U);
    state.markDisconnect(2000U, 5000U, "closed");
    assert(!state.connected);
    assert(state.reconnectAtMs == 7000U);
    assert(state.fallbackPollingActive());
    assert(strcmp(state.lastError, "closed") == 0);
  }

  return 0;
}
