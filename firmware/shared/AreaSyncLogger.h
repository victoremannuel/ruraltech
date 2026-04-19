/**
 * @file AreaSyncLogger.h
 * @brief Macros de log estruturado [AREA_SYNC] para auditoria ponta a ponta
 *        de atualização de área/cerca via fluxo Supabase → matriz → coleira.
 *
 * Formato: [AREA_SYNC][<ROLE>][<LEVEL>][<EVENT>] key1=val1 key2=val2 ...
 * Roles: MATRIX | COMMON_GATEWAY | COLLAR
 * Níveis: INFO | WARN | ERROR
 */
#pragma once
#include <Arduino.h>

// ---------------------------------------------------------------------------
// Macros base
// ---------------------------------------------------------------------------
#define _AS_LOG(role, level, event, fmt, ...) \
  Serial.printf("[AREA_SYNC][" role "][" level "][" event "] " fmt "\n", ##__VA_ARGS__)

// ---------------------------------------------------------------------------
// MATRIX
// ---------------------------------------------------------------------------
#define AS_MATRIX_INFO(event, fmt, ...) _AS_LOG("MATRIX", "INFO",  event, fmt, ##__VA_ARGS__)
#define AS_MATRIX_WARN(event, fmt, ...) _AS_LOG("MATRIX", "WARN",  event, fmt, ##__VA_ARGS__)
#define AS_MATRIX_ERR(event,  fmt, ...) _AS_LOG("MATRIX", "ERROR", event, fmt, ##__VA_ARGS__)

// Eventos — matriz carregando comando da fila
#define AS_MATRIX_QUEUE_LOADED(cmdId, areaId, propId, scopeId, targetCount, pointCount) \
  AS_MATRIX_INFO("QUEUE_COMMAND_LOADED", \
    "commandId=%s areaId=%s propertyId=%s scopeId=%s targetCount=%d pointCount=%d", \
    cmdId, areaId, propId, scopeId, (int)(targetCount), (int)(pointCount))

#define AS_MATRIX_QUEUE_ACCEPTED(cmdId, areaId, propId, scopeId) \
  AS_MATRIX_INFO("QUEUE_COMMAND_ACCEPTED", \
    "commandId=%s areaId=%s propertyId=%s scopeId=%s", \
    cmdId, areaId, propId, scopeId)

#define AS_MATRIX_QUEUE_REJECTED(cmdId, reason) \
  AS_MATRIX_WARN("QUEUE_COMMAND_REJECTED", \
    "commandId=%s reason=%s", cmdId, reason)

#define AS_MATRIX_QUEUE_POLL_SKIPPED(reason, runtimeId, bindingReady, backhaulOpen, herdActive, simpleActive) \
  AS_MATRIX_WARN("QUEUE_POLL_SKIPPED", \
    "reason=%s runtimeId=%s bindingReady=%d backhaulOpen=%d herdActive=%d simpleActive=%d", \
    reason, runtimeId, (int)(bindingReady), (int)(backhaulOpen), (int)(herdActive), (int)(simpleActive))

#define AS_MATRIX_QUEUE_EMPTY(runtimeId, queueKeyLen) \
  AS_MATRIX_INFO("QUEUE_EMPTY", \
    "runtimeId=%s queueKeyLen=%d", runtimeId, (int)(queueKeyLen))

// Despacho LoRa
#define AS_MATRIX_DISPATCH_BEGIN(cmdId, areaId, propId, targetCount) \
  AS_MATRIX_INFO("DISPATCH_BEGIN", \
    "commandId=%s areaId=%s propertyId=%s targetCount=%d", \
    cmdId, areaId, propId, (int)(targetCount))

#define AS_MATRIX_DISPATCH_TARGET(cmdId, deviceId, part, total) \
  AS_MATRIX_INFO("DISPATCH_TARGET", \
    "commandId=%s deviceId=%lu part=%d total=%d", \
    cmdId, (unsigned long)(deviceId), (int)(part), (int)(total))

#define AS_MATRIX_LORA_TX_ATTEMPT(cmdId, deviceId, part, total) \
  AS_MATRIX_INFO("LORA_TX_ATTEMPT", \
    "commandId=%s deviceId=%lu part=%d total=%d", \
    cmdId, (unsigned long)(deviceId), (int)(part), (int)(total))

#define AS_MATRIX_LORA_TX_OK(cmdId, deviceId, part, total, areaId, pointCount) \
  AS_MATRIX_INFO("LORA_TX_OK", \
    "commandId=%s deviceId=%lu part=%d total=%d areaId=%s pointCount=%d", \
    cmdId, (unsigned long)(deviceId), (int)(part), (int)(total), areaId, (int)(pointCount))

#define AS_MATRIX_LORA_TX_FAIL(cmdId, deviceId, reason) \
  AS_MATRIX_ERR("LORA_TX_FAIL", \
    "commandId=%s deviceId=%lu reason=%s", \
    cmdId, (unsigned long)(deviceId), reason)

// ACK/NACK
#define AS_MATRIX_ACK_WAIT_OPEN(cmdId, deviceId) \
  AS_MATRIX_INFO("ACK_WAIT_OPEN", \
    "commandId=%s deviceId=%lu", cmdId, (unsigned long)(deviceId))

#define AS_MATRIX_ACK_MATCH(cmdId, deviceId, status, reason) \
  AS_MATRIX_INFO("ACK_MATCH", \
    "commandId=%s deviceId=%lu status=%s reason=%s", \
    cmdId, (unsigned long)(deviceId), status, reason)

#define AS_MATRIX_NACK_MATCH(cmdId, deviceId, status, reason) \
  AS_MATRIX_WARN("NACK_MATCH", \
    "commandId=%s deviceId=%lu status=%s reason=%s", \
    cmdId, (unsigned long)(deviceId), status, reason)

#define AS_MATRIX_ACK_TIMEOUT(cmdId, deviceId) \
  AS_MATRIX_WARN("ACK_TIMEOUT", \
    "commandId=%s deviceId=%lu", cmdId, (unsigned long)(deviceId))

// Evento polygon_apply_result da coleira
#define AS_MATRIX_COLLAR_APPLY_SUCCESS(cmdId, deviceId, areaId, originDocType, originDocId, pointCount) \
  AS_MATRIX_INFO("COLLAR_EVENT_POLYGON_APPLY_SUCCESS", \
    "commandId=%s deviceId=%lu areaId=%s originDocType=%s originDocId=%s pointCount=%d", \
    cmdId, (unsigned long)(deviceId), areaId, originDocType, originDocId, (int)(pointCount))

#define AS_MATRIX_COLLAR_APPLY_FAILURE(cmdId, deviceId, errorCode, errorStage) \
  AS_MATRIX_ERR("COLLAR_EVENT_POLYGON_APPLY_FAILURE", \
    "commandId=%s deviceId=%lu errorCode=%s errorStage=%s", \
    cmdId, (unsigned long)(deviceId), errorCode, errorStage)

// Publicação resultado no backend
#define AS_MATRIX_RESULT_PUBLISHED(cmdId, status) \
  AS_MATRIX_INFO("COMMAND_RESULT_PUBLISHED", \
    "commandId=%s status=%s", cmdId, status)

#define AS_MATRIX_RESULT_PUBLISH_FAIL(cmdId, reason) \
  AS_MATRIX_ERR("COMMAND_RESULT_PUBLISH_FAIL", \
    "commandId=%s reason=%s", cmdId, reason)

// ---------------------------------------------------------------------------
// COLLAR
// ---------------------------------------------------------------------------
#define AS_COLLAR_INFO(event, fmt, ...) _AS_LOG("COLLAR", "INFO",  event, fmt, ##__VA_ARGS__)
#define AS_COLLAR_WARN(event, fmt, ...) _AS_LOG("COLLAR", "WARN",  event, fmt, ##__VA_ARGS__)
#define AS_COLLAR_ERR(event,  fmt, ...) _AS_LOG("COLLAR", "ERROR", event, fmt, ##__VA_ARGS__)

// Recepção
#define AS_COLLAR_RX_FENCE_COMMAND(cmdId, areaId, originDocType, originDocId, scopeId, deviceId) \
  AS_COLLAR_INFO("RX_FENCE_COMMAND", \
    "commandId=%s areaId=%s originDocType=%s originDocId=%s scopeId=%s deviceId=%lu", \
    cmdId, areaId, originDocType, originDocId, scopeId, (unsigned long)(deviceId))

#define AS_COLLAR_RX_CHUNK_BEGIN(cmdId, total) \
  AS_COLLAR_INFO("RX_FENCE_CHUNK_BEGIN", \
    "commandId=%s total=%d", cmdId, (int)(total))

#define AS_COLLAR_RX_CHUNK_APPEND(cmdId, part, total, accum) \
  AS_COLLAR_INFO("RX_FENCE_CHUNK_APPEND", \
    "commandId=%s part=%d total=%d accumulatedPoints=%d", \
    cmdId, (int)(part), (int)(total), (int)(accum))

#define AS_COLLAR_RX_CHUNK_FINAL(cmdId, pointCount) \
  AS_COLLAR_INFO("RX_FENCE_CHUNK_FINAL", \
    "commandId=%s pointCount=%d", cmdId, (int)(pointCount))

// Erros de validação
#define AS_COLLAR_BINDING_MISSING(cmdId) \
  AS_COLLAR_WARN("BINDING_MISSING", "commandId=%s", cmdId)

#define AS_COLLAR_SCOPE_MISMATCH(cmdId, expected, got) \
  AS_COLLAR_WARN("SCOPE_MISMATCH", \
    "commandId=%s expectedScope=%s gotScope=%llu", \
    cmdId, expected, (unsigned long long)(got))

#define AS_COLLAR_PARSE_FAIL(cmdId, reason) \
  AS_COLLAR_ERR("PARSE_FAIL", \
    "commandId=%s reason=%s errorStage=parse", cmdId, reason)

#define AS_COLLAR_ASSEMBLE_FAIL(cmdId, reason) \
  AS_COLLAR_ERR("ASSEMBLE_FAIL", \
    "commandId=%s reason=%s errorStage=assemble", cmdId, reason)

#define AS_COLLAR_PERSIST_FAIL(cmdId, reason) \
  AS_COLLAR_ERR("PERSIST_FAIL", \
    "commandId=%s reason=%s errorStage=persist", cmdId, reason)

#define AS_COLLAR_ACTIVATE_FAIL(cmdId, reason) \
  AS_COLLAR_ERR("ACTIVATE_FAIL", \
    "commandId=%s reason=%s errorStage=activate", cmdId, reason)

// Sucesso
#define AS_COLLAR_FENCE_APPLY_OK(cmdId, areaId, pointCount) \
  AS_COLLAR_INFO("FENCE_APPLY_OK", \
    "commandId=%s areaId=%s pointCount=%d persisted=1 activated=1", \
    cmdId, areaId, (int)(pointCount))

#define AS_COLLAR_AUDIT_EVENT_QUEUED(cmdId) \
  AS_COLLAR_INFO("POLYGON_AUDIT_EVENT_QUEUED", \
    "commandId=%s", cmdId)

// ACK/NACK enviados
#define AS_COLLAR_ACK_SENT(cmdId, status) \
  AS_COLLAR_INFO("ACK_SENT", \
    "commandId=%s status=%s", cmdId, status)

#define AS_COLLAR_NACK_SENT(cmdId, status, reason) \
  AS_COLLAR_WARN("NACK_SENT", \
    "commandId=%s status=%s reason=%s", cmdId, status, reason)

// ---------------------------------------------------------------------------
// COMMON_GATEWAY (N/A neste repositório — firmware gateway/ não participa
// do caminho SET_FENCE; logs reservados para uso futuro)
// ---------------------------------------------------------------------------
#define AS_GW_INFO(event, fmt, ...) _AS_LOG("COMMON_GATEWAY", "INFO",  event, fmt, ##__VA_ARGS__)
#define AS_GW_WARN(event, fmt, ...) _AS_LOG("COMMON_GATEWAY", "WARN",  event, fmt, ##__VA_ARGS__)
#define AS_GW_ERR(event,  fmt, ...) _AS_LOG("COMMON_GATEWAY", "ERROR", event, fmt, ##__VA_ARGS__)
