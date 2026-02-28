#line 1 "/Users/victor/Downloads/code/ruraltech/gateway/Types.h"
/** @file Types.h */
#pragma once
#include <Arduino.h>

enum class MsgType : uint8_t {
  TELEMETRY = 1, EVENT = 2, HEARTBEAT = 3,
  SET_FENCE = 10, SET_HERDING_PLAN = 11, SET_PARAMS = 12,
  REQUEST_STATUS = 13, PING = 14, TIME_SYNC = 15, ACK = 16, NACK = 17
};
