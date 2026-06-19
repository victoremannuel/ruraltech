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
  HERD_DONE = 9,
  GPS_INVALID_FIX = 10,
  GPS_OUTLIER = 11,
  GPS_LOCKED = 12,
  GPS_UNLOCKED = 13,
  POLYGON_APPLY_RESULT = 14
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
  NACK = 17,
  RTR_CONTROL = 18
};

enum class PolygonApplyStatus : uint8_t {
  NONE = 0,
  SUCCESS = 1,
  FAILURE = 2,
};

enum class PolygonKind : uint8_t {
  NONE = 0,
  PROPERTY = 1,
  AREA = 2,
  HERDING = 3,
};

enum class OriginDocType : uint8_t {
  NONE = 0,
  RURAL_PROPERTY = 1,
  AREA = 2,
  HERDING_OPERATION = 3,
};

enum class PolygonErrorStage : uint8_t {
  NONE = 0,
  PARSE = 1,
  ASSEMBLE = 2,
  PERSIST = 3,
  ACTIVATE = 4,
  SCOPE = 5,
  BINDING = 6,
};

struct GpsData {
  bool valid = false;
  double lat = 0;
  double lon = 0;
  float speedKmph = 0;
  float hdop = 99.9f;
  uint8_t sats = 0;
  uint32_t gpsTime = 0;
  uint16_t year = 0;
  uint8_t month = 0;
  uint8_t day = 0;
  bool filtered = false;
  bool locked = false;
  bool outlierDropped = false;
  uint32_t sampleMs = 0;
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
  char operationId[cfg::OPERATION_ID_MAX_LEN]{};
  Polygon phases[cfg::MAX_HERD_PHASES]{};
};

struct PolygonAuditPayload {
  char commandId[cfg::EVENT_COMMAND_ID_MAX_LEN]{};
  char originDocId[cfg::EVENT_ORIGIN_DOC_ID_MAX_LEN]{};
  char errorCode[cfg::EVENT_ERROR_CODE_MAX_LEN]{};
};

union EventPayloadData {
  char operationId[cfg::OPERATION_ID_MAX_LEN];
  PolygonAuditPayload audit;

  EventPayloadData() { memset(this, 0, sizeof(*this)); }
};

struct EventRecord {
  uint32_t ts = 0;
  int32_t d1 = 0;
  int32_t d2 = 0;
  uint64_t scopeId = 0;
  EventType type = EventType::GPS_FAIL;
  PolygonApplyStatus auditStatus = PolygonApplyStatus::NONE;
  PolygonKind polygonKind = PolygonKind::NONE;
  OriginDocType originDocType = OriginDocType::NONE;
  PolygonErrorStage errorStage = PolygonErrorStage::NONE;
  EventPayloadData payload{};
};
