#line 1 "/Users/victor/Downloads/code/ruraltech/coleira/Types.h"
/**
 * @file Types.h
 * @brief Tipos compartilhados entre módulos da coleira.
 * @version 1.0.0
 * @date 2026-02-18
 */
#pragma once
#include <Arduino.h>
#include "config.h"

enum class CollarMode : uint8_t { NORMAL = 0, ALERTA = 1, CONDUCAO = 2 };
enum class EventType : uint8_t {
  APPROACH = 1,
  VIOLATION = 2,
  RETURNED = 3,
  PULSE_APPLIED = 4,
  GPS_FAIL = 5,
  NO_MOTION = 6,
  HERD_START = 7,
  HERD_PHASE_CHANGE = 8,
  HERD_DONE = 9
};
enum class MsgType : uint8_t {
  TELEMETRY = 1,
  EVENT = 2,
  HEARTBEAT = 3,
  SET_FENCE = 10,
  SET_HERDING_PLAN = 11,
  SET_PARAMS = 12,
  REQUEST_STATUS = 13,
  PING = 14,
  TIME_SYNC = 15,
  ACK = 16,
  NACK = 17
};

struct GpsData {
  bool valid = false;
  double lat = 0;
  double lon = 0;
  float speedKmph = 0;
  float hdop = 99.9f;
  uint8_t sats = 0;
  uint32_t gpsTime = 0;
};

struct Telemetry {
  GpsData gps;
  float temperatureC = 0;
  bool moving = false;
  int16_t rssi = -120;
  float snr = 0;
  uint32_t uptime = 0;
  CollarMode mode = CollarMode::NORMAL;
};

struct GeoPoint { double lat; double lon; };
struct Polygon {
  uint8_t count = 0;
  GeoPoint points[cfg::MAX_POLYGON_POINTS]{};
};

struct HerdingPlan {
  bool active = false;
  uint8_t phaseCount = 0;
  uint8_t currentPhase = 0;
  Polygon phases[cfg::MAX_HERD_PHASES]{};
};

struct EventRecord {
  uint32_t ts = 0;
  EventType type = EventType::GPS_FAIL;
  int32_t d1 = 0;
  int32_t d2 = 0;
};
