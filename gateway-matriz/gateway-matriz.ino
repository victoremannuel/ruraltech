/**
 * @file gateway.ino
 * @brief Firmware gateway matriz RuralTech: LoRa seguro + REST/WS + SD log + OLED.
 * @version 1.0.0
 * @date 2026-02-21
 */
#if !defined(ARDUINO_PARTITION_min_spiffs)
#error "Selecione Partition Scheme: Minimal SPIFFS (1.9MB APP with OTA/128KB SPIFFS)."
#endif

#include <Arduino.h>
#include <ctype.h>
#include <cstring>
#include <math.h>
#include <WiFi.h>
#include <ArduinoOTA.h>
#include <WiFiClientSecure.h>
#include <Wire.h>
#include <SPI.h>
#include <ArduinoJson.h>
#include <esp_task_wdt.h>
#include <esp_system.h>
#include <esp_ota_ops.h>
#include <time.h>
#if __has_include(<esp_idf_version.h>)
#include <esp_idf_version.h>
#endif
#include "config.h"
#if RT_MATRIX_OLED_ENABLED
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#endif
#include <RTClib.h>
#include <Preferences.h>
#include "Logger.h"
#include "BlePresence.h"
#include "LoRaGateway.h"
#include "MatrixLoRaTxAudit.h"
#include "RtrWakeOrchestrator.h"
#include "FenceRpv2Planner.h"
#include "SdLogger.h"
#include "../firmware/shared/build_info.h"
#include "ApiServer.h"
#include "QueueStreamSupport.h"
#include "../firmware/shared/command_contract.h"
#include "../firmware/shared/AreaSyncLogger.h"
#include "../firmware/shared/radio_transport_v1_codec.h"
#include "../firmware/shared/radio_transport_v1_constants.h"
#include "../firmware/shared/radio_transport_v1_reason_codes.h"
#include "../firmware/shared/radio_transport_v1_session_id.h"
#include "../firmware/shared/rtr_diag_support.h"
#include "../firmware/shared/radio_proto_v2_codec.h"
#include "../firmware/shared/radio_proto_v2_crc.h"
#include "../firmware/shared/radio_proto_v2_id.h"
#include "../firmware/shared/radio_proto_v2_planner_support.h"
#include "../firmware/shared/radio_proto_v2_reason_codes.h"

LoRaGateway lora;
BlePresence blePresence;
SdLogger sdlog;
ApiServer api;
RTC_DS3231 rtc;
#if RT_MATRIX_OLED_ENABLED
Adafruit_SSD1306 display(128, 64, &Wire, -1);
#endif
uint32_t seqDown = 1;
Preferences seqPrefs;
Preferences bindingPrefs;
bool seqPrefsReady = false;
bool bindingPrefsReady = false;
bool wifiOtaEnabled = cfg::WIFI_OTA_DEFAULT_ENABLED;
bool watchdogTaskRegistered = false;
bool otaUploadInProgress = false;
bool wifiApRunning = false;
uint32_t wifiRecoveryAttemptAtMs = 0;
uint8_t wifiRecoveryAttemptCount = 0;
uint32_t cloudBackhaulAttemptAtMs = 0;
uint32_t cloudLastPublishAtMs = 0;
bool cloudBackhaulConnecting = false;
uint32_t cloudBackhaulConnectStartedAtMs = 0;
wifi_err_reason_t cloudBackhaulLastDisconnectReason = WIFI_REASON_UNSPECIFIED;
uint32_t cloudBackhaulLastDiagScanAtMs = 0;
uint32_t queuePollAtMs = 0;
uint64_t lastQueuePollAtUnixMs = 0;
bool queueStreamConnected = false;
uint64_t queueStreamLastEventAtUnixMs = 0;
uint64_t queueStreamReconnectAtUnixMs = 0;
char queueStreamLastError[96]{};
rtmatrix::QueueStreamParser queueStreamParser;
rtmatrix::QueueStreamRuntimeState queueStreamRuntime;
WiFiClientSecure queueStreamClient;
bool queueDispatchRequested = false;
uint32_t runtimeMirrorPublishAtMs = 0;
char bindingPropertyId[48]{};
char bindingPropertyScopeId[17]{};
char bindingMatrixGatewayId[32]{};
uint32_t bindingVersion = 0;
bool bindingReady = false;
bool supportsScopedLora = true;
char lastCloudWriteError[96]{};
constexpr uint8_t kAcceptedUplinkQueueSize = 8;
constexpr uint32_t kAcceptedUplinkQuietMs = 1500;
constexpr uint32_t kBackhaulStartupDelayMs = 8000;
constexpr uint32_t kBackhaulDiagHeartbeatWhileUnhealthyMs = 5000;
constexpr uint32_t kBackhaulDiagHeartbeatConnectedMs = 30000;

enum class BackhaulDiagState : uint8_t {
  kDisabled,
  kIdle,
  kConnecting,
  kAssociatedNoIp,
  kConnected,
  kNoSsid,
  kAuthFailed,
  kDhcpTimeout,
  kConnectionLost,
  kRetryWait,
  kUnknownFailure
};

struct BackhaulDiagSnapshot {
  BackhaulDiagState state = BackhaulDiagState::kIdle;
  uint32_t attemptCount = 0;
  uint32_t connectStartedAtMs = 0;
  uint32_t lastStateChangeAtMs = 0;
  uint32_t lastHeartbeatAtMs = 0;
  uint32_t lastSuccessAtMs = 0;
  uint32_t retryDelayMs = 0;
  wl_status_t wlStatus = WL_DISCONNECTED;
  wifi_err_reason_t lastDisconnectReason = WIFI_REASON_UNSPECIFIED;
  bool associated = false;
  bool targetVisible = false;
  int16_t targetRssi = 0;
  int32_t targetChannel = 0;
  wifi_auth_mode_t targetAuth = WIFI_AUTH_OPEN;
  char targetBssid[24]{};
  char ip[20]{};
  char gateway[20]{};
  char dns[20]{};
  char lastSummary[96]{};
};

BackhaulDiagSnapshot backhaulDiag;

struct AcceptedUplinkEntry {
  bool used = false;
  uint32_t enqueuedAtMs = 0;
  LoRaFrame frame{};
};

AcceptedUplinkEntry acceptedUplinkQueue[kAcceptedUplinkQueueSize]{};
uint8_t acceptedUplinkQueueHead = 0;
uint8_t acceptedUplinkQueueTail = 0;
uint8_t acceptedUplinkQueueCount = 0;
uint32_t acceptedUplinkLastEnqueueAtMs = 0;
uint32_t acceptedUplinkLastDrainAtMs = 0;
uint32_t acceptedUplinkDropCount = 0;
AcceptedUplinkEntry deferredUplinkQueue[kAcceptedUplinkQueueSize]{};
uint8_t deferredUplinkQueueHead = 0;
uint8_t deferredUplinkQueueTail = 0;
uint8_t deferredUplinkQueueCount = 0;
uint32_t deferredUplinkFlushAtMs = 0;
uint32_t lastSimpleCommandAckMatchedAtMs = 0;
char lastSimpleCommandFeedbackOutcome[24]{};
bool simpleAckWaitActive = false;
uint32_t simpleAckWaitDeviceId = 0;
uint32_t simpleAckWaitDeadlineAtMs = 0;
char simpleAckWaitCommandId[48]{};
uint32_t bootStartedAtMs = 0;

struct HerdPoint {
  double lat = 0.0;
  double lon = 0.0;
};

struct HerdingOperationDeviceState {
  uint32_t deviceId = 0;
  uint32_t lastDispatchAtMs = 0;
  uint32_t updatedAtMs = 0;
  uint32_t assembledAtSec = 0;
  uint32_t completedAtSec = 0;
  uint16_t retryCount = 0;
  uint8_t phaseIndex = 0;
  char lastReason[32]{};
  bool assembled = false;
  bool completed = false;
};

struct HerdingOperationState {
  bool active = false;
  bool finalized = false;
  uint32_t startedAtMs = 0;
  uint32_t updatedAtMs = 0;
  uint32_t lastStatusPublishAtMs = 0;
  uint32_t requestedAtSec = 0;
  uint32_t completedAtSec = 0;
  uint8_t pointCount = 0;
  uint8_t deviceCount = 0;
  uint64_t createdAtMs = 0;
  uint64_t expiresAtMs = 0;
  char operationId[48]{};
  char propertyId[48]{};
  char ownerUid[48]{};
  char requestedByUid[48]{};
  char requestedByRole[16]{};
  char matrixGatewayId[32]{};
  char propertyScopeId[17]{};
  char loraCommandId[48]{};
  char lastCommandStatus[20]{};
  char failureReason[48]{};
  HerdPoint targetPolygon[cfg::MAX_POLYGON_POINTS]{};
  HerdingOperationDeviceState devices[cfg::MAX_HERD_OPERATION_DEVICES]{};
} herdOp;

struct ActiveSimpleCommandTargetState {
  char targetId[32]{};
  bool terminal = false;
  bool ok = false;
  char status[20]{};
  char reason[48]{};
};

struct ActiveSimpleCommandState {
  bool active = false;
  bool targetedRetryPending = false;
  bool targetDeviceCommand = false;
  bool sawTargetUplinkSinceDispatch = false;
  bool awaitingFeedback = false;
  uint32_t dispatchAtMs = 0;
  uint32_t lastAttemptAtMs = 0;
  uint32_t targetedRetryAtMs = 0;
  uint32_t targetedRetryDeviceId = 0;
  uint32_t lastProgressAtMs = 0;
  uint32_t feedbackDeviceId = 0;
  uint32_t feedbackWindowOpenedAtMs = 0;
  uint32_t feedbackDeadlineAtMs = 0;
  uint32_t deferredUplinkCount = 0;
  uint64_t createdAtMs = 0;
  uint64_t expiresAtMs = 0;
  uint8_t targetCount = 0;
  uint16_t retryCount = 0;
  uint16_t lastReasonCode = rpv2::REASON_NONE;
  char commandId[48]{};
  char command[24]{};
  char transportState[32]{};
  char feedbackCommandId[48]{};
  char lastFeedbackOutcome[24]{};
  char propertyId[48]{};
  char propertyScopeId[17]{};
  char matrixGatewayId[32]{};
  char polygonKind[16]{};
  char originDocType[24]{};
  char originDocId[48]{};
  char requestedByUid[48]{};
  char requestedByRole[16]{};
  char payloadJson[4096]{};
  ActiveSimpleCommandTargetState targets[cfg::MAX_HERD_OPERATION_DEVICES]{};
} activeSimpleCommand;

struct Rpv2AwaitedResponse {
  bool received = false;
  bool ack = false;
  bool nack = false;
  bool applyStatus = false;
  uint16_t reasonCode = rpv2::REASON_NONE;
  uint16_t fragmentIndex = 0;
  uint16_t nextExpectedFragment = 0;
  uint16_t acceptedPoints = 0;
  uint32_t observedCrc32 = 0;
  uint16_t activePoints = 0;
};

struct PendingWakeSession {
  rtrwake::SessionCore core{};
  char commandId[48]{};
  uint64_t scopeId = 0;
  MsgType commandType = MsgType::SET_FENCE;
  uint64_t radioCommandId = 0;
  uint32_t sessionNonce = 0;
  uint16_t estimatedFragments = 0;
  uint16_t lastReasonCode = rtrv1::REASON_NONE;
  char lastReasonLabel[48]{};
  bool rpv2PlanReady = false;
  Rpv2FenceChunkPlan plan{};
};

constexpr uint8_t kMaxPendingWakeSessions = cfg::MAX_HERD_OPERATION_DEVICES;
constexpr uint8_t kMaxDevicePresenceEntries = cfg::MAX_HERD_OPERATION_DEVICES;
constexpr uint32_t kRecentWakeHintMs = 4000;
constexpr uint32_t kSetFenceLocalStallTimeoutMs = 30000UL;
constexpr uint32_t kPendingWakeWaitingUplinkTimeoutMs = 180000UL;
PendingWakeSession pendingWakeSessions[kMaxPendingWakeSessions]{};
rtrwake::Presence devicePresence[kMaxDevicePresenceEntries]{};
rtrdiag::PageSnapshot lastPageDiag{};
rtrdiag::WakeLoopSnapshot wakeLoopDiag{};

struct CloudPublishContext {
  uint32_t nowSec = 0;
  uint64_t nowMs = 0;
  String matrixId;
  String deviceId;
  String propertyId;
  String propertyScopeId;
};

struct CloudWriteTrace {
  bool ok = false;
  int httpStatus = 0;
  uint32_t elapsedMs = 0;
  char stage[24]{};
  char detail[96]{};
};

struct TelemetryPublishTrace {
  bool attempted = false;
  bool latestOk = false;
  bool historyOk = false;
  uint32_t totalElapsedMs = 0;
  CloudWriteTrace latest{};
  CloudWriteTrace history{};
};

struct FencePointsResolution;

static void setWatchdogEnabled(bool enabled);
static void feedWatchdogIfEnabled();
static void printBootChecklist(
    bool displayOk,
    bool wifiOk,
    bool bleInitOk,
    bool rtcOk,
    bool sdOk,
    bool loraOk,
    bool cloudConfigured,
    bool queueConfigured);
static void copyStringToBuffer(char* dst, size_t dstSize, const char* src);
static void loadBindingConfig();
static bool persistBindingConfig(
    const JsonVariantConst payload,
    const char** reason = nullptr);
static bool startHerdingOperation(const JsonVariantConst payload, const char** reason);
static void dispatchActiveHerdingOperation();
static void handleHerdingOperationFeedback(const LoRaFrame& rx);
static void handleHerdingOperationEvent(const LoRaFrame& rx);
static void handleSimpleCommandFeedback(const LoRaFrame& rx);
static bool sendLoRaJsonFrame(
    uint32_t deviceId,
    MsgType msgType,
    const JsonVariantConst payload,
    const char** reason = nullptr,
    MatrixLoRaTxReason txReason = MatrixLoRaTxReason::CommandDispatch,
    const char* callerTag = "sendLoRaJsonFrame",
    const LoRaFrame* sourceUplinkOrNull = nullptr,
    const char* commandId = nullptr);
static bool sendFenceCommandChunked(
    uint32_t deviceId,
    const JsonVariantConst payload,
    const char** reason = nullptr);
static void noteSetFenceCommandProgress(const char* stage);
static bool hasPendingWakeSessionForCommand(const char* commandId);
static void checkSetFencePlannerDispatchStall(uint32_t nowTick, uint64_t nowMs);
static bool resendActiveSimpleCommand(
    const LoRaFrame* triggerRx = nullptr,
    const char** reason = nullptr);
static bool isHealthDailyEvent(const LoRaFrame& rx);
static void scheduleActiveSimpleCommandRetryForRx(const LoRaFrame& rx);
static void processScheduledActiveSimpleCommandRetry();
static void processNextQueuedCommand();
static void publishHerdingOperationSnapshot(
    bool force = false,
    const char* statusOverride = nullptr);
static bool ensureCloudBackhaulConnected();
static bool publishMatrixRuntimeMirrors(bool force = false);
static void pollQueueCommandStream();
static bool enqueueAcceptedUplink(const LoRaFrame& frame);
static bool popAcceptedUplink(LoRaFrame& frame);
static bool enqueueDeferredUplink(const LoRaFrame& frame);
static bool popDeferredUplink(LoRaFrame& frame);
static void processAcceptedUplink(const LoRaFrame& rx);
static void processQueuedAcceptedUplinks();
static void flushDeferredAcceptedUplinksIfReady();
static void openActiveSimpleCommandFeedbackWindow(uint32_t deviceId);
static void closeActiveSimpleCommandFeedbackWindow(const char* outcome);
static bool isAwaitedSimpleCommandFeedback(const LoRaFrame& rx);
static void handleUplinkDuringAckWait(const LoRaFrame& rx);
static void pollActiveSimpleCommandFeedbackSlice();
static bool processPrioritySimpleCommandFeedbackWindow();
static int findActiveSimpleCommandTarget(const char* targetId);
static bool publishSimpleCommandResult(const char* status, const char* reason = nullptr);
static String payloadBytesToString(const uint8_t* data, size_t len);
static void fillCloudWriteTrace(
    CloudWriteTrace* trace,
    bool ok,
    int httpStatus,
    uint32_t elapsedMs,
    const char* stage,
    const char* detail);
static int parseHttpStatusCode(const String& statusLine);
static String summarizeHttpFailureDetail(
    const String& statusLine,
    const String& responseBody);
static void primeSpiChipSelectLines();
static bool backhaulWindowOpen();
static void requestImmediateQueueDispatch(const char* source);
static void closeQueueCommandStream(const char* reason);
static void drawStatus(const char* line1, const char* line2);
static bool splitFencePointArrayForPayload(
    const JsonVariantConst payload,
    const JsonArrayConst& points,
    uint8_t starts[cfg::MAX_POLYGON_POINTS],
    uint8_t ends[cfg::MAX_POLYGON_POINTS],
    uint8_t& chunkCount,
    const char** reason = nullptr);
static bool hasPendingWakeSessions();
static int findPendingWakeSessionByDeviceId(uint32_t deviceId);
static int findPendingWakeSessionByCommandId(const char* commandId);
static int findPendingWakeSessionByPageCorrelation(uint32_t deviceId, uint64_t sessionId, uint32_t messageId);
static PendingWakeSession* allocatePendingWakeSession();
static void clearPendingWakeSession(int idx, const char* reason);
static const char* pendingWakeStateLabel(rtrwake::State state);
static void transitionPendingWakeState(PendingWakeSession& session, rtrwake::State nextState, const char* reason);
static void setPendingWakeReason(PendingWakeSession& session, uint16_t reasonCode, const char* reasonLabel);
static void syncLastPageDiagFromSession(const PendingWakeSession& session);
static void noteWakeLoopStage(const char* stage, const PendingWakeSession& session);
static bool processPendingWakeSessionStep(uint8_t idx, PendingWakeSession& session, uint32_t nowMs);
static void updateDevicePresenceFromAcceptedUplink(const LoRaFrame& rx, uint32_t atMs);
static rtrwake::Presence* findDevicePresence(uint32_t deviceId);
static bool notePendingWakeHintFromUplink(const LoRaFrame& rx, uint32_t rxAcceptedAtMs);
static bool tryHandleWakePageImmediatelyAfterAcceptedUplink(
    const LoRaFrame& rx,
    uint32_t rxAcceptedAtMs);
static bool handlePendingWakePageAck(const LoRaFrame& rx);
static bool tryHandlePendingWakePageAckFastPath(const LoRaFrame& rx);
static bool trySendRtrPage(PendingWakeSession& session, const char** reason = nullptr);
static bool executeFenceCommandRpv2Plan(
    uint32_t deviceId,
    uint64_t scopeId,
    uint64_t radioCommandId,
    uint32_t sessionNonce,
    const char* commandId,
    const Rpv2FenceChunkPlan& plan,
    const char** reason);
static bool prepareFenceWakeSession(
    uint32_t deviceId,
    const JsonVariantConst payload,
    const char* commandId,
    const FencePointsResolution& pointsResolution,
    const char** reason);
static void finalizeFenceCommandIfAllTargetsTerminal();
static void failPendingWakeSession(PendingWakeSession& session, uint16_t reasonCode, const char* reasonLabel);
static void processPendingWakeSessions();
static void logRpv2StageTransition(
    uint32_t deviceId,
    const char* commandId,
    const char* fromStage,
    const char* toStage);

enum class QueueLoadResult : uint8_t {
  kLoaded = 0,
  kEmpty = 1,
  kContentError = 2,
};

struct FencePointsResolution {
  JsonArrayConst points;
  const char* source = "none";
};
static const char* backhaulStateLabel(BackhaulDiagState state);
static const char* backhaulOledLabel(BackhaulDiagState state);
static void refreshBackhaulNetworkSnapshot();
static void setBackhaulDiagState(
    BackhaulDiagState state,
    const char* summary,
    bool forceLog = false);
static void updateBackhaulDiagState(
    uint32_t now,
    bool timeoutExpired = false,
    bool forceLog = false);
static void emitBackhaulHeartbeatIfNeeded(uint32_t now);
static void logBackhaulConnectedSnapshot();
void fillBackhaulDiagJson(JsonObject obj);
void runBackhaulManualDiagnostic();

static const char* otaErrorText(ota_error_t error) {
  switch (error) {
    case OTA_AUTH_ERROR: return "auth";
    case OTA_BEGIN_ERROR: return "begin";
    case OTA_CONNECT_ERROR: return "connect";
    case OTA_RECEIVE_ERROR: return "receive";
    case OTA_END_ERROR: return "end";
    default: return "unknown";
  }
}

static const char* wifiStatusLabel(wl_status_t status) {
  switch (status) {
    case WL_NO_SHIELD: return "no_shield";
    case WL_IDLE_STATUS: return "idle";
    case WL_NO_SSID_AVAIL: return "no_ssid";
    case WL_SCAN_COMPLETED: return "scan_completed";
    case WL_CONNECTED: return "connected";
    case WL_CONNECT_FAILED: return "connect_failed";
    case WL_CONNECTION_LOST: return "connection_lost";
    case WL_DISCONNECTED: return "disconnected";
    case WL_STOPPED: return "stopped";
    default: return "unknown";
  }
}

static const char* wifiDisconnectReasonLabel(wifi_err_reason_t reason) {
  const char* label = WiFi.disconnectReasonName(reason);
  return (label != nullptr && label[0] != '\0') ? label : "unknown";
}

static const char* wifiAuthModeLabel(wifi_auth_mode_t authMode) {
  switch (authMode) {
    case WIFI_AUTH_OPEN: return "OPEN";
    case WIFI_AUTH_WEP: return "WEP";
    case WIFI_AUTH_WPA_PSK: return "WPA_PSK";
    case WIFI_AUTH_WPA2_PSK: return "WPA2_PSK";
    case WIFI_AUTH_WPA_WPA2_PSK: return "WPA_WPA2_PSK";
    case WIFI_AUTH_WPA2_ENTERPRISE: return "WPA2_ENTERPRISE";
    case WIFI_AUTH_WPA3_PSK: return "WPA3_PSK";
    case WIFI_AUTH_WPA2_WPA3_PSK: return "WPA2_WPA3_PSK";
    case WIFI_AUTH_WAPI_PSK: return "WAPI_PSK";
    case WIFI_AUTH_OWE: return "OWE";
    case WIFI_AUTH_WPA3_ENT_192: return "WPA3_ENT_192";
    default: return "UNKNOWN";
  }
}

static const char* backhaulStateLabel(BackhaulDiagState state) {
  switch (state) {
    case BackhaulDiagState::kDisabled: return "disabled";
    case BackhaulDiagState::kIdle: return "idle";
    case BackhaulDiagState::kConnecting: return "connecting";
    case BackhaulDiagState::kAssociatedNoIp: return "associated_no_ip";
    case BackhaulDiagState::kConnected: return "connected";
    case BackhaulDiagState::kNoSsid: return "no_ssid";
    case BackhaulDiagState::kAuthFailed: return "auth_failed";
    case BackhaulDiagState::kDhcpTimeout: return "dhcp_timeout";
    case BackhaulDiagState::kConnectionLost: return "connection_lost";
    case BackhaulDiagState::kRetryWait: return "retry_wait";
    default: return "unknown_failure";
  }
}

static const char* backhaulOledLabel(BackhaulDiagState state) {
  switch (state) {
    case BackhaulDiagState::kConnected: return "OK";
    case BackhaulDiagState::kConnecting: return "CONN";
    case BackhaulDiagState::kAssociatedNoIp: return "DHCP";
    case BackhaulDiagState::kNoSsid: return "NO SSID";
    case BackhaulDiagState::kAuthFailed: return "AUTH";
    case BackhaulDiagState::kDhcpTimeout: return "DHCP";
    case BackhaulDiagState::kConnectionLost: return "LOST";
    case BackhaulDiagState::kRetryWait: return "RETRY";
    case BackhaulDiagState::kDisabled: return "OFF";
    default: return "IDLE";
  }
}

static bool ipAddressLooksValid(const IPAddress& ip) {
  return !(ip[0] == 0 && ip[1] == 0 && ip[2] == 0 && ip[3] == 0);
}

static bool containsReasonToken(const char* text, const char* token) {
  return text && token && strstr(text, token) != nullptr;
}

static bool isAuthFailureReason(const char* reasonLabel) {
  return containsReasonToken(reasonLabel, "AUTH") ||
         containsReasonToken(reasonLabel, "HANDSHAKE") ||
         containsReasonToken(reasonLabel, "MIC_FAILURE") ||
         containsReasonToken(reasonLabel, "AKMP");
}

static bool isNoSsidReason(const char* reasonLabel) {
  return containsReasonToken(reasonLabel, "NO_AP_FOUND") ||
         containsReasonToken(reasonLabel, "BEACON_TIMEOUT");
}

static const char* summarizeBackhaulFailure(bool timeoutExpired) {
  const char* reasonLabel = wifiDisconnectReasonLabel(backhaulDiag.lastDisconnectReason);
  if (WiFi.status() == WL_CONNECTED && ipAddressLooksValid(WiFi.localIP())) {
    return "connected_ok";
  }
  if (!backhaulDiag.targetVisible && (timeoutExpired || isNoSsidReason(reasonLabel))) {
    return "ssid_nao_visivel";
  }
  if (isAuthFailureReason(reasonLabel)) {
    return "senha_incorreta_ou_autenticacao_falhou";
  }
  if ((timeoutExpired || backhaulDiag.associated) && !ipAddressLooksValid(WiFi.localIP())) {
    return "dhcp_sem_resposta";
  }
  if (backhaulDiag.targetVisible && backhaulDiag.targetRssi != 0 &&
      backhaulDiag.targetRssi <= -82) {
    return "sinal_fraco";
  }
  if (backhaulDiag.targetVisible && !backhaulDiag.associated) {
    return "target_visible_auth_ok_no_assoc";
  }
  if (backhaulDiag.lastSuccessAtMs != 0) {
    return "conexao_perdida";
  }
  return "falha_indeterminada";
}

static void refreshBackhaulNetworkSnapshot() {
  backhaulDiag.wlStatus = WiFi.status();
  backhaulDiag.lastDisconnectReason = cloudBackhaulLastDisconnectReason;
  backhaulDiag.connectStartedAtMs = cloudBackhaulConnectStartedAtMs;
  copyStringToBuffer(backhaulDiag.ip, sizeof(backhaulDiag.ip), WiFi.localIP().toString().c_str());
  copyStringToBuffer(
      backhaulDiag.gateway, sizeof(backhaulDiag.gateway), WiFi.gatewayIP().toString().c_str());
  copyStringToBuffer(backhaulDiag.dns, sizeof(backhaulDiag.dns), WiFi.dnsIP().toString().c_str());
}

static void setBackhaulDiagState(
    BackhaulDiagState state,
    const char* summary,
    bool forceLog) {
  refreshBackhaulNetworkSnapshot();
  const BackhaulDiagState previousState = backhaulDiag.state;
  const bool stateChanged = backhaulDiag.state != state;
  const bool summaryChanged =
      summary && summary[0] != '\0' &&
      strncmp(backhaulDiag.lastSummary, summary, sizeof(backhaulDiag.lastSummary) - 1) != 0;
  if (summary && summary[0] != '\0') {
    copyStringToBuffer(backhaulDiag.lastSummary, sizeof(backhaulDiag.lastSummary), summary);
  }
  if (stateChanged) {
    backhaulDiag.state = state;
    backhaulDiag.lastStateChangeAtMs = millis();
  }
  if (!(forceLog || stateChanged || summaryChanged)) return;

  const char* prevState = backhaulStateLabel(previousState);
  const char* newState = backhaulStateLabel(state);
  const bool warn =
      state == BackhaulDiagState::kNoSsid ||
      state == BackhaulDiagState::kAuthFailed ||
      state == BackhaulDiagState::kDhcpTimeout ||
      state == BackhaulDiagState::kConnectionLost ||
      state == BackhaulDiagState::kUnknownFailure;
  if (warn) {
    LOGW(
        "Backhaul transicao: %s -> %s wl=%s(%d) reason=%s(%u) resumo=%s",
        prevState,
        newState,
        wifiStatusLabel(backhaulDiag.wlStatus),
        (int)backhaulDiag.wlStatus,
        wifiDisconnectReasonLabel(backhaulDiag.lastDisconnectReason),
        (unsigned)backhaulDiag.lastDisconnectReason,
        backhaulDiag.lastSummary);
  } else {
    LOGI(
        "Backhaul transicao: %s -> %s wl=%s(%d) resumo=%s",
        prevState,
        newState,
        wifiStatusLabel(backhaulDiag.wlStatus),
        (int)backhaulDiag.wlStatus,
        backhaulDiag.lastSummary);
  }
#if RT_MATRIX_OLED_ENABLED
  if (state != BackhaulDiagState::kConnected) {
    drawStatus("Backhaul", backhaulOledLabel(state));
  }
#endif
}

static void updateBackhaulDiagState(
    uint32_t now,
    bool timeoutExpired,
    bool forceLog) {
  refreshBackhaulNetworkSnapshot();
  backhaulDiag.retryDelayMs = 0;
  if (!cfg::FEATURE_BACKHAUL || !cloudTelemetryConfigured()) {
    setBackhaulDiagState(BackhaulDiagState::kDisabled, "disabled", forceLog);
    return;
  }

  const bool connected =
      backhaulDiag.wlStatus == WL_CONNECTED && ipAddressLooksValid(WiFi.localIP());
  if (connected) {
    backhaulDiag.lastSuccessAtMs = now;
    setBackhaulDiagState(BackhaulDiagState::kConnected, "connected_ok", forceLog);
    return;
  }

  if (cloudBackhaulConnecting) {
    if (backhaulDiag.associated) {
      setBackhaulDiagState(
          timeoutExpired ? BackhaulDiagState::kDhcpTimeout : BackhaulDiagState::kAssociatedNoIp,
          timeoutExpired ? "dhcp_sem_resposta" : "aguardando_dhcp",
          forceLog);
      return;
    }
    const char* summary = summarizeBackhaulFailure(timeoutExpired);
    if (timeoutExpired && strcmp(summary, "ssid_nao_visivel") == 0) {
      setBackhaulDiagState(BackhaulDiagState::kNoSsid, summary, forceLog);
      return;
    }
    if (timeoutExpired && strcmp(summary, "senha_incorreta_ou_autenticacao_falhou") == 0) {
      setBackhaulDiagState(BackhaulDiagState::kAuthFailed, summary, forceLog);
      return;
    }
    setBackhaulDiagState(BackhaulDiagState::kConnecting, "tentando_conectar", forceLog);
    return;
  }

  if (cloudBackhaulAttemptAtMs != 0) {
    const uint32_t elapsed = (uint32_t)(now - cloudBackhaulAttemptAtMs);
    if (elapsed < cfg::CLOUD_BACKHAUL_RETRY_MS) {
      backhaulDiag.retryDelayMs = cfg::CLOUD_BACKHAUL_RETRY_MS - elapsed;
      setBackhaulDiagState(BackhaulDiagState::kRetryWait, summarizeBackhaulFailure(false), forceLog);
      return;
    }
  }

  const char* summary = summarizeBackhaulFailure(false);
  if (strcmp(summary, "ssid_nao_visivel") == 0) {
    setBackhaulDiagState(BackhaulDiagState::kNoSsid, summary, forceLog);
    return;
  }
  if (strcmp(summary, "senha_incorreta_ou_autenticacao_falhou") == 0) {
    setBackhaulDiagState(BackhaulDiagState::kAuthFailed, summary, forceLog);
    return;
  }
  if (strcmp(summary, "dhcp_sem_resposta") == 0) {
    setBackhaulDiagState(BackhaulDiagState::kDhcpTimeout, summary, forceLog);
    return;
  }
  if (backhaulDiag.lastSuccessAtMs != 0) {
    setBackhaulDiagState(BackhaulDiagState::kConnectionLost, summary, forceLog);
    return;
  }
  setBackhaulDiagState(BackhaulDiagState::kIdle, "idle", forceLog);
}

static void emitBackhaulHeartbeatIfNeeded(uint32_t now) {
  updateBackhaulDiagState(now);
  const bool connected = backhaulDiag.state == BackhaulDiagState::kConnected;
  const uint32_t interval =
      connected ? kBackhaulDiagHeartbeatConnectedMs : kBackhaulDiagHeartbeatWhileUnhealthyMs;
  if (backhaulDiag.lastHeartbeatAtMs != 0 &&
      (uint32_t)(now - backhaulDiag.lastHeartbeatAtMs) < interval) {
    return;
  }
  backhaulDiag.lastHeartbeatAtMs = now;
  const uint32_t elapsed =
      backhaulDiag.connectStartedAtMs == 0 ? 0 : (uint32_t)(now - backhaulDiag.connectStartedAtMs);
  LOGI(
      "Backhaul status: state=%s wl=%s(%d) elapsed_ms=%lu attempt=%lu reason=%s(%u) target_visible=%d target_rssi=%d ip=%s",
      backhaulStateLabel(backhaulDiag.state),
      wifiStatusLabel(backhaulDiag.wlStatus),
      (int)backhaulDiag.wlStatus,
      (unsigned long)elapsed,
      (unsigned long)backhaulDiag.attemptCount,
      wifiDisconnectReasonLabel(backhaulDiag.lastDisconnectReason),
      (unsigned)backhaulDiag.lastDisconnectReason,
      backhaulDiag.targetVisible ? 1 : 0,
      (int)backhaulDiag.targetRssi,
      backhaulDiag.ip);
}

static void logBackhaulConnectedSnapshot() {
  refreshBackhaulNetworkSnapshot();
  LOGI(
      "Backhaul snapshot: state=%s ssid=%s rssi=%d channel=%ld ip=%s gateway=%s dns=%s",
      backhaulStateLabel(backhaulDiag.state),
      cfg::BACKHAUL_WIFI_SSID,
      (int)WiFi.RSSI(),
      (long)WiFi.channel(),
      backhaulDiag.ip,
      backhaulDiag.gateway,
      backhaulDiag.dns);
}

void fillBackhaulDiagJson(JsonObject obj) {
  const uint32_t now = millis();
  updateBackhaulDiagState(now);
  obj["enabled"] = cfg::FEATURE_BACKHAUL && cloudTelemetryConfigured();
  obj["state"] = backhaulStateLabel(backhaulDiag.state);
  obj["wl_status"] = wifiStatusLabel(backhaulDiag.wlStatus);
  obj["ssid"] = cfg::BACKHAUL_WIFI_SSID;
  obj["attempt_count"] = backhaulDiag.attemptCount;
  obj["connecting"] = cloudBackhaulConnecting;
  obj["elapsed_ms"] =
      backhaulDiag.connectStartedAtMs == 0 ? 0 : (uint32_t)(now - backhaulDiag.connectStartedAtMs);
  obj["retry_delay_ms"] = backhaulDiag.retryDelayMs;
  obj["last_disconnect_reason_code"] = (unsigned)backhaulDiag.lastDisconnectReason;
  obj["last_disconnect_reason_label"] = wifiDisconnectReasonLabel(backhaulDiag.lastDisconnectReason);
  obj["ip"] = backhaulDiag.ip;
  obj["gateway"] = backhaulDiag.gateway;
  obj["dns"] = backhaulDiag.dns;
  obj["rssi"] = WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : backhaulDiag.targetRssi;
  obj["channel"] = WiFi.status() == WL_CONNECTED ? WiFi.channel() : backhaulDiag.targetChannel;
  obj["last_diag_summary"] = backhaulDiag.lastSummary;
  obj["target_visible"] = backhaulDiag.targetVisible;
  obj["target_rssi"] = backhaulDiag.targetRssi;
  obj["target_channel"] = backhaulDiag.targetChannel;
  obj["target_bssid"] = backhaulDiag.targetBssid;
  obj["target_auth"] = wifiAuthModeLabel(backhaulDiag.targetAuth);
  obj["associated"] = backhaulDiag.associated;
  obj["last_success_at_ms"] = backhaulDiag.lastSuccessAtMs;
}

void runBackhaulManualDiagnostic() {
  const uint32_t now = millis();
  cloudBackhaulLastDiagScanAtMs = 0;
  backhaulDiag.lastHeartbeatAtMs = 0;
  logBackhaulScanDiagnostics(now);
  updateBackhaulDiagState(now, cloudBackhaulConnecting, true);
  emitBackhaulHeartbeatIfNeeded(now);
}

static void logBackhaulScanDiagnostics(uint32_t now) {
  if (cloudBackhaulLastDiagScanAtMs != 0 &&
      (uint32_t)(now - cloudBackhaulLastDiagScanAtMs) <
          cfg::CLOUD_BACKHAUL_DIAG_SCAN_INTERVAL_MS) {
    return;
  }
  cloudBackhaulLastDiagScanAtMs = now;

  LOGI("Backhaul Wi-Fi: escaneando SSID alvo=%s", cfg::BACKHAUL_WIFI_SSID);
  const int16_t networkCount = WiFi.scanNetworks(false, true);
  if (networkCount < 0) {
    LOGW("Backhaul Wi-Fi: scan falhou codigo=%d", (int)networkCount);
    WiFi.scanDelete();
    return;
  }

  uint8_t matchCount = 0;
  int16_t bestRssi = -127;
  int16_t bestIndex = -1;
  for (int16_t i = 0; i < networkCount; ++i) {
    const String ssid = WiFi.SSID((uint8_t)i);
    if (ssid != cfg::BACKHAUL_WIFI_SSID) continue;
    matchCount++;
    const int16_t rssi = WiFi.RSSI((uint8_t)i);
    if (bestIndex < 0 || rssi > bestRssi) {
      bestIndex = i;
      bestRssi = rssi;
    }
    LOGI(
        "Backhaul scan alvo[%u/%d]: bssid=%s canal=%d rssi=%d auth=%s(%d)",
        (unsigned)matchCount,
        (int)networkCount,
        WiFi.BSSIDstr((uint8_t)i).c_str(),
        (int)WiFi.channel((uint8_t)i),
        (int)rssi,
        wifiAuthModeLabel(WiFi.encryptionType((uint8_t)i)),
        (int)WiFi.encryptionType((uint8_t)i));
  }

  if (matchCount == 0) {
    backhaulDiag.targetVisible = false;
    backhaulDiag.targetRssi = 0;
    backhaulDiag.targetChannel = 0;
    backhaulDiag.targetAuth = WIFI_AUTH_OPEN;
    backhaulDiag.targetBssid[0] = '\0';
    LOGW("Backhaul scan: SSID alvo %s nao apareceu entre %d redes visiveis",
         cfg::BACKHAUL_WIFI_SSID, (int)networkCount);
  } else if (bestIndex >= 0) {
    backhaulDiag.targetVisible = true;
    backhaulDiag.targetRssi = WiFi.RSSI((uint8_t)bestIndex);
    backhaulDiag.targetChannel = WiFi.channel((uint8_t)bestIndex);
    backhaulDiag.targetAuth = WiFi.encryptionType((uint8_t)bestIndex);
    copyStringToBuffer(
        backhaulDiag.targetBssid,
        sizeof(backhaulDiag.targetBssid),
        WiFi.BSSIDstr((uint8_t)bestIndex).c_str());
    LOGW(
        "Backhaul diagnostico: ssid_visivel=1 associou=%d ip=%s causa_provavel=%s",
        backhaulDiag.associated ? 1 : 0,
        backhaulDiag.ip,
        summarizeBackhaulFailure(true));
  }
  if (matchCount == 0) {
    copyStringToBuffer(
        backhaulDiag.lastSummary,
        sizeof(backhaulDiag.lastSummary),
        "ssid_nao_visivel");
    LOGW("Backhaul diagnostico: causa_provavel=ssid_nao_visivel");
  } else {
    copyStringToBuffer(
        backhaulDiag.lastSummary,
        sizeof(backhaulDiag.lastSummary),
        summarizeBackhaulFailure(true));
  }
  WiFi.scanDelete();
}

static void logOtaPartitionInfo(const char* context) {
  const esp_partition_t* running = esp_ota_get_running_partition();
  const esp_partition_t* next = esp_ota_get_next_update_partition(NULL);
  LOGI("OTA particoes (%s): running=%s size=0x%lx next=%s size=0x%lx",
       context ? context : "-",
       running ? running->label : "null",
       running ? (unsigned long)running->size : 0UL,
       next ? next->label : "null",
       next ? (unsigned long)next->size : 0UL);
  if (!next) {
    LOGE("OTA sem particao de update. Grave 1x via USB com Partition Scheme OTA (min_spiffs).");
  }
}

static String compactIdentifier(const String& raw) {
  String out;
  out.reserve(raw.length());
  for (size_t i = 0; i < raw.length(); ++i) {
    const char c = raw[i];
    if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') ||
        (c >= 'a' && c <= 'f')) {
      out += (char)toupper((unsigned char)c);
    }
  }
  return out;
}

static String gatewayNodeId() {
  String id = compactIdentifier(WiFi.softAPmacAddress());
  if (id.isEmpty()) id = compactIdentifier(WiFi.macAddress());
  return id;
}

static String gatewayAdvName(const String& nodeId) {
  if (nodeId.isEmpty()) return String(cfg::BLE_DEVICE_PREFIX);
  const String suffix =
      nodeId.length() > 6 ? nodeId.substring(nodeId.length() - 6) : nodeId;
  return String(cfg::BLE_DEVICE_PREFIX) + "-" + suffix;
}

static String gatewayApSsid() {
  String suffix = gatewayNodeId();
  if (suffix.length() > 6) suffix = suffix.substring(suffix.length() - 6);
  String ssid = String(cfg::AP_SSID) + "-" + suffix;
  if (ssid.length() > 31) ssid = ssid.substring(0, 31);
  return ssid;
}

static void copyStringToBuffer(char* dst, size_t dstSize, const char* src) {
  if (dstSize == 0) return;
  if (src == nullptr) {
    dst[0] = '\0';
    return;
  }
  strncpy(dst, src, dstSize - 1);
  dst[dstSize - 1] = '\0';
}

static String scopeIdToHex(uint64_t scopeId) {
  char out[17];
  snprintf(out, sizeof(out), "%016llX", (unsigned long long)scopeId);
  return String(out);
}

static String payloadBytesToString(const uint8_t* data, size_t len) {
  String out;
  if (!data || len == 0) return out;
  if (len > 128) len = 128;
  out.reserve(len);
  for (size_t i = 0; i < len; ++i) {
    out += (char)data[i];
  }
  return out;
}

static void primeSpiChipSelectLines() {
  pinMode(cfg::PIN_LORA_CS, OUTPUT);
  digitalWrite(cfg::PIN_LORA_CS, HIGH);
  pinMode(cfg::PIN_SD_CS, OUTPUT);
  digitalWrite(cfg::PIN_SD_CS, HIGH);
}

static bool backhaulWindowOpen() {
  if (!cfg::FEATURE_BACKHAUL) return false;
  const uint32_t now = millis();
  if ((uint32_t)(now - bootStartedAtMs) < kBackhaulStartupDelayMs) return false;
  const uint32_t lastRawRxAtMs = lora.lastRawRxAtMs();
  if (lastRawRxAtMs != 0 &&
      (uint32_t)(now - lastRawRxAtMs) < kAcceptedUplinkQuietMs) {
    return false;
  }
  return true;
}

static const char* pickFirstText(
    const JsonVariantConst a,
    const JsonVariantConst b = JsonVariantConst(),
    const JsonVariantConst c = JsonVariantConst(),
    const JsonVariantConst d = JsonVariantConst()) {
  const JsonVariantConst values[] = {a, b, c, d};
  for (const JsonVariantConst value : values) {
    if (!value.is<const char*>()) continue;
    const char* text = value.as<const char*>();
    if (text && text[0] != '\0') return text;
  }
  return "";
}

static void copyAuditMetadataFromPayload(
    JsonObject dst,
    const JsonVariantConst payload) {
  const char* polygonKind = pickFirstText(
      payload["polygon_kind"], payload["polygonKind"]);
  const char* originDocType = pickFirstText(
      payload["origin_doc_type"], payload["originDocType"]);
  const char* originDocId = pickFirstText(
      payload["origin_doc_id"], payload["originDocId"], payload["operation_id"]);
  if (polygonKind[0] != '\0') dst["polygonKind"] = polygonKind;
  if (originDocType[0] != '\0') dst["originDocType"] = originDocType;
  if (originDocId[0] != '\0') dst["originDocId"] = originDocId;
}

static void copyTargetDeviceIdsFromActiveCommand(JsonObject dst) {
  if (activeSimpleCommand.targetDeviceCommand) {
    JsonArray targets = dst["targetDeviceIds"].to<JsonArray>();
    for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
      targets.add(activeSimpleCommand.targets[i].targetId);
    }
    return;
  }

  JsonArray targets = dst["targetGatewayIds"].to<JsonArray>();
  for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
    targets.add(activeSimpleCommand.targets[i].targetId);
  }
}

static bool beginBindingPrefs() {
  if (bindingPrefsReady) return true;
  bindingPrefsReady = bindingPrefs.begin("binding", false);
  if (!bindingPrefsReady) LOGW("Falha ao abrir NVS binding");
  return bindingPrefsReady;
}

static bool computeBindingReadyState() {
  return bindingPropertyId[0] != '\0' &&
         bindingMatrixGatewayId[0] != '\0' &&
         rtcmd::isValidScopeId(bindingPropertyScopeId);
}

static uint64_t bindingScopeIdValue() {
  if (!computeBindingReadyState()) return 0;
  return strtoull(bindingPropertyScopeId, nullptr, 16);
}

static void loadBindingConfig() {
  bindingPropertyId[0] = '\0';
  bindingPropertyScopeId[0] = '\0';
  bindingMatrixGatewayId[0] = '\0';
  bindingVersion = 0;
  bindingReady = false;
  if (!beginBindingPrefs()) return;

  bindingPrefs.getString("property_id", bindingPropertyId, sizeof(bindingPropertyId));
  bindingPrefs.getString("scope_id", bindingPropertyScopeId, sizeof(bindingPropertyScopeId));
  bindingPrefs.getString("matrix_gid", bindingMatrixGatewayId, sizeof(bindingMatrixGatewayId));
  bindingVersion = bindingPrefs.getUInt("bind_ver", 0);
  bindingReady = computeBindingReadyState();
  LOGI(
      "Binding matriz: ready=%d property=%s scope=%s matrix=%s ver=%lu",
      bindingReady ? 1 : 0,
      bindingPropertyId[0] ? bindingPropertyId : "-",
      bindingPropertyScopeId[0] ? bindingPropertyScopeId : "-",
      bindingMatrixGatewayId[0] ? bindingMatrixGatewayId : "-",
      (unsigned long)bindingVersion);
}

static bool persistBindingConfig(const JsonVariantConst payload, const char** reason) {
  const char* propertyId = pickFirstText(payload["property_id"], payload["propertyId"]);
  const char* propertyScopeId = pickFirstText(
      payload["property_scope_id"], payload["propertyScopeId"], payload["scope_id"]);
  const char* matrixGatewayId = pickFirstText(
      payload["matrix_gateway_id"], payload["matrixGatewayId"]);
  uint32_t nextBindingVersion =
      payload["binding_version"].is<uint32_t>()
          ? payload["binding_version"].as<uint32_t>()
          : (payload["bindingVersion"] | 1U);

  if (!propertyId[0]) {
    if (reason) *reason = "missing_property_id";
    return false;
  }
  if (!rtcmd::isValidScopeId(propertyScopeId)) {
    if (reason) *reason = "invalid_property_scope_id";
    return false;
  }
  if (!matrixGatewayId[0]) {
    if (reason) *reason = "missing_matrix_gateway_id";
    return false;
  }
  if (nextBindingVersion == 0) nextBindingVersion = 1;
  if (!beginBindingPrefs()) {
    if (reason) *reason = "binding_prefs_unavailable";
    return false;
  }

  copyStringToBuffer(bindingPropertyId, sizeof(bindingPropertyId), propertyId);
  copyStringToBuffer(
      bindingPropertyScopeId, sizeof(bindingPropertyScopeId), propertyScopeId);
  copyStringToBuffer(
      bindingMatrixGatewayId, sizeof(bindingMatrixGatewayId), matrixGatewayId);
  bindingVersion = nextBindingVersion;
  bindingReady = computeBindingReadyState();

  bindingPrefs.putString("property_id", bindingPropertyId);
  bindingPrefs.putString("scope_id", bindingPropertyScopeId);
  bindingPrefs.putString("matrix_gid", bindingMatrixGatewayId);
  bindingPrefs.putUInt("bind_ver", bindingVersion);
  return bindingReady;
}

static bool scopeMatchesBinding(uint64_t scopeId) {
  return bindingReady && scopeId != 0 && scopeId == bindingScopeIdValue();
}

static void restoreDownlinkSeq() {
  seqDown = 1;
  seqPrefsReady = seqPrefs.begin("lora_down", false);
  if (!seqPrefsReady) {
    LOGW("NVS indisponivel para seqDown; iniciando em 1.");
    return;
  }

  if (!seqPrefs.isKey("seq")) {
    // Primeiro boot apos update: evita colisao com lastSeqSeen_ ja alto na coleira.
    seqDown = (esp_random() & 0x7FFFFFFFUL) | 0x40000000UL;
    if (seqPrefs.putULong("seq", seqDown - 1) != sizeof(uint32_t)) {
      LOGW("Falha ao inicializar persistencia de seqDown=%lu", seqDown);
    }
    LOGI("seqDown inicializado=%lu (seed aleatorio)", seqDown);
    return;
  }

  const uint32_t persisted = seqPrefs.getULong("seq", seqDown - 1);
  seqDown = persisted + 1;
  if (seqDown == 0) seqDown = 1;
  LOGI("seqDown restaurado=%lu (persistido=%lu)", seqDown, persisted);
}

static uint32_t nextDownlinkSeq() {
  if (seqDown == 0) seqDown = 1;
  const uint32_t out = seqDown++;
  if (seqDown == 0) seqDown = 1;

  if (seqPrefsReady && seqPrefs.putULong("seq", out) != sizeof(uint32_t)) {
    LOGW("Falha ao persistir seqDown=%lu", out);
  }
  return out;
}

static String sanitizeRtdbKey(String value) {
  value.trim();
  if (value.isEmpty()) return value;
  value.replace('.', '_');
  value.replace('#', '_');
  value.replace('$', '_');
  value.replace('[', '_');
  value.replace(']', '_');
  value.replace('/', '_');
  return value;
}

static bool isUnsetCloudValue(const char* value) {
  if (value == nullptr) return true;
  while (*value == ' ' || *value == '\t' || *value == '\r' || *value == '\n') {
    ++value;
  }
  if (*value == '\0') return true;
  return strncmp(value, "SET_", 4) == 0 ||
         strncmp(value, "CHANGE_ME", 9) == 0 ||
         strncmp(value, "YOUR_", 5) == 0;
}

static bool cloudTelemetryConfigured() {
  if (!cfg::FEATURE_CLOUD) return false;

  const bool backhaulSsidOk = !isUnsetCloudValue(cfg::BACKHAUL_WIFI_SSID);
  const bool backhaulPassOk =
      cfg::BACKHAUL_WIFI_PASS[0] == '\0' || !isUnsetCloudValue(cfg::BACKHAUL_WIFI_PASS);
  const bool hostOk = !isUnsetCloudValue(cfg::SUPABASE_EDGE_HOST);
  const bool matrixIdOk =
      cfg::RTDB_MATRIX_ID[0] == '\0' || !isUnsetCloudValue(cfg::RTDB_MATRIX_ID);
  const bool writerKeyOk = !isUnsetCloudValue(cfg::RTDB_WRITER_KEY);
  const bool configured =
      backhaulSsidOk && backhaulPassOk && hostOk && matrixIdOk && writerKeyOk;

  static bool warned = false;
  if (!configured && !warned) {
    LOGW("Cloud telemetry desativada: substitua placeholders SET_* em manual_settings.local.h");
    warned = true;
  } else if (configured && warned) {
    warned = false;
  }
  return configured;
}

static String matrixCloudId() {
  if (cfg::RTDB_MATRIX_ID[0] != '\0' && !isUnsetCloudValue(cfg::RTDB_MATRIX_ID)) {
    return sanitizeRtdbKey(String(cfg::RTDB_MATRIX_ID));
  }
  return sanitizeRtdbKey(gatewayNodeId());
}

static uint64_t parseScopeIdHex(const JsonVariantConst value) {
  const char* text = value.is<const char*>() ? value.as<const char*>() : "";
  if (!text || !text[0] || !rtcmd::isValidScopeId(text)) return 0;
  return strtoull(text, nullptr, 16);
}

static uint32_t unixNowSec() {
  const time_t wall = time(nullptr);
  if (wall > 1700000000) return (uint32_t)wall;
  const DateTime nowRtc = rtc.now();
  if (nowRtc.year() >= 2023) return nowRtc.unixtime();
  return millis() / 1000;
}

static uint64_t unixNowMs(uint32_t unixSec) {
  // Mantem alinhamento com unixNowSec() e adiciona granularidade sub-segundo.
  return ((uint64_t)unixSec * 1000ULL) + (uint64_t)(millis() % 1000UL);
}

static String utcDayKey(uint32_t unixSec) {
  time_t raw = (time_t)unixSec;
  struct tm tmUtc;
  gmtime_r(&raw, &tmUtc);
  char out[9];
  snprintf(out, sizeof(out), "%04d%02d%02d", tmUtc.tm_year + 1900,
           tmUtc.tm_mon + 1, tmUtc.tm_mday);
  return String(out);
}

static String urlEncodeComponent(const String& input) {
  String out;
  out.reserve(input.length() * 3);
  for (size_t i = 0; i < input.length(); ++i) {
    const char ch = input.charAt(i);
    const bool safe =
        (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
        (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' ||
        ch == '.' || ch == '~';
    if (safe) {
      out += ch;
      continue;
    }
    char buf[4];
    snprintf(buf, sizeof(buf), "%%%02X", (unsigned char)ch);
    out += buf;
  }
  return out;
}

static void fillCloudWriteTrace(
    CloudWriteTrace* trace,
    bool ok,
    int httpStatus,
    uint32_t elapsedMs,
    const char* stage,
    const char* detail) {
  if (!trace) return;
  trace->ok = ok;
  trace->httpStatus = httpStatus;
  trace->elapsedMs = elapsedMs;
  copyStringToBuffer(trace->stage, sizeof(trace->stage), stage && stage[0] ? stage : "unknown");
  copyStringToBuffer(trace->detail, sizeof(trace->detail), detail && detail[0] ? detail : "-");
}

static int parseHttpStatusCode(const String& statusLine) {
  const int firstSpace = statusLine.indexOf(' ');
  if (firstSpace < 0) return 0;
  const int secondSpace = statusLine.indexOf(' ', firstSpace + 1);
  const String codeText =
      secondSpace > firstSpace ? statusLine.substring(firstSpace + 1, secondSpace)
                               : statusLine.substring(firstSpace + 1);
  return codeText.toInt();
}

static String summarizeHttpFailureDetail(
    const String& statusLine,
    const String& responseBody) {
  String detail = responseBody;
  detail.trim();
  if (detail.isEmpty()) {
    detail = statusLine;
    detail.trim();
  }
  detail.replace('\r', ' ');
  detail.replace('\n', ' ');
  if (detail.length() > 88) {
    detail.remove(88);
  }
  return detail;
}

static bool rtdbRequest(
    const char* method,
    const String& path,
    const String& body,
    String* responseBody = nullptr,
    CloudWriteTrace* trace = nullptr) {
  if (WiFi.status() != WL_CONNECTED) {
    fillCloudWriteTrace(trace, false, 0, 0, "wifi", "disconnected");
    setLastCloudWriteError("wifi", path);
    return false;
  }
  if (path.isEmpty()) {
    fillCloudWriteTrace(trace, false, 0, 0, "path", "empty");
    setLastCloudWriteError("path", "-");
    return false;
  }

  const uint32_t startedAtMs = millis();
  WiFiClientSecure client;
  client.setInsecure();
  client.setTimeout(cfg::CLOUD_HTTP_TIMEOUT_MS);
  if (!client.connect(cfg::SUPABASE_EDGE_HOST, 443)) {
    fillCloudWriteTrace(
        trace,
        false,
        0,
        (uint32_t)(millis() - startedAtMs),
        "connect",
        "tls_connect_failed");
    setLastCloudWriteError("connect", path);
    return false;
  }

  const String reqPath =
      String("/functions/v1/matrix-cloud?path=") + urlEncodeComponent(path);
  const size_t bodyLen = body.length();
  client.print(method);
  client.print(" ");
  client.print(reqPath);
  client.print(" HTTP/1.1\r\nHost: ");
  client.print(cfg::SUPABASE_EDGE_HOST);
  client.print(
      "\r\nUser-Agent: ruraltech-matrix\r\nConnection: close\r\nAccept: application/json\r\nContent-Type: application/json\r\nx-matrix-writer-key: ");
  client.print(cfg::RTDB_WRITER_KEY);
  client.print("\r\nContent-Length: ");
  client.print((unsigned long)bodyLen);
  client.print("\r\n\r\n");
  if (bodyLen > 0) client.print(body);

  const String statusLine = client.readStringUntil('\n');
  const int httpStatus = parseHttpStatusCode(statusLine);
  const bool ok =
      statusLine.startsWith("HTTP/1.1 2") || statusLine.startsWith("HTTP/1.0 2");

  while (client.connected()) {
    const String line = client.readStringUntil('\n');
    if (line == "\r" || line.length() == 0) break;
  }
  String bodyRead;
  if (responseBody) {
    bodyRead = client.readString();
    *responseBody = bodyRead;
  } else if (!ok) {
    bodyRead = client.readString();
  }

  const uint32_t drainStart = millis();
  while ((uint32_t)(millis() - drainStart) < 250) {
    while (client.available()) {
      client.read();
    }
    if (!client.connected()) break;
    delay(1);
  }
  client.stop();
  const uint32_t elapsedMs = (uint32_t)(millis() - startedAtMs);
  if (ok) {
    fillCloudWriteTrace(trace, true, httpStatus, elapsedMs, "ok", "ok");
    clearLastCloudWriteError();
  } else {
    const String detail = summarizeHttpFailureDetail(statusLine, bodyRead);
    fillCloudWriteTrace(trace, false, httpStatus, elapsedMs, "http", detail.c_str());
    setLastCloudWriteError("http", path + "|" + statusLine);
  }
  return ok;
}

static bool rtdbWrite(
    const char* method,
    const String& path,
    const String& body,
    CloudWriteTrace* trace = nullptr) {
  return rtdbRequest(method, path, body, nullptr, trace);
}

static bool rtdbRead(const String& path, String& body, CloudWriteTrace* trace = nullptr) {
  body = "";
  return rtdbRequest("GET", path, "", &body, trace);
}

static bool rtdbDelete(const String& path, CloudWriteTrace* trace = nullptr) {
  return rtdbRequest("DELETE", path, "", nullptr, trace);
}

static void setLastCloudWriteError(const char* stage, const String& detail) {
  const char* safeStage = (stage && stage[0] != '\0') ? stage : "cloud";
  const String safeDetail = detail.isEmpty() ? String("-") : detail;
  snprintf(
      lastCloudWriteError,
      sizeof(lastCloudWriteError),
      "%s:%s",
      safeStage,
      safeDetail.substring(0, 72).c_str());
}

static void clearLastCloudWriteError() {
  lastCloudWriteError[0] = '\0';
}

static void setQueueStreamError(const char* stage, const String& detail) {
  const char* safeStage = (stage && stage[0] != '\0') ? stage : "stream";
  const String safeDetail = detail.isEmpty() ? String("-") : detail;
  snprintf(
      queueStreamLastError,
      sizeof(queueStreamLastError),
      "%s:%s",
      safeStage,
      safeDetail.substring(0, 72).c_str());
}

static void clearQueueStreamError() {
  queueStreamLastError[0] = '\0';
}

static void requestImmediateQueueDispatch(const char* source) {
  queueDispatchRequested = true;
  queuePollAtMs = 0;
  if (source && source[0] != '\0') {
    LOGI("Fila cloud sinalizada via stream (%s)", source);
  } else {
    LOGI("Fila cloud sinalizada via stream");
  }
}

static void closeQueueCommandStream(const char* reason) {
  if (queueStreamClient.connected()) {
    queueStreamClient.stop();
  }
  queueStreamParser.reset();
  queueStreamConnected = false;
  const uint64_t nowMs = unixNowMs(unixNowSec());
  queueStreamReconnectAtUnixMs =
      nowMs + (uint64_t)cfg::CLOUD_BACKHAUL_RETRY_MS;
  queueStreamRuntime.markDisconnect(
      millis(), cfg::CLOUD_BACKHAUL_RETRY_MS, reason);
  if (reason && reason[0] != '\0') {
    setQueueStreamError("stream", String(reason));
  }
}

static bool appendPropertyCommandEvent(
    const char* propertyId,
    const char* commandId,
    const char* status,
    const char* reason,
    const DynamicJsonDocument* sourceDoc = nullptr) {
  if (!cfg::FEATURE_CLOUD) return false;
  if (!propertyId || !propertyId[0] || !commandId || !commandId[0] || !status ||
      !status[0]) {
    return false;
  }

  DynamicJsonDocument doc(1536);
  doc["type"] = status;
  doc["status"] = status;
  doc["matrixId"] = matrixCloudId();
  doc["matrixGatewayId"] = bindingMatrixGatewayId;
  doc["createdAtMs"] = unixNowMs(unixNowSec());
  doc["writer"] = "gateway_matrix";
  doc["writerKey"] = cfg::RTDB_WRITER_KEY;
  if (reason && reason[0]) doc["reason"] = reason;
  if (sourceDoc && (*sourceDoc)["command"].is<const char*>()) {
    doc["command"] = (*sourceDoc)["command"].as<const char*>();
  }
  if (sourceDoc && (*sourceDoc)["propertyScopeId"].is<const char*>()) {
    doc["propertyScopeId"] = (*sourceDoc)["propertyScopeId"].as<const char*>();
  }
  if (sourceDoc && (*sourceDoc)["requestedByUid"].is<const char*>()) {
    doc["requestedByUid"] = (*sourceDoc)["requestedByUid"].as<const char*>();
  }
  if (sourceDoc && (*sourceDoc)["requestedByRole"].is<const char*>()) {
    doc["requestedByRole"] = (*sourceDoc)["requestedByRole"].as<const char*>();
  }
  if (sourceDoc) {
    copyAuditMetadataFromPayload(doc.as<JsonObject>(), sourceDoc->as<JsonVariantConst>());
  }
  if (sourceDoc && (*sourceDoc)["targetDeviceIds"].is<JsonArrayConst>()) {
    doc["targetDeviceIds"] = (*sourceDoc)["targetDeviceIds"].as<JsonArrayConst>();
  }
  if (sourceDoc && (*sourceDoc)["targetGatewayIds"].is<JsonArrayConst>()) {
    doc["targetGatewayIds"] = (*sourceDoc)["targetGatewayIds"].as<JsonArrayConst>();
  }
  if (sourceDoc && (*sourceDoc)["deviceResults"].is<JsonObjectConst>()) {
    doc["deviceResults"] = (*sourceDoc)["deviceResults"].as<JsonObjectConst>();
  }

  String body;
  serializeJson(doc, body);
  char eventId[72];
  snprintf(
      eventId,
      sizeof(eventId),
      "%llu_%s_%lu",
      (unsigned long long)unixNowMs(unixNowSec()),
      status,
      (unsigned long)esp_random());
  return rtdbWrite(
      "PUT",
      String("propertyCommandEvents/") + sanitizeRtdbKey(String(propertyId)) + "/" +
          commandId + "/" + eventId,
      body);
}

static bool cloudPublishReady() {
  return cloudTelemetryConfigured() && backhaulWindowOpen() &&
         ensureCloudBackhaulConnected();
}

static bool publishMatrixRuntimeMirrors(bool force) {
  if (!cloudTelemetryConfigured()) return false;
  if (!force && !backhaulWindowOpen()) return false;
  if (!ensureCloudBackhaulConnected()) return false;

  const uint32_t nowTick = millis();
  if (!force && runtimeMirrorPublishAtMs != 0 &&
      (uint32_t)(nowTick - runtimeMirrorPublishAtMs) < 30000UL) {
    return true;
  }

  const String runtimeId = matrixCloudId();
  const uint64_t nowMs = unixNowMs(unixNowSec());
  DynamicJsonDocument bindingDoc(640);
  bindingDoc["propertyId"] = bindingPropertyId;
  bindingDoc["propertyScopeId"] = bindingPropertyScopeId;
  bindingDoc["matrixGatewayId"] = bindingMatrixGatewayId;
  bindingDoc["matrixRuntimeId"] = runtimeId;
  bindingDoc["enabled"] = bindingReady && supportsScopedLora;
  bindingDoc["updatedAtMs"] = nowMs;
  bindingDoc["writer"] = "gateway_matrix";
  bindingDoc["writerKey"] = cfg::RTDB_WRITER_KEY;
  String bindingBody;
  serializeJson(bindingDoc, bindingBody);

  const String runtimeBindingPath = String("matrixBindings/") + runtimeId;
  bool ok = rtdbWrite("PUT", runtimeBindingPath, bindingBody);
  if (!ok) {
    setLastCloudWriteError("binding", runtimeBindingPath);
    return false;
  }

  const String gatewayAlias = sanitizeRtdbKey(gatewayNodeId());
  if (!gatewayAlias.isEmpty() && gatewayAlias != runtimeId) {
    ok = rtdbWrite("PUT", String("matrixBindings/") + gatewayAlias, bindingBody) && ok;
  }
  const String matrixAlias = sanitizeRtdbKey(String(bindingMatrixGatewayId));
  if (!matrixAlias.isEmpty() && matrixAlias != runtimeId && matrixAlias != gatewayAlias) {
    ok = rtdbWrite("PUT", String("matrixBindings/") + matrixAlias, bindingBody) && ok;
  }

  if (!isUnsetCloudValue(cfg::RTDB_QUEUE_KEY)) {
    DynamicJsonDocument queueDoc(384);
    queueDoc["queueKey"] = cfg::RTDB_QUEUE_KEY;
    queueDoc["matrixRuntimeId"] = runtimeId;
    queueDoc["updatedAtMs"] = nowMs;
    queueDoc["writer"] = "gateway_matrix";
    queueDoc["writerKey"] = cfg::RTDB_WRITER_KEY;
    String queueBody;
    serializeJson(queueDoc, queueBody);
    const String queuePath = String("matrixQueueKeys/") + runtimeId;
    ok = rtdbWrite("PUT", queuePath, queueBody) && ok;
    if (!ok) {
      setLastCloudWriteError("queue_key", queuePath);
      return false;
    }
  }

  runtimeMirrorPublishAtMs = nowTick;
  clearLastCloudWriteError();
  return ok;
}

static bool buildCloudPublishContext(const LoRaFrame& rx, CloudPublishContext& ctx) {
  if (!scopeMatchesBinding(rx.scopeId)) return false;
  ctx.nowSec = unixNowSec();
  ctx.nowMs = unixNowMs(ctx.nowSec);
  ctx.matrixId = matrixCloudId();
  ctx.deviceId = sanitizeRtdbKey(String(rx.deviceId));
  ctx.propertyId = sanitizeRtdbKey(String(bindingPropertyId));
  ctx.propertyScopeId = String(bindingPropertyScopeId);
  return !ctx.deviceId.isEmpty() && !ctx.propertyId.isEmpty() &&
         rtcmd::isValidScopeId(ctx.propertyScopeId.c_str());
}

static void populateCommonCloudFields(
    JsonObject payload,
    const CloudPublishContext& ctx,
    const LoRaFrame& rx) {
  payload["seq"] = rx.seq;
  payload["sourceTimestampSec"] = rx.timestamp;
  payload["receivedAt"] = ctx.nowSec;
  payload["receivedAtMs"] = ctx.nowMs;
  payload["gatewayId"] = ctx.matrixId;
  payload["gatewayRole"] = "matrix";
  payload["gatewayWifiOtaEnabled"] = wifiOtaEnabled;
  payload["propertyId"] = ctx.propertyId;
  payload["propertyScopeId"] = ctx.propertyScopeId;
  payload["matrixGatewayId"] = bindingMatrixGatewayId;
  payload["scope_id"] = ctx.propertyScopeId;
  payload["transport"] = "lora";
  payload["writer"] = "gateway_matrix";
  payload["matrixId"] = ctx.matrixId;
  payload["writerKey"] = cfg::RTDB_WRITER_KEY;
  payload["retentionDays"] = cfg::TELEMETRY_RETENTION_DAYS;
  payload["expiresAt"] =
      ctx.nowSec + (uint32_t)cfg::TELEMETRY_RETENTION_DAYS * 24UL * 60UL * 60UL;
}

static bool publishCloudLatestAndHistory(
    const char* latestRoot,
    const char* historyRoot,
    const CloudPublishContext& ctx,
    const String& historyDayKey,
    const String& body,
    const char* logLabel,
    uint32_t entrySeq,
    TelemetryPublishTrace* trace = nullptr) {
  const uint32_t startedAtMs = millis();
  const String latestPath =
      String(latestRoot) + "/" + ctx.propertyId + "/" + ctx.deviceId;
  char historyEntryId[40];
  snprintf(historyEntryId, sizeof(historyEntryId), "%llu_%lu",
           (unsigned long long)ctx.nowMs, (unsigned long)entrySeq);
  const String historyPath =
      String(historyRoot) + "/" + ctx.propertyId + "/" + ctx.deviceId + "/" +
      historyDayKey + "/" + String(historyEntryId);

  if (trace) {
    trace->attempted = true;
  }

  const bool latestOk = rtdbWrite("PUT", latestPath, body, trace ? &trace->latest : nullptr);
  if (trace) {
    trace->latestOk = latestOk;
    if (latestOk) {
      LOGI(
          "CLOUD_TX_STEP kind=%s step=latest ok=1 code=%d ms=%lu device=%s seq=%lu",
          logLabel,
          trace->latest.httpStatus,
          (unsigned long)trace->latest.elapsedMs,
          ctx.deviceId.c_str(),
          (unsigned long)entrySeq);
    } else {
      LOGW(
          "CLOUD_TX_STEP kind=%s step=latest ok=0 stage=%s code=%d ms=%lu detail=%s device=%s seq=%lu",
          logLabel,
          trace->latest.stage,
          trace->latest.httpStatus,
          (unsigned long)trace->latest.elapsedMs,
          trace->latest.detail,
          ctx.deviceId.c_str(),
          (unsigned long)entrySeq);
    }
  }

  const bool historyOk = rtdbWrite("PUT", historyPath, body, trace ? &trace->history : nullptr);
  if (trace) {
    trace->historyOk = historyOk;
    trace->totalElapsedMs = (uint32_t)(millis() - startedAtMs);
    if (historyOk) {
      LOGI(
          "CLOUD_TX_STEP kind=%s step=history ok=1 code=%d ms=%lu device=%s seq=%lu",
          logLabel,
          trace->history.httpStatus,
          (unsigned long)trace->history.elapsedMs,
          ctx.deviceId.c_str(),
          (unsigned long)entrySeq);
    } else {
      LOGW(
          "CLOUD_TX_STEP kind=%s step=history ok=0 stage=%s code=%d ms=%lu detail=%s device=%s seq=%lu",
          logLabel,
          trace->history.stage,
          trace->history.httpStatus,
          (unsigned long)trace->history.elapsedMs,
          trace->history.detail,
          ctx.deviceId.c_str(),
          (unsigned long)entrySeq);
    }
  }
  if (latestOk && historyOk) {
    cloudLastPublishAtMs = millis();
  } else {
    LOGW("Falha upload cloud %s device=%s latest=%d history=%d",
         logLabel, ctx.deviceId.c_str(), latestOk ? 1 : 0, historyOk ? 1 : 0);
  }
  return latestOk && historyOk;
}

static bool ensureCloudBackhaulConnected() {
  if (!cfg::FEATURE_BACKHAUL) return false;
  if (!cloudTelemetryConfigured()) return false;
  if (WiFi.status() == WL_CONNECTED) {
    cloudBackhaulConnecting = false;
    cloudBackhaulConnectStartedAtMs = 0;
    cloudBackhaulLastDisconnectReason = WIFI_REASON_UNSPECIFIED;
    updateBackhaulDiagState(millis());
    return true;
  }

  const uint32_t now = millis();
  if (cloudBackhaulConnecting) {
    if (cloudBackhaulConnectStartedAtMs != 0 &&
        (uint32_t)(now - cloudBackhaulConnectStartedAtMs) <
            cfg::CLOUD_BACKHAUL_CONNECT_TIMEOUT_MS) {
      return false;
    }
    LOGW(
        "Backhaul Wi-Fi: tentativa expirou sem IP ssid=%s wl=%s(%d) ultimo_motivo=%s(%u); reiniciando STA",
        cfg::BACKHAUL_WIFI_SSID,
        wifiStatusLabel(WiFi.status()),
        (int)WiFi.status(),
        wifiDisconnectReasonLabel(cloudBackhaulLastDisconnectReason),
        (unsigned)cloudBackhaulLastDisconnectReason);
    logBackhaulScanDiagnostics(now);
    updateBackhaulDiagState(now, true, true);
    cloudBackhaulConnecting = false;
    cloudBackhaulConnectStartedAtMs = 0;
    WiFi.disconnect(false, false);
    LOGI("Backhaul retry agendado em %lu ms", (unsigned long)cfg::CLOUD_BACKHAUL_RETRY_MS);
  }
  if (cloudBackhaulAttemptAtMs != 0 &&
      (uint32_t)(now - cloudBackhaulAttemptAtMs) < cfg::CLOUD_BACKHAUL_RETRY_MS) {
    updateBackhaulDiagState(now);
    return false;
  }
  cloudBackhaulAttemptAtMs = now;
  backhaulDiag.attemptCount++;
  // Em modo OTA/manual, preserva AP local e sobe STA para backhaul cloud.
  const wifi_mode_t desiredMode =
      (cfg::FEATURE_WIFI_AP && wifiOtaEnabled) ? WIFI_AP_STA : WIFI_STA;
  if (WiFi.getMode() != desiredMode) {
    WiFi.mode(desiredMode);
  }
  WiFi.setSleep(false);
  cloudBackhaulConnecting = true;
  cloudBackhaulConnectStartedAtMs = now;
  cloudBackhaulLastDisconnectReason = WIFI_REASON_UNSPECIFIED;
  backhaulDiag.associated = false;
  WiFi.begin(cfg::BACKHAUL_WIFI_SSID, cfg::BACKHAUL_WIFI_PASS);
  LOGI("Backhaul Wi-Fi: tentando conectar em %s", cfg::BACKHAUL_WIFI_SSID);
  updateBackhaulDiagState(now, false, true);
  return false;
}

static void publishTelemetryToCloud(const LoRaFrame& rx) {
  if (rx.msgType != MsgType::TELEMETRY) return;
  if (!cloudPublishReady()) {
    LOGW(
        "CLOUD_TX_SKIP reason=cloud_not_ready device=%lu seq=%lu",
        (unsigned long)rx.deviceId,
        (unsigned long)rx.seq);
    return;
  }

  StaticJsonDocument<256> telemetry;
  if (deserializeJson(telemetry, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    LOGW(
        "CLOUD_TX_SKIP reason=invalid_json device=%lu seq=%lu",
        (unsigned long)rx.deviceId,
        (unsigned long)rx.seq);
    return;
  }

  const JsonVariantConst latField =
      telemetry["lat"].isNull() ? telemetry["la"] : telemetry["lat"];
  const JsonVariantConst lonField =
      telemetry["lon"].isNull() ? telemetry["lo"] : telemetry["lon"];
  const float lat = latField | NAN;
  const float lon = lonField | NAN;
  if (!isfinite(lat) || !isfinite(lon) ||
      lat < -90.0f || lat > 90.0f || lon < -180.0f || lon > 180.0f) {
    LOGW(
        "CLOUD_TX_SKIP reason=invalid_coordinates device=%lu seq=%lu",
        (unsigned long)rx.deviceId,
        (unsigned long)rx.seq);
    return;
  }

  CloudPublishContext ctx;
  if (!buildCloudPublishContext(rx, ctx)) {
    if (scopeMatchesBinding(rx.scopeId)) {
      LOGW(
          "CLOUD_TX_SKIP reason=context_not_ready device=%lu seq=%lu",
          (unsigned long)rx.deviceId,
          (unsigned long)rx.seq);
    }
    return;
  }

  LOGI(
      "CLOUD_TX_BEGIN kind=telemetry device=%s seq=%lu scope=%s lat=%.6f lon=%.6f",
      ctx.deviceId.c_str(),
      (unsigned long)rx.seq,
      ctx.propertyScopeId.c_str(),
      lat,
      lon);

  StaticJsonDocument<512> payload;
  payload["deviceId"] = ctx.deviceId;
  payload["lat"] = lat;
  payload["lon"] = lon;
  payload["mode"] =
      telemetry["mode"].isNull() ? (telemetry["m"] | 0) : (telemetry["mode"] | 0);
  payload["spd"] =
      telemetry["spd"].isNull() ? (telemetry["sp"] | 0.0f) : (telemetry["spd"] | 0.0f);
  payload["hdop"] =
      telemetry["hdop"].isNull() ? (telemetry["hd"] | 99.9f) : (telemetry["hdop"] | 99.9f);
  payload["sat"] =
      telemetry["sat"].isNull() ? (telemetry["sa"] | 0) : (telemetry["sat"] | 0);
  payload["rssi"] = telemetry["rssi"] | 0;
  payload["snr"] = telemetry["snr"] | 0.0f;
  populateCommonCloudFields(payload.as<JsonObject>(), ctx, rx);

  String body;
  serializeJson(payload, body);
  TelemetryPublishTrace trace;
  const bool ok = publishCloudLatestAndHistory(
      "propertyTelemetryLatest", "propertyTelemetryHistory", ctx, utcDayKey(ctx.nowSec), body,
      "telemetry", rx.seq, &trace);
  if (ok) {
    LOGI(
        "CLOUD_TX_DONE kind=telemetry device=%s seq=%lu latest=1 history=1 total_ms=%lu",
        ctx.deviceId.c_str(),
        (unsigned long)rx.seq,
        (unsigned long)trace.totalElapsedMs);
  } else if (trace.latestOk || trace.historyOk) {
    LOGW(
        "CLOUD_TX_PARTIAL kind=telemetry device=%s seq=%lu latest=%d history=%d total_ms=%lu",
        ctx.deviceId.c_str(),
        (unsigned long)rx.seq,
        trace.latestOk ? 1 : 0,
        trace.historyOk ? 1 : 0,
        (unsigned long)trace.totalElapsedMs);
  } else {
    LOGE(
        "CLOUD_TX_FAIL kind=telemetry device=%s seq=%lu latest=0 history=0 total_ms=%lu",
        ctx.deviceId.c_str(),
        (unsigned long)rx.seq,
        (unsigned long)trace.totalElapsedMs);
  }
}

static bool isDailyHealthEvent(const JsonVariantConst payload) {
  if (!payload.is<JsonObjectConst>()) return false;
  const char* type = payload["type"] | "";
  if (strcmp(type, "health_daily") == 0) return true;
  const char* eventType = payload["event_type"] | "";
  return strcmp(eventType, "health_daily") == 0;
}

static void publishDailyHealthToCloud(const LoRaFrame& rx) {
  if (rx.msgType != MsgType::EVENT) return;
  if (!cloudPublishReady()) return;

  StaticJsonDocument<256> eventPayload;
  if (deserializeJson(eventPayload, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return;
  }
  if (!isDailyHealthEvent(eventPayload.as<JsonVariantConst>())) return;

  CloudPublishContext ctx;
  if (!buildCloudPublishContext(rx, ctx)) return;

  const uint32_t gpsDayKey = eventPayload["dk"] | 0UL;

  StaticJsonDocument<512> payload;
  payload["deviceId"] = ctx.deviceId;
  payload["kind"] = "health_daily";
  payload["healthFlags"] = eventPayload["hf"] | 0;
  payload["gpsDayKey"] = gpsDayKey;
  payload["uptimeSec"] = eventPayload["up"] | 0UL;
  payload["temperatureDeciC"] = eventPayload["tp"] | 0;
  payload["sat"] = eventPayload["sa"] | 0;
  payload["hdopCenti"] = eventPayload["hd"] | 0;
  payload["i2cDevices"] = eventPayload["i2"] | 0;
  populateCommonCloudFields(payload.as<JsonObject>(), ctx, rx);

  String body;
  serializeJson(payload, body);
  const String historyDayKey =
      gpsDayKey > 0 ? String(gpsDayKey) : utcDayKey(ctx.nowSec);
  publishCloudLatestAndHistory(
      "propertyHealthLatest", "propertyHealthHistory", ctx, historyDayKey, body, "health_daily",
      rx.seq);
}

static void publishEventToCloud(const LoRaFrame& rx) {
  if (rx.msgType != MsgType::EVENT) return;
  if (!cloudPublishReady()) return;

  DynamicJsonDocument eventPayload(768);
  if (deserializeJson(eventPayload, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return;
  }

  CloudPublishContext ctx;
  if (!buildCloudPublishContext(rx, ctx)) return;

  DynamicJsonDocument payload(1024);
  payload["deviceId"] = ctx.deviceId;
  const char* eventType = pickFirstText(eventPayload["event_type"], eventPayload["type"]);
  if (!eventType[0]) eventType = "event";
  payload["eventType"] = eventType;
  payload["type"] = eventType;
  const char* polygonStatus = eventPayload["status"] | "";
  if (polygonStatus[0] != '\0') payload["status"] = polygonStatus;
  const char* polygonKind = pickFirstText(
      eventPayload["polygon_kind"], eventPayload["polygonKind"]);
  if (polygonKind[0] != '\0') payload["polygonKind"] = polygonKind;
  const char* originDocType = pickFirstText(
      eventPayload["origin_doc_type"], eventPayload["originDocType"]);
  if (originDocType[0] != '\0') payload["originDocType"] = originDocType;
  const char* originDocId = pickFirstText(
      eventPayload["origin_doc_id"], eventPayload["originDocId"]);
  if (originDocId[0] != '\0') payload["originDocId"] = originDocId;

  if (strcmp(eventType, "polygon_apply_result") == 0) {
    const char* cmdId = eventPayload["cmd_id"] | eventPayload["commandId"] | "";
    const bool applyOk = strcmp(polygonStatus, "success") == 0;
    if (applyOk) {
      const int pts = eventPayload["point_count"] | 0;
      AS_MATRIX_COLLAR_APPLY_SUCCESS(
          cmdId, rx.deviceId, originDocId, originDocType, originDocId, pts);
    } else {
      const char* errCode = eventPayload["error_code"] | "";
      const char* errStage = eventPayload["error_stage"] | "";
      AS_MATRIX_COLLAR_APPLY_FAILURE(cmdId, rx.deviceId, errCode, errStage);
    }
  }
  if (eventPayload["operation_id"].is<const char*>()) {
    payload["operationId"] = eventPayload["operation_id"].as<const char*>();
  }
  if (eventPayload["cmd_id"].is<const char*>()) {
    payload["cmd_id"] = eventPayload["cmd_id"].as<const char*>();
  }
  if (!eventPayload["point_count"].isNull()) {
    payload["pointCount"] = eventPayload["point_count"];
  }
  if (!eventPayload["phase_count"].isNull()) {
    payload["phaseCount"] = eventPayload["phase_count"];
  }
  const char* errorCode = eventPayload["error_code"] | "";
  if (errorCode[0] != '\0') payload["errorCode"] = errorCode;
  const char* errorStage = eventPayload["error_stage"] | "";
  if (errorStage[0] != '\0') payload["errorStage"] = errorStage;
  payload["payload"] = eventPayload.as<JsonVariantConst>();
  populateCommonCloudFields(payload.as<JsonObject>(), ctx, rx);

  String body;
  serializeJson(payload, body);
  char entryId[40];
  snprintf(entryId, sizeof(entryId), "%llu_%lu",
           (unsigned long long)ctx.nowMs, (unsigned long)rx.seq);
  const String eventPath =
      String("propertyEvents/") + ctx.propertyId + "/" + utcDayKey(ctx.nowSec) +
      "/" + String(entryId);
  if (!rtdbWrite("PUT", eventPath, body)) {
    LOGW("Falha upload cloud event device=%s type=%s",
         ctx.deviceId.c_str(), eventType);
  }
}

static void clearActiveSimpleCommand() {
  if (activeSimpleCommand.active) {
    AS_MATRIX_SIMPLE_COMMAND_CLEARED(
        activeSimpleCommand.commandId[0] ? activeSimpleCommand.commandId : "-",
        activeSimpleCommand.command[0] ? activeSimpleCommand.command : "-",
        activeSimpleCommand.lastReasonCode != rpv2::REASON_NONE
            ? rpv2::reasonCodeLabel(activeSimpleCommand.lastReasonCode)
            : "cleared");
  }
  if (deferredUplinkQueueCount > 0 && deferredUplinkFlushAtMs == 0) {
    deferredUplinkFlushAtMs = millis() + cfg::SIMPLE_COMMAND_ACK_POST_FLUSH_DELAY_MS;
  }
  for (uint8_t i = 0; i < kMaxPendingWakeSessions; ++i) {
    pendingWakeSessions[i] = PendingWakeSession{};
  }
  activeSimpleCommand = ActiveSimpleCommandState{};
  simpleAckWaitActive = false;
  simpleAckWaitDeviceId = 0;
  simpleAckWaitDeadlineAtMs = 0;
  simpleAckWaitCommandId[0] = '\0';
}

static void noteSetFenceCommandProgress(const char* stage) {
  if (!activeSimpleCommand.active) return;
  if (strcmp(activeSimpleCommand.command, "SET_FENCE") != 0) return;
  activeSimpleCommand.lastProgressAtMs = millis();
  if (stage && stage[0]) {
    LOGI(
        "SET_FENCE_PROGRESS commandId=%s stage=%s atMs=%lu",
        activeSimpleCommand.commandId[0] ? activeSimpleCommand.commandId : "-",
        stage,
        (unsigned long)activeSimpleCommand.lastProgressAtMs);
  }
}

static bool targetStateMatchesDeviceId(
    const ActiveSimpleCommandTargetState& target,
    uint32_t deviceId) {
  if (!target.targetId[0] || deviceId == 0) return false;
  char expected[32]{};
  snprintf(expected, sizeof(expected), "%lu", (unsigned long)deviceId);
  return strcmp(target.targetId, expected) == 0;
}

static bool isHealthDailyEvent(const LoRaFrame& rx) {
  if (rx.msgType != MsgType::EVENT || rx.payloadLen == 0) return false;
  StaticJsonDocument<256> payload;
  if (deserializeJson(payload, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return false;
  }
  const char* eventType = pickFirstText(payload["event_type"], payload["type"]);
  return strcmp(eventType, "health_daily") == 0;
}

static void scheduleActiveSimpleCommandRetryForRx(const LoRaFrame& rx) {
  if (!activeSimpleCommand.active || activeSimpleCommand.targetCount == 0) return;
  if (strcmp(activeSimpleCommand.command, "SET_FENCE") == 0 && hasPendingWakeSessions()) {
    return;
  }
  bool matchesTarget = false;
  for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
    if (targetStateMatchesDeviceId(activeSimpleCommand.targets[i], rx.deviceId)) {
      matchesTarget = true;
      break;
    }
  }
  if (!matchesTarget) return;

  activeSimpleCommand.sawTargetUplinkSinceDispatch = true;

  const bool telemetryTrigger = rx.msgType == MsgType::TELEMETRY;
  const bool healthTrigger = isHealthDailyEvent(rx);
  if (!telemetryTrigger && !healthTrigger) return;

  uint32_t delayMs = telemetryTrigger
      ? cfg::SIMPLE_COMMAND_TELEMETRY_TRIGGER_DELAY_MS
      : cfg::SIMPLE_COMMAND_HEALTH_TRIGGER_DELAY_MS;
  activeSimpleCommand.targetedRetryPending = true;
  activeSimpleCommand.targetedRetryAtMs = millis() + delayMs;
  activeSimpleCommand.targetedRetryDeviceId = rx.deviceId;
}

static int findActiveSimpleCommandTarget(const char* targetId) {
  if (!targetId || !targetId[0]) return -1;
  for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
    if (strcmp(activeSimpleCommand.targets[i].targetId, targetId) == 0) return (int)i;
  }
  return -1;
}

static bool allActiveSimpleTargetsTerminal() {
  if (!activeSimpleCommand.active || activeSimpleCommand.targetCount == 0) return false;
  for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
    if (!activeSimpleCommand.targets[i].terminal) return false;
  }
  return true;
}

static bool anyActiveSimpleTargetFailed() {
  for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
    if (activeSimpleCommand.targets[i].terminal && !activeSimpleCommand.targets[i].ok) {
      return true;
    }
  }
  return false;
}

static const char* firstActiveSimpleTargetFailureReason() {
  for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
    const ActiveSimpleCommandTargetState& target = activeSimpleCommand.targets[i];
    if (!target.terminal || target.ok) continue;
    if (target.reason[0]) return target.reason;
  }
  return nullptr;
}

static bool publishSimpleCommandResult(const char* status, const char* reason) {
  if (!cfg::FEATURE_CLOUD) return false;
  if (!activeSimpleCommand.active || !activeSimpleCommand.commandId[0]) return false;

  DynamicJsonDocument doc(2048);
  doc["commandId"] = activeSimpleCommand.commandId;
  doc["command"] = activeSimpleCommand.command;
  doc["status"] = status;
  doc["transport"] =
      strcmp(activeSimpleCommand.command, "SET_FENCE") == 0 ? "radio_fence_v2" : "lora";
  doc["transportState"] = status;
  doc["createdAtMs"] = activeSimpleCommand.createdAtMs;
  doc["updatedAtMs"] = unixNowMs(unixNowSec());
  doc["expiresAtMs"] = activeSimpleCommand.expiresAtMs;
  doc["propertyId"] = activeSimpleCommand.propertyId;
  doc["propertyScopeId"] = activeSimpleCommand.propertyScopeId;
  doc["matrixId"] = matrixCloudId();
  doc["matrixGatewayId"] = activeSimpleCommand.matrixGatewayId;
  doc["matrixRuntimeId"] = matrixCloudId();
  doc["requestedByUid"] = activeSimpleCommand.requestedByUid;
  doc["requestedByRole"] = activeSimpleCommand.requestedByRole;
  doc["writer"] = "gateway_matrix";
  doc["writerKey"] = cfg::RTDB_WRITER_KEY;
  if (activeSimpleCommand.polygonKind[0] != '\0') {
    doc["polygonKind"] = activeSimpleCommand.polygonKind;
  }
  if (activeSimpleCommand.originDocType[0] != '\0') {
    doc["originDocType"] = activeSimpleCommand.originDocType;
  }
  if (activeSimpleCommand.originDocId[0] != '\0') {
    doc["originDocId"] = activeSimpleCommand.originDocId;
  }
  copyTargetDeviceIdsFromActiveCommand(doc.as<JsonObject>());
  if (reason && reason[0]) doc["reason"] = reason;
  if (activeSimpleCommand.lastReasonCode != rpv2::REASON_NONE) {
    doc["reasonCode"] = activeSimpleCommand.lastReasonCode;
  }

  JsonObject deviceResults = doc["deviceResults"].to<JsonObject>();
  for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
    const ActiveSimpleCommandTargetState& target = activeSimpleCommand.targets[i];
    JsonObject item = deviceResults.createNestedObject(target.targetId);
    item["ok"] = target.ok;
    item["status"] = target.status[0] ? target.status : (target.terminal ? "completed" : "dispatching");
    if (target.reason[0]) item["reason"] = target.reason;
    if (activeSimpleCommand.lastReasonCode != rpv2::REASON_NONE) {
      item["reasonCode"] = activeSimpleCommand.lastReasonCode;
    }
  }

  String body;
  serializeJson(doc, body);
  const bool matrixOk = rtdbWrite(
      "PUT",
      String("matrixCommandResults/") + matrixCloudId() + "/" + activeSimpleCommand.commandId,
      body);
  const bool propertyOk = rtdbWrite(
      "PUT",
      String("propertyCommands/") + sanitizeRtdbKey(String(activeSimpleCommand.propertyId)) +
          "/" + activeSimpleCommand.commandId,
      body);
  const bool eventOk = appendPropertyCommandEvent(
      activeSimpleCommand.propertyId,
      activeSimpleCommand.commandId,
      status,
      reason,
      &doc);
  copyStringToBuffer(
      activeSimpleCommand.transportState,
      sizeof(activeSimpleCommand.transportState),
      status);
  if (!(matrixOk && propertyOk && eventOk)) {
    setLastCloudWriteError("command_status", activeSimpleCommand.commandId);
  }
  return matrixOk && propertyOk && eventOk;
}

static void markActiveSimpleCommandTarget(
    const char* targetId,
    bool ok,
    const char* status,
    const char* reason) {
  const int idx = findActiveSimpleCommandTarget(targetId);
  if (idx < 0) return;

  ActiveSimpleCommandTargetState& target = activeSimpleCommand.targets[idx];
  target.terminal = true;
  target.ok = ok;
  copyStringToBuffer(target.status, sizeof(target.status), status ? status : (ok ? "completed" : "failed"));
  copyStringToBuffer(target.reason, sizeof(target.reason), reason ? reason : "");
}

static bool cacheActiveSimpleCommandPayload(
    const JsonVariantConst payload,
    const char** reason) {
  const size_t bytes = measureJson(payload);
  if (bytes == 0 || bytes >= sizeof(activeSimpleCommand.payloadJson)) {
    if (reason) *reason = "payload_cache_too_large";
    return false;
  }
  const size_t written =
      serializeJson(payload, activeSimpleCommand.payloadJson, sizeof(activeSimpleCommand.payloadJson));
  if (written != bytes) {
    activeSimpleCommand.payloadJson[0] = '\0';
    if (reason) *reason = "payload_cache_failed";
    return false;
  }
  return true;
}

static bool resendActiveSimpleCommand(
    const LoRaFrame* triggerRx,
    const char** reason) {
  if (!activeSimpleCommand.active || !activeSimpleCommand.commandId[0]) return false;
  if (strcmp(activeSimpleCommand.command, "SET_FENCE") == 0 && hasPendingWakeSessions()) {
    if (reason) *reason = "wake_session_pending";
    return false;
  }
  if (!activeSimpleCommand.payloadJson[0]) {
    if (reason) *reason = "missing_cached_payload";
    return false;
  }

  const uint32_t nowTick = millis();
  const uint32_t minGap =
      triggerRx ? cfg::SIMPLE_COMMAND_RX_TRIGGER_MIN_GAP_MS : cfg::SIMPLE_COMMAND_RETRY_MS;
  if (activeSimpleCommand.lastAttemptAtMs != 0 &&
      (uint32_t)(nowTick - activeSimpleCommand.lastAttemptAtMs) < minGap) {
    return false;
  }

  DynamicJsonDocument payloadDoc(8192);
  if (deserializeJson(payloadDoc, activeSimpleCommand.payloadJson) != DeserializationError::Ok) {
    if (reason) *reason = "cached_payload_invalid_json";
    return false;
  }

  bool sentAny = false;
  const bool targetedRetry = triggerRx != nullptr && triggerRx->deviceId != 0;
  for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
    ActiveSimpleCommandTargetState& target = activeSimpleCommand.targets[i];
    if (target.terminal) continue;
    if (targetedRetry && !targetStateMatchesDeviceId(target, triggerRx->deviceId)) continue;

    const uint32_t deviceId = (uint32_t)strtoul(target.targetId, nullptr, 10);
    bool ok = false;
    const char* sendReason = nullptr;
    if (strcmp(activeSimpleCommand.command, "SET_FENCE") == 0) {
      ok = sendFenceCommandChunked(deviceId, payloadDoc.as<JsonVariantConst>(), &sendReason);
    } else {
      const MsgType msgType =
          strcmp(activeSimpleCommand.command, "SET_PARAMS") == 0
              ? MsgType::SET_PARAMS
              : MsgType::PING;
      ok = sendLoRaJsonFrame(
          deviceId,
          msgType,
          payloadDoc.as<JsonVariantConst>(),
          &sendReason,
          MatrixLoRaTxReason::CommandDispatch,
          "resendActiveSimpleCommand",
          triggerRx,
          activeSimpleCommand.commandId);
    }
    if (ok) {
      copyStringToBuffer(target.status, sizeof(target.status), "dispatching");
      target.reason[0] = '\0';
      sentAny = true;
    } else if (sendReason && sendReason[0]) {
      copyStringToBuffer(target.reason, sizeof(target.reason), sendReason);
    }
  }

  if (!sentAny) {
    if (reason && !*reason) *reason = targetedRetry ? "target_not_ready" : "lora_send_failed";
    return false;
  }

  activeSimpleCommand.lastAttemptAtMs = nowTick;
  activeSimpleCommand.targetedRetryPending = false;
  activeSimpleCommand.targetedRetryAtMs = 0;
  activeSimpleCommand.targetedRetryDeviceId = 0;
  if (activeSimpleCommand.retryCount < 0xFFFF) activeSimpleCommand.retryCount++;
  publishSimpleCommandResult("dispatching", nullptr);
  return true;
}

static void processScheduledActiveSimpleCommandRetry() {
  if (!activeSimpleCommand.active || !activeSimpleCommand.targetedRetryPending) return;
  if (strcmp(activeSimpleCommand.command, "SET_FENCE") == 0 && hasPendingWakeSessions()) return;
  const uint32_t nowTick = millis();
  if ((int32_t)(nowTick - activeSimpleCommand.targetedRetryAtMs) < 0) return;
  if (lora.lastRawRxAtMs() != 0 &&
      (uint32_t)(nowTick - lora.lastRawRxAtMs()) < cfg::SIMPLE_COMMAND_RAW_RX_HOLDOFF_MS) {
    return;
  }

  LoRaFrame trigger;
  trigger.deviceId = activeSimpleCommand.targetedRetryDeviceId;
  resendActiveSimpleCommand(&trigger, nullptr);
}

static bool publishImmediateMatrixCommandResult(
    const char* commandId,
    const char* command,
    const char* propertyId,
    const char* propertyScopeId,
    const char* matrixGatewayId,
    const char* requestedByUid,
    const char* requestedByRole,
    uint64_t createdAtMs,
    uint64_t expiresAtMs,
    const char* status,
    const char* reason,
    const JsonVariantConst payload = JsonVariantConst(),
    const JsonArrayConst targetDeviceIds = JsonArrayConst(),
    const JsonArrayConst targetGatewayIds = JsonArrayConst()) {
  if (!cfg::FEATURE_CLOUD) return false;
  if (!commandId || !commandId[0]) return false;
  DynamicJsonDocument doc(2048);
  doc["commandId"] = commandId;
  if (command && command[0]) doc["command"] = command;
  doc["status"] = status;
  doc["createdAtMs"] = createdAtMs;
  doc["updatedAtMs"] = unixNowMs(unixNowSec());
  doc["expiresAtMs"] = expiresAtMs;
  doc["propertyId"] = propertyId ? propertyId : "";
  doc["propertyScopeId"] = propertyScopeId ? propertyScopeId : "";
  doc["matrixId"] = matrixCloudId();
  doc["matrixGatewayId"] = matrixGatewayId ? matrixGatewayId : "";
  doc["matrixRuntimeId"] = matrixCloudId();
  if (requestedByUid && requestedByUid[0]) doc["requestedByUid"] = requestedByUid;
  if (requestedByRole && requestedByRole[0]) doc["requestedByRole"] = requestedByRole;
  doc["writer"] = "gateway_matrix";
  doc["writerKey"] = cfg::RTDB_WRITER_KEY;
  if (!payload.isNull()) {
    copyAuditMetadataFromPayload(doc.as<JsonObject>(), payload);
  }
  if (!targetDeviceIds.isNull()) {
    doc["targetDeviceIds"] = targetDeviceIds;
  }
  if (!targetGatewayIds.isNull()) {
    doc["targetGatewayIds"] = targetGatewayIds;
  }
  if (reason && reason[0]) doc["reason"] = reason;

  String body;
  serializeJson(doc, body);
  const bool matrixOk = rtdbWrite(
      "PUT",
      String("matrixCommandResults/") + matrixCloudId() + "/" + commandId,
      body);
  const bool propertyOk = rtdbWrite(
      "PUT",
      String("propertyCommands/") + sanitizeRtdbKey(String(propertyId ? propertyId : "")) +
          "/" + commandId,
      body);
  const bool eventOk = appendPropertyCommandEvent(
      propertyId,
      commandId,
      status,
      reason,
      &doc);
  if (!(matrixOk && propertyOk && eventOk)) {
    setLastCloudWriteError("command_status", String(commandId));
  }
  return matrixOk && propertyOk && eventOk;
}

static bool setupWiFi() {
  if (!cfg::FEATURE_WIFI_AP) return false;
  WiFi.mode(cfg::FEATURE_BACKHAUL ? WIFI_AP_STA : WIFI_AP);
  WiFi.setSleep(false);
  const String apSsid = gatewayApSsid();
  const bool apOk = WiFi.softAP(apSsid.c_str(), cfg::AP_PASS);
  if (!apOk) {
    wifiApRunning = false;
    WiFi.mode(WIFI_OFF);
    LOGE("Falha ao subir AP.");
    return false;
  }
  wifiApRunning = true;
  wifiRecoveryAttemptCount = 0;
  LOGI("AP ativo: %s", apSsid.c_str());
  return true;
}

static void setupOta() {
  if (!wifiOtaEnabled || !cfg::FEATURE_OTA || !cfg::OTA_ENABLED) return;
  ArduinoOTA.setHostname(cfg::OTA_HOSTNAME);
  ArduinoOTA.setPort(3232);
  ArduinoOTA.setTimeout(cfg::OTA_HANDSHAKE_TIMEOUT_MS);
  ArduinoOTA.setPassword(cfg::OTA_PASSWORD);
  ArduinoOTA.onStart([]() {
    otaUploadInProgress = true;
    setWatchdogEnabled(false);
    LOGI("OTA iniciado");
  });
  ArduinoOTA.onEnd([]() {
    otaUploadInProgress = false;
    if (wifiOtaEnabled) setWatchdogEnabled(true);
    LOGI("OTA concluido");
  });
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    static uint8_t lastStep = 0xFF;
    const uint8_t pct = (uint8_t)((progress * 100U) / total);
    const uint8_t step = pct / 10U;
    if (step != lastStep || pct == 100U) {
      lastStep = step;
      LOGI("OTA progresso: %u%%", pct);
    }
  });
  ArduinoOTA.onError([](ota_error_t error) {
    otaUploadInProgress = false;
    if (wifiOtaEnabled) setWatchdogEnabled(true);
    LOGE("OTA erro=%u (%s)", (unsigned int)error, otaErrorText(error));
    logOtaPartitionInfo("erro");
  });
  ArduinoOTA.begin();
  logOtaPartitionInfo("inicio");
  LOGI("OTA ativo hostname=%s", cfg::OTA_HOSTNAME);
}

static void stopWifiAndOta() {
  wifiApRunning = false;
  wifiRecoveryAttemptCount = 0;
  wifiRecoveryAttemptAtMs = 0;
  cloudBackhaulAttemptAtMs = 0;
  cloudBackhaulConnecting = false;
  cloudBackhaulConnectStartedAtMs = 0;
  if (WiFi.getMode() == WIFI_STA || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.disconnect(true, true);
  }
  if (WiFi.getMode() == WIFI_AP || WiFi.getMode() == WIFI_AP_STA) {
    WiFi.softAPdisconnect(true);
  }
  WiFi.mode(WIFI_OFF);
  backhaulDiag.associated = false;
  updateBackhaulDiagState(millis(), false, true);
  LOGI("Gateway matriz em modo LoRa-only");
}

static void onWifiEvent(WiFiEvent_t event, WiFiEventInfo_t info) {
#if defined(ARDUINO_EVENT_WIFI_AP_START)
  if (event == ARDUINO_EVENT_WIFI_AP_START) {
    wifiApRunning = true;
    LOGI("WiFi AP iniciado");
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_AP_STOP)
  if (event == ARDUINO_EVENT_WIFI_AP_STOP) {
    wifiApRunning = false;
    wifiRecoveryAttemptAtMs = 0;
    LOGW("WiFi AP parou");
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_AP_STACONNECTED)
  if (event == ARDUINO_EVENT_WIFI_AP_STACONNECTED) {
    LOGI("Cliente conectado no AP (n=%d)", WiFi.softAPgetStationNum());
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_AP_STADISCONNECTED)
  if (event == ARDUINO_EVENT_WIFI_AP_STADISCONNECTED) {
    LOGI("Cliente desconectado do AP (n=%d)", WiFi.softAPgetStationNum());
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_STA_GOT_IP)
  if (event == ARDUINO_EVENT_WIFI_STA_GOT_IP) {
    cloudBackhaulConnecting = false;
    cloudBackhaulConnectStartedAtMs = 0;
    cloudBackhaulAttemptAtMs = 0;
    cloudBackhaulLastDisconnectReason = WIFI_REASON_UNSPECIFIED;
    backhaulDiag.associated = true;
    LOGI("Backhaul conectado: %s", WiFi.localIP().toString().c_str());
    updateBackhaulDiagState(millis(), false, true);
    logBackhaulConnectedSnapshot();
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_STA_CONNECTED)
  if (event == ARDUINO_EVENT_WIFI_STA_CONNECTED) {
    cloudBackhaulConnecting = true;
    cloudBackhaulConnectStartedAtMs = millis();
    backhaulDiag.associated = true;
    LOGI("Backhaul Wi-Fi associado ao AP");
    updateBackhaulDiagState(millis(), false, true);
  }
#endif
#if defined(ARDUINO_EVENT_WIFI_STA_DISCONNECTED)
  if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
    const uint8_t rawReason = info.wifi_sta_disconnected.reason;
    const wifi_err_reason_t reason =
        rawReason == 0 ? WIFI_REASON_UNSPECIFIED : (wifi_err_reason_t)rawReason;
    cloudBackhaulLastDisconnectReason = reason;
    cloudBackhaulConnecting = false;
    cloudBackhaulConnectStartedAtMs = 0;
    backhaulDiag.associated = false;
    if (cloudTelemetryConfigured() || !wifiOtaEnabled) {
      LOGW(
          "Backhaul desconectado: motivo=%s(%u) wl=%s(%d)",
          wifiDisconnectReasonLabel(reason),
          (unsigned)reason,
          wifiStatusLabel(WiFi.status()),
          (int)WiFi.status());
    }
    updateBackhaulDiagState(millis(), false, true);
  }
#endif
}

static bool wifiApClientConnected() {
  if (!cfg::FEATURE_WIFI_AP || !wifiOtaEnabled || !wifiApRunning) return false;
  const wifi_mode_t mode = WiFi.getMode();
  if (mode != WIFI_AP && mode != WIFI_AP_STA) return false;
  return WiFi.softAPgetStationNum() > 0;
}

static bool shouldBlePresenceBeEnabled() {
  if (!cfg::FEATURE_BLE) return false;
  if (!wifiOtaEnabled) return false;
  if (otaUploadInProgress) return false;
  return true;
}

static uint32_t wifiRecoveryBackoffMs() {
  uint8_t step = wifiRecoveryAttemptCount;
  if (step > 5) step = 5;
  return 1000UL << step;
}

static void ensureWifiOtaServices() {
  if (!cfg::FEATURE_WIFI_AP) return;
  if (!wifiOtaEnabled) return;
  const wifi_mode_t mode = WiFi.getMode();
  if (wifiApRunning && (mode == WIFI_AP || mode == WIFI_AP_STA)) return;
  const uint32_t now = millis();
  const uint32_t backoffMs = wifiRecoveryBackoffMs();
  if (wifiRecoveryAttemptAtMs != 0 &&
      (uint32_t)(now - wifiRecoveryAttemptAtMs) < backoffMs) {
    return;
  }
  wifiRecoveryAttemptAtMs = now;
  LOGW("WiFi/AP inativo, retomando servico (tentativa=%u)", (unsigned)(wifiRecoveryAttemptCount + 1U));
  if (setupWiFi()) {
    setupOta();
    wifiRecoveryAttemptCount = 0;
    return;
  }
  if (wifiRecoveryAttemptCount < 10) wifiRecoveryAttemptCount++;
}

static void setWatchdogEnabled(bool enabled) {
  if (enabled && !watchdogTaskRegistered) {
    const esp_err_t err = esp_task_wdt_add(NULL);
    if (err == ESP_OK) {
      watchdogTaskRegistered = true;
    } else if (err != ESP_ERR_INVALID_STATE) {
      LOGW("TWDT add falhou err=%d", (int)err);
    }
  } else if (!enabled && watchdogTaskRegistered) {
    const esp_err_t err = esp_task_wdt_delete(NULL);
    if (err == ESP_OK || err == ESP_ERR_NOT_FOUND) {
      watchdogTaskRegistered = false;
    } else {
      LOGW("TWDT delete falhou err=%d", (int)err);
    }
  }
}

static void feedWatchdogIfEnabled() {
  if (!watchdogTaskRegistered) return;
  const esp_err_t err = esp_task_wdt_reset();
  if (err == ESP_ERR_NOT_FOUND) {
    watchdogTaskRegistered = false;
    return;
  }
  if (err != ESP_OK) {
    LOGW("TWDT reset falhou err=%d", (int)err);
  }
}

static bool parseWifiOtaParam(const JsonVariantConst payload, bool& outEnabled) {
  if (!payload.is<JsonObjectConst>()) return false;
  const JsonVariantConst v = payload["wifi_ota_enabled"];
  if (!v.is<bool>()) return false;
  outEnabled = v.as<bool>();
  return true;
}

static bool hasAdminModePermission(const JsonVariantConst payload) {
  if (!payload.is<JsonObjectConst>()) return false;
  const JsonVariantConst requestedByAdmin = payload["requested_by_admin"];
  return rtcmd::hasAdminModePermission(
      requestedByAdmin.is<bool>() && requestedByAdmin.as<bool>(),
      payload["requested_by_role"] | "",
      payload["actor_role"] | "");
}

static bool targetIncludesGateway(const JsonVariantConst payload) {
  if (!payload.is<JsonObjectConst>()) return true;
  const char* target = payload["target"] | "all";
  return rtcmd::targetIncludesGateway(target);
}

static bool targetIncludesCollars(const JsonVariantConst payload) {
  if (!payload.is<JsonObjectConst>()) return true;
  const char* target = payload["target"] | "all";
  return rtcmd::targetIncludesCollars(target);
}

static void applyWifiOtaMode(bool enabled, const char* source) {
  if (enabled && !cfg::FEATURE_WIFI_AP) {
    LOGW("SET_PARAMS: WiFi/AP indisponivel neste perfil (%s)", cfg::DIAG_PROFILE_NAME);
    return;
  }
  if (wifiOtaEnabled == enabled) {
    LOGI("SET_PARAMS: wifi_ota_enabled ja estava em %d (%s)", enabled ? 1 : 0, source);
    return;
  }

  wifiOtaEnabled = enabled;
  setWatchdogEnabled(enabled);

  if (enabled) {
    if (setupWiFi()) {
      setupOta();
    } else {
      LOGW("SET_PARAMS: WiFi/AP indisponivel; retry automatico ativo");
    }
    if (cfg::BLE_PRESENCE_ENABLED) {
      blePresence.setEnabled(shouldBlePresenceBeEnabled());
      blePresence.setFlags(true, WiFi.status() == WL_CONNECTED);
    }
    LOGI("SET_PARAMS: wifi_ota_enabled=1 aplicado via %s", source);
  } else {
    if (cfg::BLE_PRESENCE_ENABLED) {
      blePresence.setFlags(false, false);
      blePresence.setEnabled(false);
    }
    stopWifiAndOta();
    LOGI("SET_PARAMS: wifi_ota_enabled=0 aplicado via %s", source);
  }
}

static bool isRelayCandidate(const LoRaFrame& frame) {
  return frame.msgType == MsgType::TELEMETRY ||
         frame.msgType == MsgType::EVENT ||
         frame.msgType == MsgType::ACK ||
         frame.msgType == MsgType::NACK ||
         frame.msgType == MsgType::RTR_CONTROL ||
         frame.msgType == MsgType::SET_FENCE ||
         frame.msgType == MsgType::SET_HERDING_PLAN ||
         frame.msgType == MsgType::SET_PARAMS ||
         frame.msgType == MsgType::PING;
}

static bool sendMatrixLoRaFrame(
    LoRaFrame& frame,
    MatrixLoRaTxReason txReason,
    const LoRaFrame* sourceUplinkOrNull,
    const char* callerTag,
    const char* commandId = nullptr) {
  const bool allowed = shouldAllowMatrixLoRaTx(txReason, sourceUplinkOrNull);
  LOGI(
      "LORA_TX_INTENT reason=%s caller=%s deviceId=%lu msgType=%u seq=%lu sourceMsgType=%u sourceSeq=%lu allowed=%d",
      matrixLoRaTxReasonLabel(txReason),
      callerTag ? callerTag : "-",
      (unsigned long)frame.deviceId,
      (unsigned)frame.msgType,
      (unsigned long)frame.seq,
      sourceUplinkOrNull ? (unsigned)sourceUplinkOrNull->msgType : 0U,
      sourceUplinkOrNull ? (unsigned long)sourceUplinkOrNull->seq : 0UL,
      allowed ? 1 : 0);
  if (!allowed) {
    LOGW(
        "LORA_TX_BLOCKED_UPLINK_ECHO deviceId=%lu msgType=%u seq=%lu sourceMsgType=%u sourceSeq=%lu reason=uplink_echo_blocked",
        (unsigned long)frame.deviceId,
        (unsigned)frame.msgType,
        (unsigned long)frame.seq,
        sourceUplinkOrNull ? (unsigned)sourceUplinkOrNull->msgType : 0U,
        sourceUplinkOrNull ? (unsigned long)sourceUplinkOrNull->seq : 0UL);
    return false;
  }
  if (isCommandLikeMatrixLoRaTxReason(txReason)) {
    LOGI(
        "LORA_TX_COMMAND_DISPATCH commandId=%s reason=%s msgType=%u deviceId=%lu",
        commandId && commandId[0] ? commandId : "-",
        matrixLoRaTxReasonLabel(txReason),
        (unsigned)frame.msgType,
        (unsigned long)frame.deviceId);
  }
  return lora.send(frame);
}

static const char* uplinkTypeLabel(MsgType t) {
  if (t == MsgType::TELEMETRY) return "telemetry";
  if (t == MsgType::EVENT) return "event";
  if (t == MsgType::ACK) return "ack";
  if (t == MsgType::NACK) return "nack";
  if (t == MsgType::RTR_CONTROL) return "rtr_control";
  return "lora";
}

static bool enqueueAcceptedUplink(const LoRaFrame& frame) {
  if (acceptedUplinkQueueCount >= kAcceptedUplinkQueueSize) {
    acceptedUplinkDropCount++;
    LOGW(
        "Fila uplink cheia; descartando device=%lu type=%u seq=%lu",
        (unsigned long)frame.deviceId,
        (unsigned)frame.msgType,
        (unsigned long)frame.seq);
    return false;
  }
  AcceptedUplinkEntry& slot = acceptedUplinkQueue[acceptedUplinkQueueHead];
  slot.used = true;
  slot.enqueuedAtMs = millis();
  slot.frame = frame;
  acceptedUplinkQueueHead =
      (uint8_t)((acceptedUplinkQueueHead + 1U) % kAcceptedUplinkQueueSize);
  acceptedUplinkQueueCount++;
  acceptedUplinkLastEnqueueAtMs = slot.enqueuedAtMs;
  return true;
}

static bool popAcceptedUplink(LoRaFrame& frame) {
  if (acceptedUplinkQueueCount == 0) return false;
  AcceptedUplinkEntry& slot = acceptedUplinkQueue[acceptedUplinkQueueTail];
  if (!slot.used) {
    acceptedUplinkQueueTail =
        (uint8_t)((acceptedUplinkQueueTail + 1U) % kAcceptedUplinkQueueSize);
    acceptedUplinkQueueCount--;
    return false;
  }
  frame = slot.frame;
  slot = AcceptedUplinkEntry{};
  acceptedUplinkQueueTail =
      (uint8_t)((acceptedUplinkQueueTail + 1U) % kAcceptedUplinkQueueSize);
  acceptedUplinkQueueCount--;
  return true;
}

static bool enqueueDeferredUplink(const LoRaFrame& frame) {
  if (deferredUplinkQueueCount >= kAcceptedUplinkQueueSize) {
    acceptedUplinkDropCount++;
    LOGW(
        "ACK_WAIT_DEFER_UPLINK drop device=%lu type=%u seq=%lu",
        (unsigned long)frame.deviceId,
        (unsigned)frame.msgType,
        (unsigned long)frame.seq);
    return false;
  }
  AcceptedUplinkEntry& slot = deferredUplinkQueue[deferredUplinkQueueHead];
  slot.used = true;
  slot.enqueuedAtMs = millis();
  slot.frame = frame;
  deferredUplinkQueueHead =
      (uint8_t)((deferredUplinkQueueHead + 1U) % kAcceptedUplinkQueueSize);
  deferredUplinkQueueCount++;
  activeSimpleCommand.deferredUplinkCount = deferredUplinkQueueCount;
  LOGI(
      "ACK_WAIT_DEFER_UPLINK device=%lu type=%u seq=%lu depth=%u",
      (unsigned long)frame.deviceId,
      (unsigned)frame.msgType,
      (unsigned long)frame.seq,
      (unsigned)deferredUplinkQueueCount);
  return true;
}

static bool popDeferredUplink(LoRaFrame& frame) {
  if (deferredUplinkQueueCount == 0) return false;
  AcceptedUplinkEntry& slot = deferredUplinkQueue[deferredUplinkQueueTail];
  if (!slot.used) {
    deferredUplinkQueueTail =
        (uint8_t)((deferredUplinkQueueTail + 1U) % kAcceptedUplinkQueueSize);
    deferredUplinkQueueCount--;
    activeSimpleCommand.deferredUplinkCount = deferredUplinkQueueCount;
    return false;
  }
  frame = slot.frame;
  slot = AcceptedUplinkEntry{};
  deferredUplinkQueueTail =
      (uint8_t)((deferredUplinkQueueTail + 1U) % kAcceptedUplinkQueueSize);
  deferredUplinkQueueCount--;
  activeSimpleCommand.deferredUplinkCount = deferredUplinkQueueCount;
  return true;
}

static void flushDeferredAcceptedUplinksIfReady() {
  if (deferredUplinkQueueCount == 0) return;
  if (deferredUplinkFlushAtMs == 0) return;
  const uint32_t now = millis();
  if ((int32_t)(now - deferredUplinkFlushAtMs) < 0) return;

  const uint8_t flushCount = deferredUplinkQueueCount;
  LOGI("ACK_WAIT_FLUSH_DEFERRED count=%u", (unsigned)flushCount);
  LoRaFrame frame;
  while (popDeferredUplink(frame)) {
    if (!enqueueAcceptedUplink(frame)) {
      processAcceptedUplink(frame);
    }
  }
  deferredUplinkFlushAtMs = 0;
}

static void openActiveSimpleCommandFeedbackWindow(uint32_t deviceId) {
  if (!activeSimpleCommand.active || deviceId == 0) return;
  activeSimpleCommand.awaitingFeedback = true;
  activeSimpleCommand.feedbackDeviceId = deviceId;
  activeSimpleCommand.feedbackWindowOpenedAtMs = millis();
  activeSimpleCommand.feedbackDeadlineAtMs =
      activeSimpleCommand.feedbackWindowOpenedAtMs +
      cfg::SIMPLE_COMMAND_ACK_PRIORITY_WINDOW_MS;
  activeSimpleCommand.sawTargetUplinkSinceDispatch = false;
  copyStringToBuffer(
      activeSimpleCommand.feedbackCommandId,
      sizeof(activeSimpleCommand.feedbackCommandId),
      activeSimpleCommand.commandId);
  copyStringToBuffer(
      activeSimpleCommand.lastFeedbackOutcome,
      sizeof(activeSimpleCommand.lastFeedbackOutcome),
      "waiting");
  simpleAckWaitActive = true;
  simpleAckWaitDeviceId = deviceId;
  simpleAckWaitDeadlineAtMs = activeSimpleCommand.feedbackDeadlineAtMs;
  copyStringToBuffer(
      simpleAckWaitCommandId, sizeof(simpleAckWaitCommandId), activeSimpleCommand.commandId);
  copyStringToBuffer(
      lastSimpleCommandFeedbackOutcome,
      sizeof(lastSimpleCommandFeedbackOutcome),
      "waiting");
  LOGI(
      "ACK_WAIT_OPEN cmd=%s device=%lu deadline=%lu",
      activeSimpleCommand.commandId,
      (unsigned long)deviceId,
      (unsigned long)activeSimpleCommand.feedbackDeadlineAtMs);
}

static void closeActiveSimpleCommandFeedbackWindow(const char* outcome) {
  if (!outcome || !outcome[0]) outcome = "closed";
  copyStringToBuffer(
      lastSimpleCommandFeedbackOutcome,
      sizeof(lastSimpleCommandFeedbackOutcome),
      outcome);
  copyStringToBuffer(
      activeSimpleCommand.lastFeedbackOutcome,
      sizeof(activeSimpleCommand.lastFeedbackOutcome),
      outcome);
  activeSimpleCommand.awaitingFeedback = false;
  activeSimpleCommand.feedbackDeviceId = 0;
  activeSimpleCommand.feedbackWindowOpenedAtMs = 0;
  activeSimpleCommand.feedbackDeadlineAtMs = 0;
  activeSimpleCommand.feedbackCommandId[0] = '\0';
  simpleAckWaitActive = false;
  simpleAckWaitDeviceId = 0;
  simpleAckWaitDeadlineAtMs = 0;
  simpleAckWaitCommandId[0] = '\0';
  if (deferredUplinkQueueCount > 0) {
    deferredUplinkFlushAtMs = millis() + cfg::SIMPLE_COMMAND_ACK_POST_FLUSH_DELAY_MS;
  }
}

static bool isAwaitedSimpleCommandFeedback(const LoRaFrame& rx) {
  if (!activeSimpleCommand.active || !activeSimpleCommand.awaitingFeedback) return false;
  if (rx.deviceId != activeSimpleCommand.feedbackDeviceId) return false;
  if (rx.msgType != MsgType::ACK && rx.msgType != MsgType::NACK) return false;

  StaticJsonDocument<256> payload;
  if (deserializeJson(payload, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return false;
  }
  const char* commandId = pickFirstText(payload["cmd_id"], payload["command_id"]);
  return commandId[0] != '\0' &&
      strcmp(commandId, activeSimpleCommand.commandId) == 0;
}

static void handleUplinkDuringAckWait(const LoRaFrame& rx) {
  if (!scopeMatchesBinding(rx.scopeId)) {
    LOGW(
        "scope_reject device=%lu msg=%u seq=%lu scope=%s ready=%d",
        (unsigned long)rx.deviceId,
        (unsigned)rx.msgType,
        (unsigned long)rx.seq,
        scopeIdToHex(rx.scopeId).c_str(),
        bindingReady ? 1 : 0);
    return;
  }
  if (tryHandlePendingWakePageAckFastPath(rx)) {
    return;
  }
  if (isAwaitedSimpleCommandFeedback(rx)) {
    lastSimpleCommandAckMatchedAtMs = millis();
    LOGI(
        "ACK_WAIT_MATCH cmd=%s device=%lu seq=%lu",
        activeSimpleCommand.commandId,
        (unsigned long)rx.deviceId,
        (unsigned long)rx.seq);
    closeActiveSimpleCommandFeedbackWindow("matched");
    handleSimpleCommandFeedback(rx);
    return;
  }

  // Even while ACK_WAIT is active, target uplinks for pending wake/page sessions
  // must go through the radio-critical fast-path before any deferred queueing.
  tryHandleWakePageImmediatelyAfterAcceptedUplink(rx, lora.lastAcceptedRxAtMs());

  if (activeSimpleCommand.active &&
      rx.deviceId == activeSimpleCommand.feedbackDeviceId) {
    scheduleActiveSimpleCommandRetryForRx(rx);
    enqueueDeferredUplink(rx);
    return;
  }
  enqueueAcceptedUplink(rx);
}

static void pollActiveSimpleCommandFeedbackSlice() {
  if (!activeSimpleCommand.active || !activeSimpleCommand.awaitingFeedback) return;
  const uint32_t sliceStartedAtMs = millis();
  while (activeSimpleCommand.awaitingFeedback &&
         (uint32_t)(millis() - sliceStartedAtMs) <
             cfg::SIMPLE_COMMAND_ACK_POLL_SLICE_MS) {
    LoRaFrame rx;
    if (!lora.receive(rx)) break;
    handleUplinkDuringAckWait(rx);
  }
  if (activeSimpleCommand.awaitingFeedback &&
      (int32_t)(millis() - activeSimpleCommand.feedbackDeadlineAtMs) >= 0) {
    LOGW(
        "ACK_WAIT_TIMEOUT cmd=%s device=%lu",
        activeSimpleCommand.commandId,
        (unsigned long)activeSimpleCommand.feedbackDeviceId);
    closeActiveSimpleCommandFeedbackWindow("timeout");
  }
}

static bool processPrioritySimpleCommandFeedbackWindow() {
  if (!activeSimpleCommand.active || !activeSimpleCommand.awaitingFeedback) return false;
  pollActiveSimpleCommandFeedbackSlice();
  return true;
}

static void processAcceptedUplink(const LoRaFrame& rx) {
  const int wakeIdx = findPendingWakeSessionByDeviceId(rx.deviceId);
  PendingWakeSession* wakeSession = wakeIdx >= 0 ? &pendingWakeSessions[wakeIdx] : nullptr;
  const bool deferCloudTx =
      wakeSession &&
      rtrwake::shouldDeferCloudTx(wakeSession->core, rx.deviceId);

  handleSimpleCommandFeedback(rx);
  handleHerdingOperationFeedback(rx);
  handleHerdingOperationEvent(rx);
  bool suppressRelay = false;
  if (activeSimpleCommand.active) {
    for (uint8_t i = 0; i < activeSimpleCommand.targetCount; ++i) {
      if (targetStateMatchesDeviceId(activeSimpleCommand.targets[i], rx.deviceId)) {
        suppressRelay = true;
        break;
      }
    }
  }
  if (!suppressRelay) {
    relayFrameToPeerGateways(rx);
  }

  StaticJsonDocument<576> packet;
  packet["type"] = uplinkTypeLabel(rx.msgType);
  packet["device_id"] = rx.deviceId;
  packet["msg_type"] = (int)rx.msgType;
  packet["seq"] = rx.seq;
  packet["timestamp"] = rx.timestamp;
  packet["scope_id"] = scopeIdToHex(rx.scopeId);
  packet["gateway_id"] = gatewayNodeId();
  packet["gateway_role"] = "matrix";
  packet["gateway_wifi_ota_enabled"] = wifiOtaEnabled;
  packet["payload"] = payloadBytesToString(rx.payload, rx.payloadLen);
  String out;
  serializeJson(packet, out);
  if (cfg::FEATURE_HTTP || cfg::FEATURE_WS) {
    api.broadcastTelemetry(out);
  }
  if (cfg::FEATURE_SD) sdlog.log(String("UL|") + out);
  drawStatus("RX LoRa", out.substring(0, 16).c_str());

  if (cfg::FEATURE_CLOUD) {
    if (deferCloudTx &&
        wakeSession &&
        wakeSession->core.active &&
        (lastPageDiag.lastImmediateDeviceId != rx.deviceId ||
         lastPageDiag.lastImmediateUplinkSeq != rx.seq ||
         lastPageDiag.lastImmediateResultAtMs < lastPageDiag.lastImmediateEnterAtMs)) {
      rtrdiag::noteOrderViolation(&lastPageDiag, "cloud_tx_before_page");
      LOGW(
          "RTR_FAST_PATH_ORDER_VIOLATION reason=cloud_tx_before_page deviceId=%lu commandId=%s uplinkSeq=%lu state=%s",
          (unsigned long)rx.deviceId,
          wakeSession->commandId[0] ? wakeSession->commandId : "-",
          (unsigned long)rx.seq,
          pendingWakeStateLabel(wakeSession->core.state));
      return;
    }
    publishTelemetryToCloud(rx);
    publishDailyHealthToCloud(rx);
    publishEventToCloud(rx);
    if (deferCloudTx && wakeSession && wakeSession->core.active) {
      wakeSession->core.cloudTxDeferred = false;
      LOGI(
          "RTR_WAKE_CLOUD_TX_RESUMED_AFTER_PAGE deviceId=%lu commandId=%s uplinkSeq=%lu reason=post_page_attempt",
          (unsigned long)rx.deviceId,
          wakeSession->commandId[0] ? wakeSession->commandId : "-",
          (unsigned long)wakeSession->core.uplinkSeq);
    }
  }
}

static void processQueuedAcceptedUplinks() {
  if (acceptedUplinkQueueCount == 0) return;
  const uint32_t now = millis();
  if (acceptedUplinkQueueCount < kAcceptedUplinkQueueSize &&
      (uint32_t)(now - acceptedUplinkLastEnqueueAtMs) < kAcceptedUplinkQuietMs) {
    return;
  }
  if (cfg::FEATURE_CLOUD && !backhaulWindowOpen()) return;

  LoRaFrame frame;
  if (!popAcceptedUplink(frame)) return;
  acceptedUplinkLastDrainAtMs = now;
  processAcceptedUplink(frame);
}

static bool readPointPair(const JsonArrayConst& pair, double& lat, double& lon) {
  if (pair.isNull() || pair.size() < 2 || pair[0].isNull() || pair[1].isNull()) return false;
  lat = pair[0].as<double>();
  lon = pair[1].as<double>();
  return rtcmd::isValidCoordinate(lat, lon);
}

static bool payloadUsesFenceRpv2(const JsonVariantConst payload) {
  if (payload["force_rpv2"].is<bool>()) return payload["force_rpv2"].as<bool>();
  return true;
}

static uint16_t rpv2ReasonCodeFromLabel(const char* reason) {
  if (!reason || !reason[0]) return rpv2::REASON_NONE;
  if (strcmp(reason, "planner_or_dispatch_stall") == 0) return rpv2::REASON_RETRY_EXHAUSTED;
  if (strcmp(reason, "no_point_fits_in_frame") == 0) return rpv2::REASON_NO_POINT_FITS_IN_FRAME;
  if (strcmp(reason, "point_chunk_too_large") == 0) return rpv2::REASON_NO_POINT_FITS_IN_FRAME;
  if (strcmp(reason, "codec_or_buffer_error") == 0) return rpv2::REASON_NO_POINT_FITS_IN_FRAME;
  if (strcmp(reason, "fence_single_point_chunk_too_large") == 0) return rpv2::REASON_SECURE_ENVELOPE_TOO_LARGE;
  if (strcmp(reason, "secure_envelope_too_large") == 0) return rpv2::REASON_SECURE_ENVELOPE_TOO_LARGE;
  if (strcmp(reason, "begin_timeout") == 0) return rpv2::REASON_BEGIN_TIMEOUT;
  if (strcmp(reason, "points_timeout") == 0) return rpv2::REASON_POINTS_TIMEOUT;
  if (strcmp(reason, "commit_timeout") == 0) return rpv2::REASON_COMMIT_TIMEOUT;
  if (strcmp(reason, "apply_timeout") == 0) return rpv2::REASON_APPLY_FAILED;
  if (strcmp(reason, "begin_rejected") == 0) return rpv2::REASON_BEGIN_REJECTED;
  if (strcmp(reason, "points_rejected") == 0) return rpv2::REASON_POINTS_OUT_OF_ORDER;
  if (strcmp(reason, "commit_rejected") == 0) return rpv2::REASON_COMMIT_REJECTED;
  if (strcmp(reason, "apply_failed") == 0) return rpv2::REASON_APPLY_FAILED;
  return rpv2::REASON_NONE;
}

static void setFenceTargetTransportState(
    uint32_t deviceId,
    const char* status,
    bool terminal,
    bool ok,
    const char* reason,
    uint16_t reasonCode) {
  char targetId[32]{};
  snprintf(targetId, sizeof(targetId), "%lu", (unsigned long)deviceId);
  const int idx = findActiveSimpleCommandTarget(targetId);
  if (idx < 0) return;
  ActiveSimpleCommandTargetState& target = activeSimpleCommand.targets[idx];
  target.terminal = terminal;
  target.ok = ok;
  copyStringToBuffer(target.status, sizeof(target.status), status ? status : "");
  copyStringToBuffer(target.reason, sizeof(target.reason), reason ? reason : "");
  activeSimpleCommand.lastReasonCode = reasonCode;
}

static void publishFenceTransportState(
    uint32_t deviceId,
    const char* transportState,
    const char* reason = nullptr,
    uint16_t reasonCode = rpv2::REASON_NONE,
    bool terminal = false,
    bool ok = false) {
  noteSetFenceCommandProgress(transportState);
  setFenceTargetTransportState(deviceId, transportState, terminal, ok, reason, reasonCode);
  publishSimpleCommandResult(transportState, reason);
}

static void markFenceCommandDispatchingBegin() {
  if (!activeSimpleCommand.active) return;
  if (strcmp(activeSimpleCommand.command, "SET_FENCE") != 0) return;
  AS_MATRIX_COMMAND_MARK_DISPATCHING_BEGIN(
      activeSimpleCommand.commandId,
      activeSimpleCommand.command);
}

static void logRpv2StageTransition(
    uint32_t deviceId,
    const char* commandId,
    const char* fromStage,
    const char* toStage) {
  LOGI(
      "RPV2_STAGE_TRANSITION deviceId=%lu commandId=%s from=%s to=%s",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      fromStage ? fromStage : "-",
      toStage ? toStage : "-");
}

static const char* pendingWakeStateLabel(rtrwake::State state) {
  return rtrwake::stateLabel(state);
}

static bool hasPendingWakeSessions() {
  for (uint8_t i = 0; i < kMaxPendingWakeSessions; ++i) {
    if (pendingWakeSessions[i].core.active) return true;
  }
  return false;
}

static int findPendingWakeSessionByDeviceId(uint32_t deviceId) {
  if (deviceId == 0) return -1;
  for (uint8_t i = 0; i < kMaxPendingWakeSessions; ++i) {
    if (pendingWakeSessions[i].core.active &&
        pendingWakeSessions[i].core.deviceId == deviceId) {
      return i;
    }
  }
  return -1;
}

static int findPendingWakeSessionByCommandId(const char* commandId) {
  if (!commandId || !commandId[0]) return -1;
  for (uint8_t i = 0; i < kMaxPendingWakeSessions; ++i) {
    if (!pendingWakeSessions[i].core.active) continue;
    if (strcmp(pendingWakeSessions[i].commandId, commandId) == 0) return i;
  }
  return -1;
}

static bool hasPendingWakeSessionForCommand(const char* commandId) {
  return findPendingWakeSessionByCommandId(commandId) >= 0;
}

static int findPendingWakeSessionByPageCorrelation(
    uint32_t deviceId,
    uint64_t sessionId,
    uint32_t messageId) {
  for (uint8_t i = 0; i < kMaxPendingWakeSessions; ++i) {
    if (rtrwake::pageAckMatches(
            pendingWakeSessions[i].core, deviceId, sessionId, messageId)) {
      return i;
    }
  }
  return -1;
}

static PendingWakeSession* allocatePendingWakeSession() {
  for (uint8_t i = 0; i < kMaxPendingWakeSessions; ++i) {
    if (!pendingWakeSessions[i].core.active) return &pendingWakeSessions[i];
  }
  return nullptr;
}

static void setPendingWakeReason(
    PendingWakeSession& session,
    uint16_t reasonCode,
    const char* reasonLabel) {
  session.lastReasonCode = reasonCode;
  copyStringToBuffer(
      session.lastReasonLabel,
      sizeof(session.lastReasonLabel),
      reasonLabel ? reasonLabel : "");
}

static void transitionPendingWakeState(
    PendingWakeSession& session,
    rtrwake::State nextState,
    const char* reason) {
  const rtrwake::State previous = session.core.state;
  if (previous == nextState) return;
  session.core.state = nextState;
  LOGI(
      "RTR_STATE_TRANSITION commandId=%s deviceId=%lu fromState=%s toState=%s campaignCount=%u reason=%s",
      session.commandId[0] ? session.commandId : "-",
      (unsigned long)session.core.deviceId,
      pendingWakeStateLabel(previous),
      pendingWakeStateLabel(nextState),
      (unsigned)session.core.campaignCount,
      reason ? reason : "-");
}

static void syncLastPageDiagFromSession(const PendingWakeSession& session) {
  rtrdiag::noteInFlightPageContext(
      &lastPageDiag,
      session.core.inFlightPage.valid,
      session.core.inFlightPage.sessionId,
      session.core.inFlightPage.messageId,
      session.core.inFlightPage.campaignCount,
      session.core.inFlightPage.sentAtMs,
      session.core.inFlightPage.softDeadlineAtMs,
      session.core.inFlightPage.hardDeadlineAtMs,
      session.core.inFlightPage.ackAccepted);
  lastPageDiag.retryPending = session.core.scheduledRetry.pending;
  lastPageDiag.retryAtMs = session.core.scheduledRetry.retryAtMs;
  lastPageDiag.retryCampaignCount = session.core.scheduledRetry.nextCampaignCount;
}

static void noteWakeLoopStage(const char* stage, const PendingWakeSession& session) {
  const uint32_t nowMs = millis();
  rtrdiag::noteWakeLoopStage(
      &wakeLoopDiag,
      stage,
      nowMs,
      session.core.inFlightPage.valid ? session.core.inFlightPage.sessionId : session.core.pageSessionId,
      session.core.deviceId);
  LOGI(
      "RTR_WAKE_LOOP_STAGE stage=%s deviceId=%lu sessionId=%llu",
      stage ? stage : "-",
      (unsigned long)wakeLoopDiag.lastWakeLoopStageDeviceId,
      (unsigned long long)wakeLoopDiag.lastWakeLoopStageSessionId);
}

static rtrwake::Presence* findDevicePresence(uint32_t deviceId) {
  if (deviceId == 0) return nullptr;
  for (uint8_t i = 0; i < kMaxDevicePresenceEntries; ++i) {
    if (devicePresence[i].valid && devicePresence[i].deviceId == deviceId) {
      return &devicePresence[i];
    }
  }
  for (uint8_t i = 0; i < kMaxDevicePresenceEntries; ++i) {
    if (!devicePresence[i].valid) return &devicePresence[i];
  }
  return &devicePresence[0];
}

static void updateDevicePresenceFromAcceptedUplink(const LoRaFrame& rx, uint32_t atMs) {
  if (rx.deviceId == 0) return;
  rtrwake::Presence* presence = findDevicePresence(rx.deviceId);
  if (!presence) return;
  const uint32_t previousSeenAtMs = presence->lastSeenAtMs;
  rtrwake::updatePresence(presence, rx.deviceId, atMs);
  LOGI(
      "RTR_DEVICE_PRESENCE_UPDATE deviceId=%lu lastSeenAtMs=%lu estimatedCycleMs=%lu previousSeenAtMs=%lu",
      (unsigned long)presence->deviceId,
      (unsigned long)presence->lastSeenAtMs,
      (unsigned long)presence->estimatedCycleMs,
      (unsigned long)previousSeenAtMs);
}

static void finalizeFenceCommandIfAllTargetsTerminal() {
  if (!activeSimpleCommand.active) return;
  if (strcmp(activeSimpleCommand.command, "SET_FENCE") != 0) return;
  if (!allActiveSimpleTargetsTerminal()) return;
  const bool anyFailed = anyActiveSimpleTargetFailed();
  const char* finalStatus = anyFailed ? "failed" : "applied";
  const char* finalReason = anyFailed ? firstActiveSimpleTargetFailureReason() : nullptr;
  publishSimpleCommandResult(finalStatus, finalReason);
  clearActiveSimpleCommand();
}

static void clearPendingWakeSession(int idx, const char* reason) {
  if (idx < 0 || idx >= kMaxPendingWakeSessions) return;
  PendingWakeSession& session = pendingWakeSessions[idx];
  if (!session.core.active) return;
  if (session.core.inFlightPage.valid) {
    LOGI(
        "RTR_PAGE_ATTEMPT_REPLACED deviceId=%lu commandId=%s sessionId=%llu messageId=%lu reason=%s",
        (unsigned long)session.core.deviceId,
        session.commandId[0] ? session.commandId : "-",
        (unsigned long long)session.core.inFlightPage.sessionId,
        (unsigned long)session.core.inFlightPage.messageId,
        reason ? reason : "-");
  }
  LOGI(
      "RTR_WAKE_SESSION_CLEARED commandId=%s deviceId=%lu state=%s campaignCount=%u reason=%s",
      session.commandId[0] ? session.commandId : "-",
      (unsigned long)session.core.deviceId,
      pendingWakeStateLabel(session.core.state),
      (unsigned)session.core.campaignCount,
      reason ? reason : "-");
  session = PendingWakeSession{};
  finalizeFenceCommandIfAllTargetsTerminal();
}

static void failPendingWakeSession(
    PendingWakeSession& session,
    uint16_t reasonCode,
    const char* reasonLabel) {
  setPendingWakeReason(session, reasonCode, reasonLabel);
  transitionPendingWakeState(session, rtrwake::State::FAILED, reasonLabel);
  publishFenceTransportState(
      session.core.deviceId,
      "failed",
      reasonLabel,
      reasonCode,
      true,
      false);
}

static void checkSetFencePlannerDispatchStall(uint32_t nowTick, uint64_t nowMs) {
  if (!activeSimpleCommand.active) return;
  if (strcmp(activeSimpleCommand.command, "SET_FENCE") != 0) return;
  if (hasPendingWakeSessionForCommand(activeSimpleCommand.commandId)) return;
  if (activeSimpleCommand.awaitingFeedback) return;
  const uint32_t progressAt =
      activeSimpleCommand.lastProgressAtMs != 0
          ? activeSimpleCommand.lastProgressAtMs
          : activeSimpleCommand.dispatchAtMs;
  if (progressAt == 0) return;
  if ((uint32_t)(nowTick - progressAt) < kSetFenceLocalStallTimeoutMs) return;
  activeSimpleCommand.lastReasonCode =
      rpv2fenceplanner::reasonCodeFromLabel("planner_or_dispatch_stall");
  publishSimpleCommandResult("failed", "planner_or_dispatch_stall");
  clearActiveSimpleCommand();
}

static bool notePendingWakeHintFromUplink(const LoRaFrame& rx, uint32_t rxAcceptedAtMs) {
  const int idx = findPendingWakeSessionByDeviceId(rx.deviceId);
  if (idx < 0) return false;
  PendingWakeSession& session = pendingWakeSessions[idx];
  const char* fromState = pendingWakeStateLabel(session.core.state);
  const bool wasRequiringFreshUplink = session.core.requiresFreshUplink;
  session.core.uplinkSeq = rx.seq;
  const bool accepted = rtrwake::noteUplinkHint(&session.core, rx.deviceId, rxAcceptedAtMs);
  rtrdiag::noteWakeHint(&lastPageDiag, rxAcceptedAtMs, rx.seq, accepted);
  LOGI(
      "RTR_WAKE_HINT_CAPTURED deviceId=%lu commandId=%s uplinkSeq=%lu accepted=%d stateBefore=%s atMs=%lu",
      (unsigned long)rx.deviceId,
      session.commandId[0] ? session.commandId : "-",
      (unsigned long)rx.seq,
      accepted ? 1 : 0,
      fromState,
      (unsigned long)rxAcceptedAtMs);
  if (!accepted) return false;
  if (wasRequiringFreshUplink) {
    LOGI(
        "RTR_FRESH_UPLINK_RECEIVED deviceId=%lu commandId=%s uplinkSeq=%lu",
        (unsigned long)rx.deviceId,
        session.commandId[0] ? session.commandId : "-",
        (unsigned long)rx.seq);
  }
  publishFenceTransportState(session.core.deviceId, "paging_ready");
  LOGI(
      "RTR_WAKE_HINT_FROM_UPLINK deviceId=%lu commandId=%s stateBefore=%s lastSeenAtMs=%lu campaignCount=%u",
      (unsigned long)rx.deviceId,
      session.commandId[0] ? session.commandId : "-",
      fromState,
      (unsigned long)session.core.lastUplinkAtMs,
      (unsigned)session.core.campaignCount);
  transitionPendingWakeState(session, rtrwake::State::PAGING_READY_TO_SEND, "uplink_hint");
  LOGI(
      "RTR_PAGE_READY_TO_SEND deviceId=%lu commandId=%s campaignCount=%u",
      (unsigned long)rx.deviceId,
      session.commandId[0] ? session.commandId : "-",
      (unsigned)session.core.campaignCount);
  return true;
}

static bool reschedulePendingWakeForFreshUplink(
    PendingWakeSession& session,
    uint32_t nowMs,
    const char* stage,
    const char* reasonLabel) {
  const uint32_t hintAgeMs = rtrwake::wakeHintAgeMs(session.core, nowMs);
  if (rtrwake::hasFreshWakeHint(session.core, nowMs, rtrv1::FAST_PAGE_DEADLINE_MS)) {
    return false;
  }
  noteWakeLoopStage(stage, session);
  LOGW(
      "RTR_WAKE_HINT_STALE deviceId=%lu commandId=%s ageMs=%lu maxAgeMs=%lu state=%s action=wait_next_uplink",
      (unsigned long)session.core.deviceId,
      session.commandId[0] ? session.commandId : "-",
      (unsigned long)hintAgeMs,
      (unsigned long)rtrv1::FAST_PAGE_DEADLINE_MS,
      pendingWakeStateLabel(session.core.state));
  transitionPendingWakeState(
      session,
      rtrwake::State::PAGING_WAITING_UPLINK,
      reasonLabel);
  rtrwake::requireFreshUplink(&session.core, nowMs);
  LOGI(
      "RTR_WAITING_FRESH_UPLINK deviceId=%lu commandId=%s reason=%s",
      (unsigned long)session.core.deviceId,
      session.commandId[0] ? session.commandId : "-",
      reasonLabel ? reasonLabel : "-");
  publishFenceTransportState(session.core.deviceId, "paging_waiting_fresh_uplink");
  return true;
}

static bool tryHandleWakePageImmediatelyAfterAcceptedUplink(
    const LoRaFrame& rx,
    uint32_t rxAcceptedAtMs) {
  LOGI(
      "LORA_UPLINK_ACCEPTED deviceId=%lu msgType=%u seq=%lu scopeId=%016llX",
      (unsigned long)rx.deviceId,
      (unsigned)rx.msgType,
      (unsigned long)rx.seq,
      (unsigned long long)rx.scopeId);
  updateDevicePresenceFromAcceptedUplink(rx, rxAcceptedAtMs);

  const int wakeIdx = findPendingWakeSessionByDeviceId(rx.deviceId);
  if (wakeIdx < 0) {
    rtrdiag::noteImmediateEnter(&lastPageDiag, rxAcceptedAtMs, rx.deviceId, rx.seq);
    rtrdiag::noteImmediateResult(
        &lastPageDiag,
        millis(),
        rx.deviceId,
        rx.seq,
        0xFFFFFFFFUL,
        "no_session",
        false);
    return false;
  }

  PendingWakeSession& session = pendingWakeSessions[wakeIdx];
  const char* commandId = session.commandId[0] ? session.commandId : "-";
  const char* stateBefore = pendingWakeStateLabel(session.core.state);
  notePendingWakeHintFromUplink(rx, rxAcceptedAtMs);
  const uint32_t nowMs = millis();
  const uint32_t ageMs = rtrwake::wakeHintAgeMs(session.core, nowMs);
  rtrdiag::noteImmediateEnter(&lastPageDiag, nowMs, rx.deviceId, rx.seq);
  LOGI(
      "RTR_WAKE_FAST_PATH_IMMEDIATE_ENTER deviceId=%lu commandId=%s uplinkSeq=%lu rxAcceptedAtMs=%lu nowMs=%lu ageMs=%lu stateBefore=%s stateAfter=%s",
      (unsigned long)rx.deviceId,
      commandId,
      (unsigned long)rx.seq,
      (unsigned long)rxAcceptedAtMs,
      (unsigned long)nowMs,
      (unsigned long)ageMs,
      stateBefore,
      pendingWakeStateLabel(session.core.state));

  if (session.core.cloudTxDeferred) {
    LOGI(
        "RTR_WAKE_CLOUD_TX_DEFERRED_UNTIL_PAGE deviceId=%lu commandId=%s uplinkSeq=%lu rxAcceptedAtMs=%lu nowMs=%lu reason=%s",
        (unsigned long)rx.deviceId,
        commandId,
        (unsigned long)session.core.uplinkSeq,
        (unsigned long)rxAcceptedAtMs,
        (unsigned long)nowMs,
        pendingWakeStateLabel(session.core.state));
  }

  if (session.core.state != rtrwake::State::PAGING_READY_TO_SEND) {
    rtrdiag::noteImmediateResult(
        &lastPageDiag,
        nowMs,
        rx.deviceId,
        rx.seq,
        ageMs,
        "state_not_pageable",
        session.core.cloudTxDeferred);
    LOGI(
        "RTR_WAKE_FAST_PATH_IMMEDIATE_RESULT deviceId=%lu commandId=%s uplinkSeq=%lu rxAcceptedAtMs=%lu nowMs=%lu ageMs=%lu result=%s stateAfter=%s",
        (unsigned long)rx.deviceId,
        commandId,
        (unsigned long)rx.seq,
        (unsigned long)rxAcceptedAtMs,
        (unsigned long)nowMs,
        (unsigned long)ageMs,
        "state_not_pageable",
        pendingWakeStateLabel(session.core.state));
    return false;
  }

  if (reschedulePendingWakeForFreshUplink(
          session,
          nowMs,
          "fast_path_immediate_wake_hint_stale",
          "wake_hint_stale_wait_next_uplink")) {
    rtrdiag::noteImmediateResult(
        &lastPageDiag,
        nowMs,
        rx.deviceId,
        rx.seq,
        ageMs,
        "stale",
        session.core.cloudTxDeferred);
    LOGI(
        "RTR_WAKE_FAST_PATH_IMMEDIATE_RESULT deviceId=%lu commandId=%s uplinkSeq=%lu rxAcceptedAtMs=%lu nowMs=%lu ageMs=%lu result=%s stateAfter=%s",
        (unsigned long)rx.deviceId,
        commandId,
        (unsigned long)rx.seq,
        (unsigned long)rxAcceptedAtMs,
        (unsigned long)nowMs,
        (unsigned long)ageMs,
        "stale",
        pendingWakeStateLabel(session.core.state));
    return false;
  }

  const char* fastPathReason = nullptr;
  if (!trySendRtrPage(session, &fastPathReason)) {
    const char* result =
        fastPathReason && strstr(fastPathReason, "busy") ? "radio_busy" : "page_send_failed";
    const uint32_t resultNowMs = millis();
    const uint32_t resultAgeMs = rtrwake::wakeHintAgeMs(session.core, resultNowMs);
    rtrdiag::noteImmediateResult(
        &lastPageDiag,
        resultNowMs,
        rx.deviceId,
        rx.seq,
        resultAgeMs,
        result,
        session.core.cloudTxDeferred);
    LOGW(
        "RTR_WAKE_FAST_PATH_IMMEDIATE_RESULT deviceId=%lu commandId=%s uplinkSeq=%lu rxAcceptedAtMs=%lu nowMs=%lu ageMs=%lu result=%s reason=%s stateAfter=%s",
        (unsigned long)rx.deviceId,
        commandId,
        (unsigned long)rx.seq,
        (unsigned long)rxAcceptedAtMs,
        (unsigned long)resultNowMs,
        (unsigned long)resultAgeMs,
        result,
        fastPathReason && fastPathReason[0] ? fastPathReason : "page_send_failed",
        pendingWakeStateLabel(session.core.state));
    return false;
  }

  const uint32_t resultNowMs = millis();
  const uint32_t resultAgeMs = rtrwake::wakeHintAgeMs(session.core, resultNowMs);
  rtrdiag::noteImmediateResult(
      &lastPageDiag,
      resultNowMs,
      rx.deviceId,
      rx.seq,
      resultAgeMs,
      "page_tx_ok",
      session.core.cloudTxDeferred);
  LOGI(
      "RTR_WAKE_FAST_PATH_IMMEDIATE_RESULT deviceId=%lu commandId=%s uplinkSeq=%lu rxAcceptedAtMs=%lu nowMs=%lu ageMs=%lu result=%s stateAfter=%s",
      (unsigned long)rx.deviceId,
      commandId,
      (unsigned long)rx.seq,
      (unsigned long)rxAcceptedAtMs,
      (unsigned long)resultNowMs,
      (unsigned long)resultAgeMs,
      "page_tx_ok",
      pendingWakeStateLabel(session.core.state));
  return true;
}

static int32_t coordinateToE7(double value) {
  const double scaled = value * 10000000.0;
  return static_cast<int32_t>(scaled >= 0.0 ? scaled + 0.5 : scaled - 0.5);
}

static bool buildExactSecureWireMetrics(
    const LoRaFrame& tx,
    SecureWireMetrics* outMetrics,
    uint8_t* outWireBuffer,
    size_t outWireBufferCap) {
  return lora.buildSecureWireMetrics(tx, outMetrics, outWireBuffer, outWireBufferCap);
}

static bool sendLoRaBinaryFrame(
    uint32_t deviceId,
    MsgType msgType,
    uint64_t scopeId,
    const uint8_t* payload,
    size_t payloadLen,
    const char** reason,
    MatrixLoRaTxReason txReason = MatrixLoRaTxReason::Unknown,
    const char* callerTag = "sendLoRaBinaryFrame",
    const LoRaFrame* sourceUplinkOrNull = nullptr,
    const char* commandId = nullptr) {
  if (!payload || payloadLen == 0 || payloadLen > cfg::LORA_MAX_PAYLOAD_BYTES) {
    if (reason) *reason = "payload_too_large";
    return false;
  }

  LoRaFrame tx;
  tx.deviceId = deviceId;
  tx.scopeId = scopeId == 0 ? bindingScopeIdValue() : scopeId;
  tx.msgType = msgType;
  tx.seq = nextDownlinkSeq();
  tx.timestamp = millis() / 1000;
  for (int i = 0; i < 12; ++i) tx.nonce[i] = (uint8_t)esp_random();
  tx.payloadLen = static_cast<uint8_t>(payloadLen);
  memcpy(tx.payload, payload, payloadLen);
  SecureWireMetrics metrics;
  if (!buildExactSecureWireMetrics(tx, &metrics, nullptr, 0)) {
    if (reason) *reason = metrics.reason ? metrics.reason : "secure_envelope_build_failed";
    return false;
  }
  if (metrics.wireLenFinal > rpv2::MAX_LORA_FRAME_BYTES) {
    if (reason) *reason = "secure_envelope_too_large";
    return false;
  }
  const bool ok = sendMatrixLoRaFrame(
      tx,
      txReason,
      sourceUplinkOrNull,
      callerTag,
      commandId);
  if (!ok && reason && !*reason) *reason = "lora_send_failed";
  return ok;
}

static bool trySendRtrPage(
    PendingWakeSession& session,
    const char** reason) {
  rtrv1::Header header{};
  header.version = rtrv1::PROTOCOL_VERSION;
  header.trafficClass = rtrv1::TRAFFIC_CLASS_P0;
  header.innerMsgType = rtrv1::RTR_PAGE;
  header.flags = rtrv1::FLAG_ACK_REQUIRED | rtrv1::FLAG_PAGE | rtrv1::FLAG_WAKE_LOCK;
  header.sessionId = session.core.pageSessionId;
  header.messageId = session.core.pageMessageId;
  header.sourceId = 0;
  header.finalDestId = session.core.deviceId;
  header.nextHopId = session.core.deviceId;
  header.fragmentIndex = 0;
  header.fragmentTotal = 1;
  header.hopCount = 0;
  header.ttl = rtrv1::DEFAULT_TTL;

  rtrv1::PageBody body{};
  body.commandType = static_cast<uint8_t>(session.commandType);
  body.priority = rtrv1::TRAFFIC_CLASS_P1;
  body.estimatedFragments = session.estimatedFragments;
  body.sessionTimeoutSec = rtrv1::SESSION_CACHE_TTL_SEC;
  body.wakeLockSec = rtrv1::SESSION_WAKE_LOCK_MS / 1000UL;
  body.routeId = 0;

  uint8_t payload[sizeof(rtrv1::Header) + sizeof(rtrv1::PageBody)]{};
  const size_t payloadLen = rtrv1::encodeFrame(header, body, payload, sizeof(payload));
  if (payloadLen == 0) {
    if (reason) *reason = "page_encode_failed";
    return false;
  }

  LOGI(
      "RTR_PAGE_PLAN deviceId=%lu commandId=%s sessionId=%llu messageId=%lu commandType=%u estimatedFragments=%u",
      (unsigned long)session.core.deviceId,
      session.commandId[0] ? session.commandId : "-",
      (unsigned long long)session.core.pageSessionId,
      (unsigned long)session.core.pageMessageId,
      (unsigned)session.commandType,
      (unsigned)session.estimatedFragments);
  if (!sendLoRaBinaryFrame(
          session.core.deviceId,
          MsgType::RTR_CONTROL,
          session.scopeId,
          payload,
          payloadLen,
          reason,
          MatrixLoRaTxReason::RtrPage,
          "trySendRtrPage",
          nullptr,
          session.commandId)) {
    rtrdiag::notePageOutcome(&lastPageDiag, "not_sent");
    setPendingWakeReason(
        session,
        rtrv1::REASON_PAGE_SEND_FAILED,
        reason && *reason ? *reason : rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_SEND_FAILED));
    LOGW(
        "RTR_PAGE_TX_FAIL deviceId=%lu commandId=%s campaignCount=%u reason=%s",
        (unsigned long)session.core.deviceId,
        session.commandId[0] ? session.commandId : "-",
        (unsigned)session.core.campaignCount,
        session.lastReasonLabel[0] ? session.lastReasonLabel : "page_send_failed");
    return false;
  }
  publishFenceTransportState(session.core.deviceId, "paging_sent");
  rtrwake::markPageAttempt(&session.core, millis(), rtrv1::PAGE_ACK_TIMEOUT_MS);
  rtrdiag::notePageTx(
      &lastPageDiag,
      session.core.deviceId,
      session.core.pageSessionId,
      session.core.pageMessageId,
      session.core.campaignCount,
      session.core.lastPageSentAtMs,
      session.core.pageAckDeadlineAtMs);
  syncLastPageDiagFromSession(session);
  transitionPendingWakeState(session, rtrwake::State::PAGING_AWAITING_ACK, "page_tx_ok");
  publishFenceTransportState(session.core.deviceId, "awaiting_page_ack");
  appendPropertyCommandEvent(
      activeSimpleCommand.propertyId,
      activeSimpleCommand.commandId,
      "rtr_page_sent",
      nullptr,
      nullptr);
  const rtrwake::FastPathMetric fastPathMetric =
      rtrwake::computeFastPathMetric(session.core, rtrv1::FAST_PAGE_DEADLINE_MS);
  if (fastPathMetric.valid) {
    rtrdiag::notePageLatency(
        &lastPageDiag,
        fastPathMetric.deltaMs,
        rtrv1::FAST_PAGE_DEADLINE_MS,
        fastPathMetric.deadlineMet);
    LOGI(
        "RTR_WAKE_TO_PAGE_LATENCY deviceId=%lu commandId=%s uplinkSeq=%lu rxAcceptedAtMs=%lu pageTxAtMs=%lu deltaMs=%lu deadlineMs=%lu deadlineMet=%d reason=page_tx_ok",
        (unsigned long)session.core.deviceId,
        session.commandId[0] ? session.commandId : "-",
        (unsigned long)session.core.uplinkSeq,
        (unsigned long)fastPathMetric.rxAcceptedAtMs,
        (unsigned long)fastPathMetric.pageTxAtMs,
        (unsigned long)fastPathMetric.deltaMs,
        (unsigned long)rtrv1::FAST_PAGE_DEADLINE_MS,
        fastPathMetric.deadlineMet ? 1 : 0);
    if (!fastPathMetric.deadlineMet) {
      LOGW(
          "RTR_PAGE_SOFT_DEADLINE_MISSED deviceId=%lu commandId=%s uplinkSeq=%lu deltaMs=%lu softDeadlineMs=%lu",
          (unsigned long)session.core.deviceId,
          session.commandId[0] ? session.commandId : "-",
          (unsigned long)session.core.uplinkSeq,
          (unsigned long)fastPathMetric.deltaMs,
          (unsigned long)rtrv1::FAST_PAGE_DEADLINE_MS);
    }
  }
  LOGI(
      "RTR_PAGE_TX_CONTEXT deviceId=%lu commandId=%s sessionId=%llu messageId=%lu campaignCount=%u sentAtMs=%lu ackDeadlineAtMs=%lu outcome=%s",
      (unsigned long)lastPageDiag.lastPageTargetDeviceId,
      session.commandId[0] ? session.commandId : "-",
      (unsigned long long)lastPageDiag.lastPageSessionId,
      (unsigned long)lastPageDiag.lastPageMessageId,
      (unsigned)lastPageDiag.lastPageCampaignCount,
      (unsigned long)lastPageDiag.lastPageSentAtMs,
      (unsigned long)lastPageDiag.lastPageAckDeadlineAtMs,
      lastPageDiag.lastPageOutcome);
  LOGI(
      "RTR_PAGE_TX_OK deviceId=%lu commandId=%s sessionId=%llu messageId=%lu campaignCount=%u",
      (unsigned long)session.core.deviceId,
      session.commandId[0] ? session.commandId : "-",
      (unsigned long long)session.core.pageSessionId,
      (unsigned long)session.core.pageMessageId,
      (unsigned)session.core.campaignCount);
  markFenceCommandDispatchingBegin();
  return true;
}

static bool decodeRtrPageAckFrame(
    const LoRaFrame& rx,
    uint64_t sessionId,
    uint32_t messageId,
    rtrv1::PageAckBody* outBody) {
  if (!outBody || rx.msgType != MsgType::RTR_CONTROL) return false;
  rtrv1::Header header{};
  rtrv1::PageAckBody body{};
  if (!rtrv1::decodePageAck(rx.payload, rx.payloadLen, &header, &body)) return false;
  if (header.sessionId != sessionId || header.messageId != messageId) return false;
  *outBody = body;
  return true;
}

static bool tryHandlePendingWakePageAckFastPath(const LoRaFrame& rx) {
  if (rx.msgType != MsgType::RTR_CONTROL) return false;
  rtrv1::Header header{};
  rtrv1::PageAckBody ack{};
  if (!rtrv1::decodePageAck(rx.payload, rx.payloadLen, &header, &ack)) return false;
  const int idx = findPendingWakeSessionByPageCorrelation(
      rx.deviceId, header.sessionId, header.messageId);
  if (idx < 0) return false;
  PendingWakeSession& session = pendingWakeSessions[idx];
  if (!rtrwake::canConsumePageAckFastPath(session.core)) {
    const uint32_t nowMs = millis();
    const bool lateAck = rtrwake::isLatePageAck(session.core, nowMs);
    rtrdiag::noteAckRejected(&lastPageDiag, lateAck ? "ack_after_hard_timeout" : "ack_not_consumable");
    if (lateAck) {
      LOGW(
          "RTR_PAGE_ACK_FAST_PATH_LATE deviceId=%lu commandId=%s sessionId=%llu messageId=%lu state=%s hardDeadlineAtMs=%lu nowMs=%lu accepted=%u sessionModeActive=%u",
          (unsigned long)rx.deviceId,
          session.commandId[0] ? session.commandId : "-",
          (unsigned long long)header.sessionId,
          (unsigned long)header.messageId,
          pendingWakeStateLabel(session.core.state),
          (unsigned long)session.core.inFlightPage.hardDeadlineAtMs,
          (unsigned long)nowMs,
          (unsigned)ack.accepted,
          (unsigned)ack.sessionModeActive);
    } else {
      LOGW(
          "RTR_PAGE_ACK_FAST_PATH_SKIP deviceId=%lu commandId=%s sessionId=%llu messageId=%lu state=%s inFlightValid=%d pageSent=%d hardDeadlineAtMs=%lu accepted=%u sessionModeActive=%u",
          (unsigned long)rx.deviceId,
          session.commandId[0] ? session.commandId : "-",
          (unsigned long long)header.sessionId,
          (unsigned long)header.messageId,
          pendingWakeStateLabel(session.core.state),
          session.core.inFlightPage.valid ? 1 : 0,
          session.core.inFlightPage.pageSent ? 1 : 0,
          (unsigned long)session.core.inFlightPage.hardDeadlineAtMs,
          (unsigned)ack.accepted,
          (unsigned)ack.sessionModeActive);
    }
    return false;
  }
  LOGI(
      "RTR_PAGE_ACK_FAST_PATH_MATCH deviceId=%lu commandId=%s sessionId=%llu messageId=%lu state=%s accepted=%u sessionModeActive=%u",
      (unsigned long)rx.deviceId,
      session.commandId[0] ? session.commandId : "-",
      (unsigned long long)header.sessionId,
      (unsigned long)header.messageId,
      pendingWakeStateLabel(session.core.state),
      (unsigned)ack.accepted,
      (unsigned)ack.sessionModeActive);
  return handlePendingWakePageAck(rx);
}

static bool handlePendingWakePageAck(const LoRaFrame& rx) {
  if (rx.msgType != MsgType::RTR_CONTROL) return false;
  rtrv1::Header header{};
  rtrv1::PageAckBody ack{};
  if (!rtrv1::decodePageAck(rx.payload, rx.payloadLen, &header, &ack)) return false;
  const int idx = findPendingWakeSessionByPageCorrelation(
      rx.deviceId, header.sessionId, header.messageId);
  if (idx < 0) {
    LOGW(
        "RTR_PAGE_ACK_INVALID deviceId=%lu sessionId=%llu messageId=%lu accepted=%u sessionModeActive=%u",
        (unsigned long)rx.deviceId,
        (unsigned long long)header.sessionId,
        (unsigned long)header.messageId,
        (unsigned)ack.accepted,
        (unsigned)ack.sessionModeActive);
    return false;
  }
  PendingWakeSession& session = pendingWakeSessions[idx];
  const bool ackWithinGrace =
      session.core.state == rtrwake::State::PAGING_RETRY_GRACE &&
      session.core.inFlightPage.valid &&
      session.core.inFlightPage.hardDeadlineAtMs != 0 &&
      (int32_t)(millis() - session.core.inFlightPage.hardDeadlineAtMs) < 0;
  if (session.core.state != rtrwake::State::PAGING_AWAITING_ACK &&
      !ackWithinGrace) {
    const uint32_t nowMs = millis();
    const bool lateAck = rtrwake::isLatePageAck(session.core, nowMs);
    rtrdiag::noteAckRejected(
        &lastPageDiag,
        lateAck ? "ack_after_hard_timeout" : "state_not_awaiting_ack");
    if (lateAck) {
      LOGW(
          "RTR_PAGE_ACK_LATE deviceId=%lu commandId=%s state=%s sessionId=%llu messageId=%lu hardDeadlineAtMs=%lu nowMs=%lu",
          (unsigned long)rx.deviceId,
          session.commandId[0] ? session.commandId : "-",
          pendingWakeStateLabel(session.core.state),
          (unsigned long long)header.sessionId,
          (unsigned long)header.messageId,
          (unsigned long)session.core.inFlightPage.hardDeadlineAtMs,
          (unsigned long)nowMs);
    } else {
      LOGW(
          "RTR_PAGE_ACK_INVALID deviceId=%lu commandId=%s state=%s sessionId=%llu messageId=%lu",
          (unsigned long)rx.deviceId,
          session.commandId[0] ? session.commandId : "-",
          pendingWakeStateLabel(session.core.state),
          (unsigned long long)header.sessionId,
          (unsigned long)header.messageId);
    }
    return false;
  }
  if (!ack.accepted || !ack.sessionModeActive) {
    setPendingWakeReason(
        session,
        rtrv1::REASON_PAGE_ACK_INVALID,
        rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_ACK_INVALID));
    failPendingWakeSession(
        session,
        rtrv1::REASON_PAGE_ACK_INVALID,
        rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_ACK_INVALID));
    return true;
  }
  rtrwake::markPageAcked(&session.core);
  if (ackWithinGrace) {
    LOGI(
        "RTR_PAGE_ACK_ACCEPTED_WITHIN_GRACE deviceId=%lu commandId=%s sessionId=%llu messageId=%lu retryAtMs=%lu",
        (unsigned long)rx.deviceId,
        session.commandId[0] ? session.commandId : "-",
        (unsigned long long)header.sessionId,
        (unsigned long)header.messageId,
        (unsigned long)session.core.scheduledRetry.retryAtMs);
    if (session.core.scheduledRetry.pending) {
      LOGI(
          "RTR_PAGE_RETRY_CANCELLED_BY_ACK deviceId=%lu commandId=%s sessionId=%llu messageId=%lu",
          (unsigned long)rx.deviceId,
          session.commandId[0] ? session.commandId : "-",
          (unsigned long long)header.sessionId,
          (unsigned long)header.messageId);
    }
  }
  rtrdiag::noteAckMatched(&lastPageDiag, ackWithinGrace);
  syncLastPageDiagFromSession(session);
  rtrdiag::notePageOutcome(&lastPageDiag, "ack_rx");
  transitionPendingWakeState(session, rtrwake::State::PAGE_ACKED, "page_ack_ok");
  publishFenceTransportState(session.core.deviceId, "page_acked");
  appendPropertyCommandEvent(
      activeSimpleCommand.propertyId,
      activeSimpleCommand.commandId,
      "rtr_page_ack",
      nullptr,
      nullptr);
  LOGI(
      "RTR_PAGE_ACK_RX deviceId=%lu commandId=%s sessionId=%llu messageId=%lu suggestedRxWindowMs=%u wakeLockSec=%lu",
      (unsigned long)rx.deviceId,
      session.commandId[0] ? session.commandId : "-",
      (unsigned long long)header.sessionId,
      (unsigned long)header.messageId,
      (unsigned)ack.suggestedRxWindowMs,
      (unsigned long)ack.wakeLockUntilSec);
  return true;
}

static bool waitForRtrPageAck(
    uint32_t deviceId,
    uint64_t sessionId,
    uint32_t messageId,
    uint32_t timeoutMs,
    rtrv1::PageAckBody* outBody) {
  const uint32_t startedAt = millis();
  while ((uint32_t)(millis() - startedAt) < timeoutMs) {
    LoRaFrame rx;
    if (!lora.receive(rx)) {
      delay(10);
      continue;
    }
    if (rx.deviceId != deviceId) {
      tryHandleWakePageImmediatelyAfterAcceptedUplink(rx, lora.lastAcceptedRxAtMs());
      enqueueAcceptedUplink(rx);
      continue;
    }
    if (decodeRtrPageAckFrame(rx, sessionId, messageId, outBody)) return true;
    tryHandleWakePageImmediatelyAfterAcceptedUplink(rx, lora.lastAcceptedRxAtMs());
    enqueueAcceptedUplink(rx);
  }
  return false;
}

static bool sendRtrPageForCommand(
    uint32_t deviceId,
    uint64_t scopeId,
    MsgType commandType,
    uint16_t estimatedFragments,
    uint64_t logicalMessageId,
    uint32_t entropy,
    const char* commandId,
    const char** reason) {
  const uint64_t sessionId =
      rtrv1::makeSessionId(logicalMessageId, deviceId, entropy);
  const uint32_t messageId = static_cast<uint32_t>(entropy ^ deviceId ^ (uint32_t)commandType);

  rtrv1::Header header{};
  header.version = rtrv1::PROTOCOL_VERSION;
  header.trafficClass = rtrv1::TRAFFIC_CLASS_P0;
  header.innerMsgType = rtrv1::RTR_PAGE;
  header.flags = rtrv1::FLAG_ACK_REQUIRED | rtrv1::FLAG_PAGE | rtrv1::FLAG_WAKE_LOCK;
  header.sessionId = sessionId;
  header.messageId = messageId;
  header.sourceId = 0;
  header.finalDestId = deviceId;
  header.nextHopId = deviceId;
  header.fragmentIndex = 0;
  header.fragmentTotal = 1;
  header.hopCount = 0;
  header.ttl = rtrv1::DEFAULT_TTL;

  rtrv1::PageBody body{};
  body.commandType = static_cast<uint8_t>(commandType);
  body.priority = rtrv1::TRAFFIC_CLASS_P1;
  body.estimatedFragments = estimatedFragments;
  body.sessionTimeoutSec = rtrv1::SESSION_CACHE_TTL_SEC;
  body.wakeLockSec = rtrv1::SESSION_WAKE_LOCK_MS / 1000UL;
  body.routeId = 0;

  uint8_t payload[sizeof(rtrv1::Header) + sizeof(rtrv1::PageBody)]{};
  const size_t payloadLen = rtrv1::encodeFrame(header, body, payload, sizeof(payload));
  if (payloadLen == 0) {
    if (reason) *reason = "page_encode_failed";
    return false;
  }

  publishFenceTransportState(deviceId, "paging");
  LOGI(
      "RTR_PAGE_PLAN deviceId=%lu commandId=%s sessionId=%llu messageId=%lu commandType=%u estimatedFragments=%u",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      (unsigned long long)sessionId,
      (unsigned long)messageId,
      (unsigned)commandType,
      (unsigned)estimatedFragments);
  if (!sendLoRaBinaryFrame(
          deviceId,
          MsgType::RTR_CONTROL,
          scopeId,
          payload,
          payloadLen,
          reason,
          MatrixLoRaTxReason::RtrPage,
          "sendPagedFenceCommand",
          nullptr,
          commandId)) {
    activeSimpleCommand.lastReasonCode = rtrv1::REASON_PAGE_REJECTED;
    return false;
  }
  appendPropertyCommandEvent(
      activeSimpleCommand.propertyId,
      activeSimpleCommand.commandId,
      "rtr_page_sent",
      nullptr,
      nullptr);
  markFenceCommandDispatchingBegin();
  publishFenceTransportState(deviceId, "awaiting_page_ack");
  LOGI(
      "RTR_PAGE_TX_OK deviceId=%lu commandId=%s sessionId=%llu messageId=%lu",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      (unsigned long long)sessionId,
      (unsigned long)messageId);

  rtrv1::PageAckBody ack{};
  if (!waitForRtrPageAck(deviceId, sessionId, messageId, rtrv1::PAGE_ACK_TIMEOUT_MS, &ack)) {
    if (reason) *reason = rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_TIMEOUT);
    activeSimpleCommand.lastReasonCode = rtrv1::REASON_PAGE_TIMEOUT;
    publishFenceTransportState(
        deviceId,
        "failed",
        rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_TIMEOUT),
        rtrv1::REASON_PAGE_TIMEOUT,
        true,
        false);
    return false;
  }
  if (!ack.accepted || !ack.sessionModeActive) {
    if (reason) *reason = rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_REJECTED);
    activeSimpleCommand.lastReasonCode = rtrv1::REASON_PAGE_REJECTED;
    publishFenceTransportState(
        deviceId,
        "failed",
        rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_REJECTED),
        rtrv1::REASON_PAGE_REJECTED,
        true,
        false);
    return false;
  }
  appendPropertyCommandEvent(
      activeSimpleCommand.propertyId,
      activeSimpleCommand.commandId,
      "rtr_page_ack",
      nullptr,
      nullptr);
  LOGI(
      "RTR_PAGE_ACK_RX deviceId=%lu commandId=%s sessionId=%llu messageId=%lu suggestedRxWindowMs=%u wakeLockSec=%lu",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      (unsigned long long)sessionId,
      (unsigned long)messageId,
      (unsigned)ack.suggestedRxWindowMs,
      (unsigned long)ack.wakeLockUntilSec);
  publishFenceTransportState(deviceId, "page_acked");
  return true;
}

static bool decodeRpv2ResponseFrame(
    const LoRaFrame& rx,
    uint64_t radioCommandId,
    uint32_t sessionNonce,
    Rpv2AwaitedResponse* out) {
  if (!out || rx.payloadLen < sizeof(rpv2::Header)) return false;
  rpv2::Header header{};
  if (!rpv2::decodeHeader(rx.payload, rx.payloadLen, &header)) return false;
  if (header.radioCommandId != radioCommandId || header.sessionNonce != sessionNonce) return false;

  *out = Rpv2AwaitedResponse{};
  out->received = true;
  switch (header.msgType) {
    case rpv2::FENCE_ACK: {
      rpv2::AckBody body{};
      if (!rpv2::decodeFixedBodyFrame(rpv2::FENCE_ACK, rx.payload, rx.payloadLen, &header, &body)) return false;
      out->ack = true;
      out->fragmentIndex = body.ackedFragmentIndex;
      out->nextExpectedFragment = body.nextExpectedFragment;
      out->acceptedPoints = body.acceptedPoints;
      out->observedCrc32 = body.observedCrc32;
      return true;
    }
    case rpv2::FENCE_NACK: {
      rpv2::NackBody body{};
      if (!rpv2::decodeFixedBodyFrame(rpv2::FENCE_NACK, rx.payload, rx.payloadLen, &header, &body)) return false;
      out->nack = true;
      out->fragmentIndex = body.nackFragmentIndex;
      out->nextExpectedFragment = body.nextExpectedFragment;
      out->reasonCode = body.reasonCode;
      return true;
    }
    case rpv2::FENCE_APPLY_STATUS: {
      rpv2::ApplyStatusBody body{};
      if (!rpv2::decodeFixedBodyFrame(rpv2::FENCE_APPLY_STATUS, rx.payload, rx.payloadLen, &header, &body)) return false;
      out->applyStatus = true;
      out->reasonCode = body.reasonCode;
      out->observedCrc32 = body.activeCrc32;
      out->activePoints = body.activePoints;
      out->ack = body.applyStatus == 1;
      out->nack = body.applyStatus == 0;
      return true;
    }
    default:
      return false;
  }
}

static bool waitForRpv2Response(
    uint32_t deviceId,
    uint64_t radioCommandId,
    uint32_t sessionNonce,
    uint32_t timeoutMs,
    Rpv2AwaitedResponse* out,
    const char* stage = nullptr,
    const char* commandId = nullptr) {
  const uint32_t startedAt = millis();
  uint32_t lastHeartbeatAt = startedAt;
  while ((uint32_t)(millis() - startedAt) < timeoutMs) {
    feedWatchdogIfEnabled();
    const uint32_t nowMs = millis();
    if ((uint32_t)(nowMs - lastHeartbeatAt) >= 250UL) {
      LOGI(
          "RPV2_WAIT_HEARTBEAT deviceId=%lu commandId=%s stage=%s elapsedMs=%lu timeoutMs=%lu",
          (unsigned long)deviceId,
          commandId && commandId[0] ? commandId : "-",
          stage ? stage : "-",
          (unsigned long)(nowMs - startedAt),
          (unsigned long)timeoutMs);
      lastHeartbeatAt = nowMs;
    }
    LoRaFrame rx;
    if (!lora.receive(rx)) {
      delay(1);
      continue;
    }
    if (rx.deviceId != deviceId) {
      tryHandleWakePageImmediatelyAfterAcceptedUplink(rx, lora.lastAcceptedRxAtMs());
      enqueueAcceptedUplink(rx);
      delay(1);
      continue;
    }
    if (decodeRpv2ResponseFrame(rx, radioCommandId, sessionNonce, out)) return true;
    tryHandleWakePageImmediatelyAfterAcceptedUplink(rx, lora.lastAcceptedRxAtMs());
    enqueueAcceptedUplink(rx);
    delay(1);
  }
  return false;
}

struct FencePlannerMeasureUserData {
  uint64_t scopeId = 0;
};

static bool measureFencePlannerCandidate(
    const rpv2::EncodedPoint* points,
    uint16_t startPointIndex,
    uint16_t pointCount,
    const rpv2fenceplanner::PlannerContext& ctx,
    rpv2fenceplanner::MeasuredCandidate* measured,
    void* userData) {
  if (!points || !measured || pointCount == 0) return false;
  FencePlannerMeasureUserData* measureData =
      static_cast<FencePlannerMeasureUserData*>(userData);
  uint8_t payload[128]{};
  rpv2::Header header{};
  header.protocolVersion = rpv2::PROTOCOL_VERSION;
  header.msgType = rpv2::FENCE_POINTS;
  header.flags = rpv2::FLAG_ACK_REQUIRED | rpv2::FLAG_FROM_MATRIX;
  header.headerLen = sizeof(rpv2::Header);
  header.radioCommandId = ctx.radioCommandId;
  header.sessionNonce = ctx.sessionNonce;
  header.fragmentIndex = static_cast<uint16_t>(0);
  header.fragmentTotal = 1;
  rpv2::FencePointsPrefix prefix{};
  prefix.startPointIndex = startPointIndex;
  prefix.pointCount = static_cast<uint8_t>(pointCount);
  const size_t plainSize = rpv2::encodePointsFrame(
      header,
      prefix,
      reinterpret_cast<const rpv2::PointLatLonE7*>(points + startPointIndex),
      prefix.pointCount,
      payload,
      sizeof(payload));
  measured->encodeOk = plainSize > 0 && plainSize <= cfg::LORA_MAX_PAYLOAD_BYTES;
  measured->plainFrameSize = static_cast<uint16_t>(plainSize);
  if (!measured->encodeOk) {
    measured->reason = "points_encode_failed";
    return false;
  }
  LoRaFrame tx{};
  tx.deviceId = ctx.deviceId;
  tx.scopeId = (measureData && measureData->scopeId != 0) ? measureData->scopeId : bindingScopeIdValue();
  tx.msgType = MsgType::SET_FENCE;
  tx.seq = 1;
  tx.timestamp = 0;
  memset(tx.nonce, 0xA5, sizeof(tx.nonce));
  tx.payloadLen = static_cast<uint8_t>(plainSize);
  memcpy(tx.payload, payload, plainSize);
  SecureWireMetrics metrics;
  measured->measurementOk = buildExactSecureWireMetrics(tx, &metrics, nullptr, 0);
  measured->secureWireSize = metrics.wireLenFinal;
  measured->wireLenFinal = metrics.wireLenFinal;
  measured->reason = metrics.reason;
  return measured->measurementOk;
}

static void logFencePlannerEvent(const rpv2fenceplanner::LogEvent& event, void*) {
  if (!event.eventType) return;
  if (strcmp(event.eventType, "RPV2_PLAN_ENTER") == 0) {
    LOGI(
        "RPV2_PLAN_ENTER deviceId=%lu commandId=%s totalPoints=%u maxFrame=%u source=%s",
        (unsigned long)event.deviceId,
        event.commandId && event.commandId[0] ? event.commandId : "-",
        (unsigned)event.totalPoints,
        (unsigned)event.limit,
        event.source && event.source[0] ? event.source : "unknown");
    noteSetFenceCommandProgress("planner_enter");
    return;
  }
  if (strcmp(event.eventType, "RPV2_PLANNER_REV") == 0) {
    LOGI(
        "RPV2_PLANNER_REV rev=%s gitShort=%s",
        event.plannerRevision && event.plannerRevision[0] ? event.plannerRevision : "canonical_fence_planner_v1",
        event.gitShortSha && event.gitShortSha[0] ? event.gitShortSha : "unknown");
    return;
  }
  if (strcmp(event.eventType, "RPV2_PLAN_CANDIDATE_EVAL") == 0) {
    LOGI(
        "RPV2_PLAN_CANDIDATE_EVAL deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=%u startPointIndex=%u endPointIndex=%u pointCount=%u plainFrameSize=%u secureWireSize=%u wireLenFinal=%u limit=%u measurementOk=%u fitsLimit=%u classification=%s",
        (unsigned long)event.deviceId,
        event.commandId && event.commandId[0] ? event.commandId : "-",
        (unsigned long long)event.radioCommandId,
        (unsigned)event.fragmentIndex,
        (unsigned)event.startPointIndex,
        (unsigned)event.endPointIndex,
        (unsigned)event.pointCount,
        (unsigned)event.plainFrameSize,
        (unsigned)event.secureWireSize,
        (unsigned)event.wireLenFinal,
        (unsigned)event.limit,
        event.measurementOk ? 1U : 0U,
        event.fitsLimit ? 1U : 0U,
        event.classification && event.classification[0] ? event.classification : "-");
    return;
  }
  if (strcmp(event.eventType, "RPV2_PLAN_CHUNK_REJECT") == 0) {
    LOGW(
        "RPV2_PLAN_CHUNK_REJECT deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=%u startPointIndex=%u pointCount=%u reason=%s wireLenFinal=%u limit=%u classification=%s",
        (unsigned long)event.deviceId,
        event.commandId && event.commandId[0] ? event.commandId : "-",
        (unsigned long long)event.radioCommandId,
        (unsigned)event.fragmentIndex,
        (unsigned)event.startPointIndex,
        (unsigned)event.pointCount,
        event.reason && event.reason[0] ? event.reason : "-",
        (unsigned)event.wireLenFinal,
        (unsigned)event.limit,
        event.classification && event.classification[0] ? event.classification : "-");
    return;
  }
  if (strcmp(event.eventType, "RPV2_PLAN_CHUNK_FIT") == 0) {
    LOGI(
        "RPV2_PLAN_CHUNK_FIT deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=%u startPointIndex=%u pointCount=%u plainFrameSize=%u wireLenFinal=%u limit=%u",
        (unsigned long)event.deviceId,
        event.commandId && event.commandId[0] ? event.commandId : "-",
        (unsigned long long)event.radioCommandId,
        (unsigned)event.fragmentIndex,
        (unsigned)event.startPointIndex,
        (unsigned)event.pointCount,
        (unsigned)event.plainFrameSize,
        (unsigned)event.wireLenFinal,
        (unsigned)event.limit);
    return;
  }
  if (strcmp(event.eventType, "RPV2_PLAN_FAILED_TERMINAL") == 0) {
    LOGW(
        "RPV2_PLAN_FAILED_TERMINAL deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=%u startPointIndex=%u pointCount=%u reason=%s wireLenFinal=%u limit=%u classification=%s",
        (unsigned long)event.deviceId,
        event.commandId && event.commandId[0] ? event.commandId : "-",
        (unsigned long long)event.radioCommandId,
        (unsigned)event.fragmentIndex,
        (unsigned)event.startPointIndex,
        (unsigned)event.pointCount,
        event.reason && event.reason[0] ? event.reason : "-",
        (unsigned)event.wireLenFinal,
        (unsigned)event.limit,
        event.classification && event.classification[0] ? event.classification : "-");
    return;
  }
  if (strcmp(event.eventType, "RPV2_PLAN_FINAL") == 0) {
    LOGI(
        "RPV2_PLAN_FINAL deviceId=%lu commandId=%s planReady=%u chunkCount=%u totalPoints=%u minWireLen=%u maxWireLen=%u reason=%s",
        (unsigned long)event.deviceId,
        event.commandId && event.commandId[0] ? event.commandId : "-",
        event.planReady ? 1U : 0U,
        (unsigned)event.chunkCount,
        (unsigned)event.totalPoints,
        (unsigned)event.plainFrameSize,
        (unsigned)event.wireLenFinal,
        event.reason && event.reason[0] ? event.reason : "-");
    noteSetFenceCommandProgress(event.planReady ? "planner_final_ready" : "planner_final_failed");
  }
}

static bool buildFenceRpv2Plan(
    const JsonArrayConst& points,
    uint64_t scopeId,
    uint32_t deviceId,
    uint64_t radioCommandId,
    uint32_t sessionNonce,
    const char* commandId,
    const char* source,
    Rpv2FenceChunkPlan* plan,
    const char** reason) {
  if (!plan) {
    if (reason) *reason = "plan_null";
    return false;
  }
  const uint16_t totalPoints = static_cast<uint16_t>(points.size());
  rpv2::EncodedPoint encodedPoints[rpv2::MAX_FENCE_POINTS]{};
  for (uint16_t i = 0; i < totalPoints; ++i) {
    double lat = 0.0;
    double lon = 0.0;
    if (!readPointPair(points[i].as<JsonArrayConst>(), lat, lon)) {
      if (reason) *reason = "invalid_point_value";
      return false;
    }
    encodedPoints[i].latE7 = coordinateToE7(lat);
    encodedPoints[i].lonE7 = coordinateToE7(lon);
  }
  const buildinfo::BuildInfo build = buildinfo::current();
  rpv2fenceplanner::PlannerContext ctx{};
  ctx.deviceId = deviceId;
  ctx.scopeId = scopeId == 0 ? bindingScopeIdValue() : scopeId;
  ctx.radioCommandId = radioCommandId;
  ctx.sessionNonce = sessionNonce;
  ctx.commandId = commandId;
  ctx.source = source;
  ctx.plannerRevision = "canonical_fence_planner_v1";
  ctx.gitShortSha = build.gitShortSha;
  ctx.maxWireBytes = rpv2::MAX_LORA_FRAME_BYTES;
  FencePlannerMeasureUserData measureUserData{};
  measureUserData.scopeId = ctx.scopeId;
  const bool ok = rpv2fenceplanner::buildFenceRpv2PlanStrict(
      encodedPoints,
      totalPoints,
      ctx,
      plan,
      rpv2::MAX_FENCE_POINTS,
      measureFencePlannerCandidate,
      &measureUserData,
      logFencePlannerEvent,
      nullptr);
  if (!ok && reason) {
    *reason = plan->reasonLabel[0] ? plan->reasonLabel : "plan_failed";
  }
  return ok;
}

static bool executeFenceCommandRpv2Plan(
    uint32_t deviceId,
    uint64_t scopeId,
    uint64_t radioCommandId,
    uint32_t sessionNonce,
    const char* commandId,
    const Rpv2FenceChunkPlan& plan,
    const char** reason) {
  uint8_t framePayload[128]{};
  rpv2::Header header{};
  header.protocolVersion = rpv2::PROTOCOL_VERSION;
  header.flags = rpv2::FLAG_ACK_REQUIRED | rpv2::FLAG_FROM_MATRIX;
  header.headerLen = sizeof(rpv2::Header);
  header.radioCommandId = radioCommandId;
  header.sessionNonce = sessionNonce;

  rpv2::FenceBeginBody begin{};
  begin.totalPoints = plan.totalPoints;
  begin.totalChunks = plan.totalChunks;
  begin.fenceCrc32 = plan.fenceCrc32;
  begin.fenceVersion = static_cast<uint32_t>(millis() / 1000U);
  begin.coordEncoding = rpv2::COORD_ENCODING_LATE7_LONE7;
  begin.pointStrideBytes = rpv2::POINT_STRIDE_BYTES;
  header.msgType = rpv2::FENCE_BEGIN;
  header.fragmentIndex = 0;
  header.fragmentTotal = plan.totalChunks;
  const size_t beginLen = rpv2::encodeFrame(header, begin, framePayload, sizeof(framePayload));
  LoRaFrame beginTx;
  beginTx.deviceId = deviceId;
  beginTx.scopeId = scopeId == 0 ? bindingScopeIdValue() : scopeId;
  beginTx.msgType = MsgType::SET_FENCE;
  beginTx.seq = 1;
  beginTx.timestamp = 0;
  memset(beginTx.nonce, 0xA5, sizeof(beginTx.nonce));
  beginTx.payloadLen = static_cast<uint8_t>(beginLen);
  memcpy(beginTx.payload, framePayload, beginLen);
  SecureWireMetrics beginMetrics;
  buildExactSecureWireMetrics(beginTx, &beginMetrics, nullptr, 0);
  LOGI(
      "RPV2_BEGIN_SIZE_EVAL deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=0 pointCount=%u plainPayloadLen=%u packedLen=%u cipherPayloadLen=%u wireLenFinal=%u limit=128",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      (unsigned long long)radioCommandId,
      (unsigned)plan.totalPoints,
      (unsigned)beginMetrics.plainPayloadLen,
      (unsigned)beginMetrics.packedLen,
      (unsigned)beginMetrics.cipherPayloadLen,
      (unsigned)beginMetrics.wireLenFinal);
  publishFenceTransportState(deviceId, "awaiting_begin_ack");
  logRpv2StageTransition(deviceId, commandId, "page_acked", "begin_tx");
  LOGI(
      "RPV2_WAIT_ACK_BEGIN deviceId=%lu commandId=%s radioCommandId=%llu retryCount=%u",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      (unsigned long long)radioCommandId,
      (unsigned)activeSimpleCommand.retryCount);
  if (beginLen == 0 || !sendLoRaBinaryFrame(
          deviceId,
          MsgType::SET_FENCE,
          scopeId,
          framePayload,
          beginLen,
          reason,
          MatrixLoRaTxReason::Rpv2Begin,
          "sendFenceCommandRpv2Session.begin",
          nullptr,
          commandId)) {
    activeSimpleCommand.lastReasonCode =
        reason ? rpv2ReasonCodeFromLabel(*reason) : rpv2::REASON_NONE;
    return false;
  }
  appendPropertyCommandEvent(
      activeSimpleCommand.propertyId,
      activeSimpleCommand.commandId,
      "rpv2_begin_sent",
      nullptr,
      nullptr);
  LOGI(
      "RPV2_BEGIN_TX_OK deviceId=%lu commandId=%s radioCommandId=%llu retryCount=%u",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      (unsigned long long)radioCommandId,
      (unsigned)activeSimpleCommand.retryCount);
  feedWatchdogIfEnabled();

  Rpv2AwaitedResponse response;
  if (!waitForRpv2Response(
          deviceId,
          radioCommandId,
          sessionNonce,
          rpv2::BEGIN_ACK_TIMEOUT_MS,
          &response,
          "begin_ack",
          commandId)) {
    if (reason) *reason = "begin_timeout";
    activeSimpleCommand.lastReasonCode = rpv2::REASON_BEGIN_TIMEOUT;
    publishFenceTransportState(deviceId, "failed", "begin_timeout", rpv2::REASON_BEGIN_TIMEOUT, true, false);
    return false;
  }
  if (!response.ack || response.applyStatus || response.nack) {
    const uint16_t code = response.reasonCode ? response.reasonCode : rpv2::REASON_BEGIN_REJECTED;
    if (reason) *reason = rpv2::reasonCodeLabel(code);
    activeSimpleCommand.lastReasonCode = code;
    LOGW(
        "RPV2_RX_NACK deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=%u reasonCode=%u",
        (unsigned long)deviceId,
        commandId && commandId[0] ? commandId : "-",
        (unsigned long long)radioCommandId,
        (unsigned)response.fragmentIndex,
        (unsigned)code);
    publishFenceTransportState(deviceId, "failed", *reason, code, true, false);
    return false;
  }
  appendPropertyCommandEvent(
      activeSimpleCommand.propertyId,
      activeSimpleCommand.commandId,
      "rpv2_begin_ack",
      nullptr,
      nullptr);
  feedWatchdogIfEnabled();
  LOGI(
      "RPV2_RX_ACK deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=%u acceptedPoints=%u",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      (unsigned long long)radioCommandId,
      (unsigned)response.fragmentIndex,
      (unsigned)response.acceptedPoints);

  for (uint16_t i = 0; i < plan.totalChunks; ++i) {
    const Rpv2FenceChunkPlanItem& item = plan.items[i];
    header.msgType = rpv2::FENCE_POINTS;
    header.fragmentIndex = item.fragmentIndex;
    header.fragmentTotal = plan.totalChunks;
    logRpv2StageTransition(deviceId, commandId, "begin_acked", "points_tx");
    rpv2::FencePointsPrefix prefix{};
    prefix.startPointIndex = item.startPointIndex;
    prefix.pointCount = item.pointCount;
    const size_t pointsLen = rpv2::encodePointsFrame(
        header,
        prefix,
        reinterpret_cast<const rpv2::PointLatLonE7*>(plan.points + item.startPointIndex),
        item.pointCount,
        framePayload,
        sizeof(framePayload));
    publishFenceTransportState(deviceId, "awaiting_points_ack");
    LOGI(
        "RPV2_WAIT_ACK_POINTS deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=%u retryCount=%u",
        (unsigned long)deviceId,
        commandId && commandId[0] ? commandId : "-",
        (unsigned long long)radioCommandId,
        (unsigned)item.fragmentIndex,
        (unsigned)activeSimpleCommand.retryCount);
    if (pointsLen == 0 || !sendLoRaBinaryFrame(
            deviceId,
            MsgType::SET_FENCE,
            scopeId,
            framePayload,
            pointsLen,
            reason,
            MatrixLoRaTxReason::Rpv2Points,
            "sendFenceCommandRpv2Session.points",
            nullptr,
            commandId)) {
      activeSimpleCommand.lastReasonCode =
          reason ? rpv2ReasonCodeFromLabel(*reason) : rpv2::REASON_NONE;
      return false;
    }
    appendPropertyCommandEvent(
        activeSimpleCommand.propertyId,
        activeSimpleCommand.commandId,
        "rpv2_points_sent",
        nullptr,
        nullptr);
    LOGI(
        "RPV2_POINTS_TX_OK deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=%u pointCount=%u",
        (unsigned long)deviceId,
        commandId && commandId[0] ? commandId : "-",
        (unsigned long long)radioCommandId,
        (unsigned)item.fragmentIndex,
        (unsigned)item.pointCount);
    feedWatchdogIfEnabled();
    if (!waitForRpv2Response(
            deviceId,
            radioCommandId,
            sessionNonce,
            rpv2::POINTS_ACK_TIMEOUT_MS,
            &response,
            "points_ack",
            commandId)) {
      if (reason) *reason = "points_timeout";
      activeSimpleCommand.lastReasonCode = rpv2::REASON_POINTS_TIMEOUT;
      publishFenceTransportState(deviceId, "failed", "points_timeout", rpv2::REASON_POINTS_TIMEOUT, true, false);
      return false;
    }
    if (!response.ack || response.nack || response.applyStatus) {
      const uint16_t code = response.reasonCode ? response.reasonCode : rpv2::REASON_POINTS_OUT_OF_ORDER;
      if (reason) *reason = rpv2::reasonCodeLabel(code);
      activeSimpleCommand.lastReasonCode = code;
      LOGW(
          "RPV2_RX_NACK deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=%u reasonCode=%u",
          (unsigned long)deviceId,
          commandId && commandId[0] ? commandId : "-",
          (unsigned long long)radioCommandId,
          (unsigned)response.fragmentIndex,
          (unsigned)code);
      publishFenceTransportState(deviceId, "failed", *reason, code, true, false);
      return false;
    }
    appendPropertyCommandEvent(
        activeSimpleCommand.propertyId,
        activeSimpleCommand.commandId,
        "rpv2_points_ack",
        nullptr,
        nullptr);
    feedWatchdogIfEnabled();
    LOGI(
        "RPV2_RX_ACK deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=%u acceptedPoints=%u",
        (unsigned long)deviceId,
        commandId && commandId[0] ? commandId : "-",
        (unsigned long long)radioCommandId,
        (unsigned)response.fragmentIndex,
        (unsigned)response.acceptedPoints);
    delay(rpv2::INTER_FRAME_GAP_MS);
    feedWatchdogIfEnabled();
  }

  rpv2::FenceCommitBody commit{};
  commit.totalPoints = plan.totalPoints;
  commit.totalChunks = plan.totalChunks;
  commit.fenceCrc32 = plan.fenceCrc32;
  commit.stagedCrc32Expected = plan.fenceCrc32;
  commit.activateMode = 1;
  commit.requireApplyStatus = 1;
  commit.commitToken = sessionNonce ^ plan.fenceCrc32;
  header.msgType = rpv2::FENCE_COMMIT;
  header.fragmentIndex = 0;
  header.fragmentTotal = plan.totalChunks;
  const size_t commitLen = rpv2::encodeFrame(header, commit, framePayload, sizeof(framePayload));
  LoRaFrame commitTx;
  commitTx.deviceId = deviceId;
  commitTx.scopeId = scopeId == 0 ? bindingScopeIdValue() : scopeId;
  commitTx.msgType = MsgType::SET_FENCE;
  commitTx.seq = 1;
  commitTx.timestamp = 0;
  memset(commitTx.nonce, 0xA5, sizeof(commitTx.nonce));
  commitTx.payloadLen = static_cast<uint8_t>(commitLen);
  memcpy(commitTx.payload, framePayload, commitLen);
  SecureWireMetrics commitMetrics;
  buildExactSecureWireMetrics(commitTx, &commitMetrics, nullptr, 0);
  LOGI(
      "RPV2_COMMIT_SIZE_EVAL deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=0 pointCount=%u plainPayloadLen=%u packedLen=%u cipherPayloadLen=%u wireLenFinal=%u limit=128",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      (unsigned long long)radioCommandId,
      (unsigned)plan.totalPoints,
      (unsigned)commitMetrics.plainPayloadLen,
      (unsigned)commitMetrics.packedLen,
      (unsigned)commitMetrics.cipherPayloadLen,
      (unsigned)commitMetrics.wireLenFinal);
  publishFenceTransportState(deviceId, "awaiting_commit_ack");
  logRpv2StageTransition(deviceId, commandId, "points_acked", "commit_tx");
  LOGI(
      "RPV2_WAIT_ACK_COMMIT deviceId=%lu commandId=%s radioCommandId=%llu retryCount=%u",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      (unsigned long long)radioCommandId,
      (unsigned)activeSimpleCommand.retryCount);
  if (commitLen == 0 || !sendLoRaBinaryFrame(
          deviceId,
          MsgType::SET_FENCE,
          scopeId,
          framePayload,
          commitLen,
          reason,
          MatrixLoRaTxReason::Rpv2Commit,
          "sendFenceCommandRpv2Session.commit",
          nullptr,
          commandId)) {
    activeSimpleCommand.lastReasonCode =
        reason ? rpv2ReasonCodeFromLabel(*reason) : rpv2::REASON_NONE;
    return false;
  }
  appendPropertyCommandEvent(
      activeSimpleCommand.propertyId,
      activeSimpleCommand.commandId,
      "rpv2_commit_sent",
      nullptr,
      nullptr);
  LOGI(
      "RPV2_COMMIT_TX_OK deviceId=%lu commandId=%s radioCommandId=%llu",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      (unsigned long long)radioCommandId);
  feedWatchdogIfEnabled();
  if (!waitForRpv2Response(
          deviceId,
          radioCommandId,
          sessionNonce,
          rpv2::COMMIT_ACK_TIMEOUT_MS,
          &response,
          "commit_ack",
          commandId)) {
    if (reason) *reason = "commit_timeout";
    activeSimpleCommand.lastReasonCode = rpv2::REASON_COMMIT_TIMEOUT;
    publishFenceTransportState(deviceId, "failed", "commit_timeout", rpv2::REASON_COMMIT_TIMEOUT, true, false);
    return false;
  }
  if (!response.ack || response.nack || response.applyStatus) {
    const uint16_t code = response.reasonCode ? response.reasonCode : rpv2::REASON_COMMIT_REJECTED;
    if (reason) *reason = rpv2::reasonCodeLabel(code);
    activeSimpleCommand.lastReasonCode = code;
    LOGW(
        "RPV2_RX_NACK deviceId=%lu commandId=%s radioCommandId=%llu fragmentIndex=%u reasonCode=%u",
        (unsigned long)deviceId,
        commandId && commandId[0] ? commandId : "-",
        (unsigned long long)radioCommandId,
        (unsigned)response.fragmentIndex,
        (unsigned)code);
    publishFenceTransportState(deviceId, "failed", *reason, code, true, false);
    return false;
  }
  appendPropertyCommandEvent(
      activeSimpleCommand.propertyId,
      activeSimpleCommand.commandId,
      "rpv2_commit_ack",
      nullptr,
      nullptr);
  feedWatchdogIfEnabled();
  publishFenceTransportState(deviceId, "awaiting_apply_status");
  logRpv2StageTransition(deviceId, commandId, "commit_acked", "apply_status_wait");
  LOGI(
      "RPV2_WAIT_APPLY_STATUS deviceId=%lu commandId=%s radioCommandId=%llu retryCount=%u",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      (unsigned long long)radioCommandId,
      (unsigned)activeSimpleCommand.retryCount);
  if (!waitForRpv2Response(
          deviceId,
          radioCommandId,
          sessionNonce,
          rpv2::APPLY_STATUS_TIMEOUT_MS,
          &response,
          "apply_status",
          commandId)) {
    if (reason) *reason = "apply_timeout";
    activeSimpleCommand.lastReasonCode = rpv2::REASON_APPLY_FAILED;
    publishFenceTransportState(deviceId, "failed", "apply_timeout", rpv2::REASON_APPLY_FAILED, true, false);
    return false;
  }
  if (!response.applyStatus || !response.ack) {
    const uint16_t code = response.reasonCode ? response.reasonCode : rpv2::REASON_APPLY_FAILED;
    if (reason) *reason = rpv2::reasonCodeLabel(code);
    activeSimpleCommand.lastReasonCode = code;
    LOGW(
        "RPV2_RX_APPLY_STATUS deviceId=%lu commandId=%s radioCommandId=%llu apply=0 reasonCode=%u activePoints=%u",
        (unsigned long)deviceId,
        commandId && commandId[0] ? commandId : "-",
        (unsigned long long)radioCommandId,
        (unsigned)code,
        (unsigned)response.activePoints);
    publishFenceTransportState(deviceId, "failed", *reason, code, true, false);
    return false;
  }
  activeSimpleCommand.lastReasonCode = rpv2::REASON_NONE;
  LOGI(
      "RPV2_RX_APPLY_STATUS deviceId=%lu commandId=%s radioCommandId=%llu apply=1 reasonCode=0 activePoints=%u",
      (unsigned long)deviceId,
      commandId && commandId[0] ? commandId : "-",
      (unsigned long long)radioCommandId,
      (unsigned)response.activePoints);
  appendPropertyCommandEvent(
      activeSimpleCommand.propertyId,
      activeSimpleCommand.commandId,
      "rpv2_apply_status_ok",
      nullptr,
      nullptr);
  feedWatchdogIfEnabled();
  logRpv2StageTransition(deviceId, commandId, "apply_status_ok", "session_applied");
  publishFenceTransportState(deviceId, "applied", nullptr, rpv2::REASON_NONE, true, true);
  return true;
}

static bool sendFenceCommandRpv2Session(
    uint32_t deviceId,
    const JsonVariantConst payload,
    const char* commandId,
    const FencePointsResolution& pointsResolution,
    const char** reason) {
  uint64_t scopeId = parseScopeIdHex(payload["scope_id"]);
  if (scopeId == 0) scopeId = parseScopeIdHex(payload["property_scope_id"]);
  const uint64_t radioCommandId = rpv2::fnv1a64(commandId && commandId[0] ? commandId : "set_fence");
  const uint32_t sessionNonce = esp_random();
  Rpv2FenceChunkPlan plan;
  if (!buildFenceRpv2Plan(
          pointsResolution.points,
          scopeId,
          deviceId,
          radioCommandId,
          sessionNonce,
          commandId,
          "direct_session",
          &plan,
          reason)) {
    const rpv2fenceplanner::DispatchDecision decision =
        rpv2fenceplanner::decideDispatchAfterPlanning(plan);
    LOGW(
        "RPV2_PLAN_FAILED_TERMINAL deviceId=%lu commandId=%s radioCommandId=%llu reason=%s",
        (unsigned long)deviceId,
        commandId && commandId[0] ? commandId : "-",
        (unsigned long long)radioCommandId,
        reason && *reason ? *reason : "plan_failed");
    activeSimpleCommand.lastReasonCode = decision.reasonCode;
    return false;
  }
  if (!sendRtrPageForCommand(
          deviceId,
          scopeId,
          MsgType::SET_FENCE,
          static_cast<uint16_t>(plan.totalChunks + 2),
          radioCommandId,
          sessionNonce,
          commandId,
          reason)) {
    return false;
  }
  return executeFenceCommandRpv2Plan(
      deviceId,
      scopeId,
      radioCommandId,
      sessionNonce,
      commandId,
      plan,
      reason);
}

static bool prepareFenceWakeSession(
    uint32_t deviceId,
    const JsonVariantConst payload,
    const char* commandId,
    const FencePointsResolution& pointsResolution,
    const char** reason) {
  const int existingIdx = findPendingWakeSessionByDeviceId(deviceId);
  PendingWakeSession* session = existingIdx >= 0
      ? &pendingWakeSessions[existingIdx]
      : allocatePendingWakeSession();
  if (!session) {
    if (reason) *reason = "pending_wake_session_full";
    return false;
  }

  uint64_t scopeId = parseScopeIdHex(payload["scope_id"]);
  if (scopeId == 0) scopeId = parseScopeIdHex(payload["property_scope_id"]);
  const uint64_t radioCommandId =
      rpv2::fnv1a64(commandId && commandId[0] ? commandId : "set_fence");
  const uint32_t sessionNonce = esp_random();
  Rpv2FenceChunkPlan plan;
  if (!buildFenceRpv2Plan(
          pointsResolution.points,
          scopeId,
          deviceId,
          radioCommandId,
          sessionNonce,
          commandId,
          "cloud_queue",
          &plan,
          reason)) {
    const rpv2fenceplanner::DispatchDecision decision =
        rpv2fenceplanner::decideDispatchAfterPlanning(plan);
    LOGW(
        "RPV2_PLAN_FAILED_TERMINAL deviceId=%lu commandId=%s radioCommandId=%llu reason=%s",
        (unsigned long)deviceId,
        commandId && commandId[0] ? commandId : "-",
        (unsigned long long)radioCommandId,
        reason && *reason ? *reason : "plan_failed");
    activeSimpleCommand.lastReasonCode = decision.reasonCode;
    return false;
  }

  const uint32_t nowMs = millis();
  const rtrwake::Presence* presence = findDevicePresence(deviceId);
  const bool recentHint =
      presence && presence->valid &&
      presence->lastSeenAtMs != 0 &&
      (uint32_t)(nowMs - presence->lastSeenAtMs) <= kRecentWakeHintMs;

  if (existingIdx >= 0) {
    LOGI(
        "RTR_WAKE_SESSION_REUSED commandId=%s deviceId=%lu previousState=%s",
        commandId && commandId[0] ? commandId : "-",
        (unsigned long)deviceId,
        pendingWakeStateLabel(session->core.state));
  }
  *session = PendingWakeSession{};
  session->core.active = true;
  session->core.deviceId = deviceId;
  session->core.pageSessionId = rtrv1::makeSessionId(radioCommandId, deviceId, sessionNonce);
  session->core.pageMessageId =
      static_cast<uint32_t>(sessionNonce ^ deviceId ^ (uint32_t)MsgType::SET_FENCE);
  session->core.maxCampaigns = rtrv1::MAX_PAGE_CAMPAIGNS;
  session->core.createdAtMs = nowMs;
  session->core.lastUplinkAtMs = presence && presence->valid ? presence->lastSeenAtMs : 0;
  session->core.predictedWakeAtMs =
      (presence && presence->valid && presence->estimatedCycleMs != 0)
          ? presence->lastSeenAtMs + presence->estimatedCycleMs
          : 0;
  session->core.nextPageAttemptAtMs = recentHint ? nowMs : 0;
  session->core.state = recentHint
      ? rtrwake::State::PAGING_READY_TO_SEND
      : rtrwake::State::PAGING_WAITING_UPLINK;
  copyStringToBuffer(session->commandId, sizeof(session->commandId), commandId);
  session->scopeId = scopeId == 0 ? bindingScopeIdValue() : scopeId;
  session->commandType = MsgType::SET_FENCE;
  session->radioCommandId = radioCommandId;
  session->sessionNonce = sessionNonce;
  session->estimatedFragments = static_cast<uint16_t>(plan.totalChunks + 2);
  session->rpv2PlanReady = true;
  session->plan = plan;
  rtrdiag::notePageOutcome(&lastPageDiag, "none");
  syncLastPageDiagFromSession(*session);
  setPendingWakeReason(*session, rtrv1::REASON_NONE, "");

  publishFenceTransportState(
      deviceId,
      recentHint ? "paging_ready" : "paging_waiting_uplink");
  LOGI(
      "RTR_WAKE_SESSION_CREATED commandId=%s deviceId=%lu state=%s estimatedFragments=%u predictedWakeAtMs=%lu lastUplinkAtMs=%lu",
      session->commandId[0] ? session->commandId : "-",
      (unsigned long)deviceId,
      pendingWakeStateLabel(session->core.state),
      (unsigned)session->estimatedFragments,
      (unsigned long)session->core.predictedWakeAtMs,
      (unsigned long)session->core.lastUplinkAtMs);
  if (!recentHint) {
    LOGI(
        "RTR_PAGE_DEFERRED_WAITING_UPLINK commandId=%s deviceId=%lu campaignCount=%u",
        session->commandId[0] ? session->commandId : "-",
        (unsigned long)deviceId,
        (unsigned)session->core.campaignCount);
  }
  return true;
}

static bool processPendingWakeSessionStep(uint8_t idx, PendingWakeSession& session, uint32_t nowMs) {
    switch (session.core.state) {
      case rtrwake::State::PAGING_WAITING_UPLINK:
        if (session.core.createdAtMs != 0 &&
            (uint32_t)(nowMs - session.core.createdAtMs) >= kPendingWakeWaitingUplinkTimeoutMs) {
          noteWakeLoopStage("waiting_uplink_timeout", session);
          LOGW(
              "RTR_WAITING_UPLINK_TIMEOUT deviceId=%lu commandId=%s createdAtMs=%lu nowMs=%lu timeoutMs=%lu",
              (unsigned long)session.core.deviceId,
              session.commandId[0] ? session.commandId : "-",
              (unsigned long)session.core.createdAtMs,
              (unsigned long)nowMs,
              (unsigned long)kPendingWakeWaitingUplinkTimeoutMs);
          appendPropertyCommandEvent(
              activeSimpleCommand.propertyId,
              activeSimpleCommand.commandId,
              "rtr_waiting_uplink_timeout",
              nullptr,
              nullptr);
          failPendingWakeSession(
              session,
              rtrv1::REASON_PAGE_TIMEOUT_FINAL,
              "waiting_uplink_timeout");
          return true;
        }
        if (rtrwake::predictedWakeReady(session.core, nowMs)) {
          noteWakeLoopStage("predicted_wake", session);
          transitionPendingWakeState(
              session, rtrwake::State::PAGING_READY_TO_SEND, "predicted_wake");
          publishFenceTransportState(session.core.deviceId, "paging_ready");
          LOGI(
              "RTR_PAGE_READY_TO_SEND deviceId=%lu commandId=%s campaignCount=%u",
              (unsigned long)session.core.deviceId,
              session.commandId[0] ? session.commandId : "-",
              (unsigned)session.core.campaignCount);
          return true;
        }
        break;

      case rtrwake::State::PAGING_READY_TO_SEND:
        if (session.core.nextPageAttemptAtMs == 0 ||
            (int32_t)(nowMs - session.core.nextPageAttemptAtMs) >= 0) {
          if (reschedulePendingWakeForFreshUplink(
                  session,
                  nowMs,
                  "wake_hint_stale",
                  "wake_hint_stale_wait_next_uplink")) {
            return true;
          }
          noteWakeLoopStage("page_ready_send", session);
          const char* sendReason = nullptr;
          if (!trySendRtrPage(session, &sendReason)) {
            if (session.core.campaignCount < session.core.maxCampaigns) {
              transitionPendingWakeState(
                  session, rtrwake::State::PAGING_WAITING_UPLINK, "page_send_failed_retry");
              rtrwake::scheduleRetryWaitingUplink(&session.core, nowMs);
              publishFenceTransportState(
                  session.core.deviceId,
                  "paging_waiting_uplink",
                  sendReason ? sendReason : session.lastReasonLabel,
                  rtrv1::REASON_PAGE_SEND_FAILED,
                  false,
                  false);
            } else {
              failPendingWakeSession(
                  session,
                  rtrv1::REASON_PAGE_SEND_FAILED,
                  session.lastReasonLabel[0]
                      ? session.lastReasonLabel
                      : rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_SEND_FAILED));
            }
          }
          return true;
        }
        break;

      case rtrwake::State::PAGING_AWAITING_ACK:
        if (rtrwake::awaitingAckWithoutPageSent(session.core)) {
          noteWakeLoopStage("awaiting_ack_invalid", session);
          LOGW(
              "RTR_PAGE_TIMEOUT_STATE_INVALID deviceId=%lu commandId=%s campaignCount=%u pageSent=%d lastPageSentAtMs=%lu ackDeadlineAtMs=%lu",
              (unsigned long)session.core.deviceId,
              session.commandId[0] ? session.commandId : "-",
              (unsigned)session.core.campaignCount,
              session.core.pageSent ? 1 : 0,
              (unsigned long)session.core.lastPageSentAtMs,
              (unsigned long)session.core.pageAckDeadlineAtMs);
          failPendingWakeSession(
              session,
              rtrv1::REASON_PAGE_SEND_FAILED,
              "page_ack_state_without_page_tx");
          return true;
        }
        if (rtrwake::inFlightAttemptSoftTimedOut(session.core, nowMs)) {
          if (rtrwake::canRetryAfterTimeout(session.core)) {
            noteWakeLoopStage("soft_timeout_mark", session);
            wakeLoopDiag.lastSoftTimeoutAtMs = nowMs;
            const uint32_t retryAtMs = nowMs + rtrv1::PAGE_RETRY_GRACE_MS;
            rtrdiag::notePageRetry(
                &lastPageDiag,
                retryAtMs,
                static_cast<uint8_t>(session.core.campaignCount + 1),
                "timeout_retry_grace");
            LOGW(
                "RTR_PAGE_SOFT_TIMEOUT deviceId=%lu commandId=%s campaignCount=%u sessionId=%llu messageId=%lu softDeadlineAtMs=%lu hardDeadlineAtMs=%lu",
                (unsigned long)session.core.deviceId,
                session.commandId[0] ? session.commandId : "-",
                (unsigned)session.core.inFlightPage.campaignCount,
                (unsigned long long)session.core.inFlightPage.sessionId,
                (unsigned long)session.core.inFlightPage.messageId,
                (unsigned long)session.core.inFlightPage.softDeadlineAtMs,
                (unsigned long)session.core.inFlightPage.hardDeadlineAtMs);
            LOGI(
                "RTR_PAGE_SOFT_TIMEOUT_MARKED deviceId=%lu commandId=%s atMs=%lu",
                (unsigned long)session.core.deviceId,
                session.commandId[0] ? session.commandId : "-",
                (unsigned long)nowMs);
            LOGI(
                "RTR_PAGE_RETRY_SCHEDULED deviceId=%lu commandId=%s retryAtMs=%lu graceMs=%lu nextCampaign=%u",
                (unsigned long)session.core.deviceId,
                session.commandId[0] ? session.commandId : "-",
                (unsigned long)retryAtMs,
                (unsigned long)rtrv1::PAGE_RETRY_GRACE_MS,
                (unsigned)(session.core.campaignCount + 1));
            wakeLoopDiag.lastRetryScheduleAtMs = nowMs;
            LOGI(
                "RTR_RETRY_SCHEDULED_LIGHTWEIGHT deviceId=%lu commandId=%s retryAtMs=%lu",
                (unsigned long)session.core.deviceId,
                session.commandId[0] ? session.commandId : "-",
                (unsigned long)retryAtMs);
            transitionPendingWakeState(
                session, rtrwake::State::PAGING_RETRY_GRACE, "page_soft_timeout");
            rtrwake::scheduleRetryReadyToSend(
                &session.core,
                nowMs,
                rtrv1::PAGE_RETRY_GRACE_MS);
            syncLastPageDiagFromSession(session);
            setPendingWakeReason(
                session,
                rtrv1::REASON_PAGE_TIMEOUT,
                rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_TIMEOUT));
            publishFenceTransportState(
                session.core.deviceId,
                "page_timeout_retry_grace",
                rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_TIMEOUT),
                rtrv1::REASON_PAGE_TIMEOUT,
                false,
                false);
            return true;
          }
        }
        if (!session.core.scheduledRetry.pending &&
            rtrwake::inFlightAttemptHardTimedOut(session.core, nowMs)) {
          noteWakeLoopStage("hard_timeout_final", session);
          LOGW(
              "RTR_PAGE_HARD_TIMEOUT deviceId=%lu commandId=%s campaignCount=%u sessionId=%llu messageId=%lu hardDeadlineAtMs=%lu nowMs=%lu",
              (unsigned long)session.core.deviceId,
              session.commandId[0] ? session.commandId : "-",
              (unsigned)session.core.inFlightPage.campaignCount,
              (unsigned long long)session.core.inFlightPage.sessionId,
              (unsigned long)session.core.inFlightPage.messageId,
              (unsigned long)session.core.inFlightPage.hardDeadlineAtMs,
              (unsigned long)nowMs);
          LOGI(
              "RTR_PAGE_ATTEMPT_EXPIRED deviceId=%lu commandId=%s sessionId=%llu messageId=%lu",
              (unsigned long)session.core.deviceId,
              session.commandId[0] ? session.commandId : "-",
              (unsigned long long)session.core.inFlightPage.sessionId,
              (unsigned long)session.core.inFlightPage.messageId);
          rtrwake::expireInFlightAttempt(&session.core);
          syncLastPageDiagFromSession(session);
          rtrdiag::notePageOutcome(&lastPageDiag, "timeout_final");
          appendPropertyCommandEvent(
              activeSimpleCommand.propertyId,
              activeSimpleCommand.commandId,
              "rtr_page_timeout_final",
              nullptr,
              nullptr);
          failPendingWakeSession(
              session,
              rtrv1::REASON_PAGE_TIMEOUT_FINAL,
              rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_TIMEOUT_FINAL));
          return true;
        }
        break;

      case rtrwake::State::PAGING_RETRY_GRACE:
        if (rtrwake::inFlightAttemptHardTimedOut(session.core, nowMs)) {
          noteWakeLoopStage("retry_grace_expire", session);
          LOGW(
              "RTR_PAGE_HARD_TIMEOUT deviceId=%lu commandId=%s campaignCount=%u sessionId=%llu messageId=%lu hardDeadlineAtMs=%lu nowMs=%lu",
              (unsigned long)session.core.deviceId,
              session.commandId[0] ? session.commandId : "-",
              (unsigned)session.core.inFlightPage.campaignCount,
              (unsigned long long)session.core.inFlightPage.sessionId,
              (unsigned long)session.core.inFlightPage.messageId,
              (unsigned long)session.core.inFlightPage.hardDeadlineAtMs,
              (unsigned long)nowMs);
          LOGI(
              "RTR_PAGE_ATTEMPT_EXPIRED deviceId=%lu commandId=%s sessionId=%llu messageId=%lu",
              (unsigned long)session.core.deviceId,
              session.commandId[0] ? session.commandId : "-",
              (unsigned long long)session.core.inFlightPage.sessionId,
              (unsigned long)session.core.inFlightPage.messageId);
          rtrwake::expireInFlightAttempt(&session.core);
          syncLastPageDiagFromSession(session);
          if (session.core.scheduledRetry.pending &&
              rtrwake::canRetryAfterTimeout(session.core)) {
            session.core.campaignCount =
                session.core.scheduledRetry.nextCampaignCount > 0
                    ? session.core.scheduledRetry.nextCampaignCount - 1
                    : session.core.campaignCount;
            session.core.nextPageAttemptAtMs = session.core.scheduledRetry.retryAtMs;
            transitionPendingWakeState(
                session,
                rtrwake::State::PAGING_READY_TO_SEND,
                "page_hard_timeout_retry_ready");
            return true;
          } else {
            rtrdiag::notePageOutcome(&lastPageDiag, "timeout_final");
            appendPropertyCommandEvent(
                activeSimpleCommand.propertyId,
                activeSimpleCommand.commandId,
                "rtr_page_timeout_final",
                nullptr,
                nullptr);
            failPendingWakeSession(
                session,
                rtrv1::REASON_PAGE_TIMEOUT_FINAL,
                rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_TIMEOUT_FINAL));
            return true;
          }
        }
        break;

      case rtrwake::State::PAGE_ACKED:
        noteWakeLoopStage("page_acked", session);
        transitionPendingWakeState(
            session, rtrwake::State::SESSION_START_READY, "page_ack_ok");
        return true;

      case rtrwake::State::SESSION_START_READY:
        noteWakeLoopStage("begin_dispatch_deferred", session);
        publishFenceTransportState(session.core.deviceId, "session_starting");
        session.core.beginDispatchPending = true;
        transitionPendingWakeState(
            session, rtrwake::State::SESSION_IN_PROGRESS, "rpv2_start");
        LOGI(
            "RTR_BEGIN_DISPATCH_DEFERRED deviceId=%lu commandId=%s campaignCount=%u",
            (unsigned long)session.core.deviceId,
            session.commandId[0] ? session.commandId : "-",
            (unsigned)session.core.campaignCount);
        return true;

      case rtrwake::State::SESSION_IN_PROGRESS: {
        if (!session.core.beginDispatchPending || session.core.sessionStarted) break;
        noteWakeLoopStage("begin_dispatch_start", session);
        wakeLoopDiag.lastBeginDispatchAtMs = nowMs;
        LOGI(
            "RTR_BEGIN_DISPATCH_START deviceId=%lu commandId=%s campaignCount=%u",
            (unsigned long)session.core.deviceId,
            session.commandId[0] ? session.commandId : "-",
            (unsigned)session.core.campaignCount);
        LOGI(
            "RPV2_SESSION_BEGIN_DISPATCH deviceId=%lu commandId=%s radioCommandId=%llu",
            (unsigned long)session.core.deviceId,
            session.commandId[0] ? session.commandId : "-",
            (unsigned long long)session.radioCommandId);
        LOGI(
            "RTR_TO_RPV2_START deviceId=%lu commandId=%s campaignCount=%u",
            (unsigned long)session.core.deviceId,
            session.commandId[0] ? session.commandId : "-",
            (unsigned)session.core.campaignCount);
        feedWatchdogIfEnabled();
        delay(1);
        session.core.sessionStarted = true;
        session.core.beginDispatchPending = false;
        const char* sessionReason = nullptr;
        if (executeFenceCommandRpv2Plan(
                session.core.deviceId,
                session.scopeId,
                session.radioCommandId,
                session.sessionNonce,
                session.commandId,
                session.plan,
                &sessionReason)) {
          LOGI(
              "RPV2_SESSION_END_APPLIED deviceId=%lu commandId=%s radioCommandId=%llu",
              (unsigned long)session.core.deviceId,
              session.commandId[0] ? session.commandId : "-",
              (unsigned long long)session.radioCommandId);
          transitionPendingWakeState(
              session, rtrwake::State::COMPLETED, "rpv2_applied");
        } else {
          LOGW(
              "RPV2_SESSION_END_FAILED deviceId=%lu commandId=%s radioCommandId=%llu reason=%s",
              (unsigned long)session.core.deviceId,
              session.commandId[0] ? session.commandId : "-",
              (unsigned long long)session.radioCommandId,
              sessionReason ? sessionReason : "rpv2_failed");
          LOGW(
              "RTR_TO_RPV2_ABORT deviceId=%lu commandId=%s reason=%s",
              (unsigned long)session.core.deviceId,
              session.commandId[0] ? session.commandId : "-",
              sessionReason ? sessionReason : "session_start_failed");
          failPendingWakeSession(
              session,
              activeSimpleCommand.lastReasonCode != rpv2::REASON_NONE
                  ? activeSimpleCommand.lastReasonCode
                  : rtrv1::REASON_SESSION_NOT_STARTED_AFTER_PAGE_ACK,
              sessionReason && sessionReason[0]
                  ? sessionReason
                  : rtrv1::reasonCodeLabel(
                        rtrv1::REASON_SESSION_NOT_STARTED_AFTER_PAGE_ACK));
        }
        return true;
      }

      case rtrwake::State::COMPLETED:
        noteWakeLoopStage("session_completed", session);
        clearPendingWakeSession(idx, "completed");
        return true;

      case rtrwake::State::FAILED:
        noteWakeLoopStage("session_failed", session);
        clearPendingWakeSession(idx, session.lastReasonLabel);
        return true;

      default:
        break;
    }
    return false;
}

static void processPendingWakeSessions() {
  constexpr uint8_t kWakeSessionBudgetPerTick = 2;
  const uint32_t nowMs = millis();
  wakeLoopDiag.wakeLoopIterationCount++;
  uint8_t processedCount = 0;
  bool shouldYield = false;
  for (uint8_t i = 0; i < kMaxPendingWakeSessions; ++i) {
    PendingWakeSession& session = pendingWakeSessions[i];
    if (!session.core.active) continue;
    feedWatchdogIfEnabled();
    processedCount++;
    const bool advanced = processPendingWakeSessionStep(i, session, nowMs);
    if (advanced) {
      shouldYield = true;
      break;
    }
    if (processedCount >= kWakeSessionBudgetPerTick) {
      wakeLoopDiag.wakeLoopBudgetHitCount++;
      LOGI(
          "RTR_WAKE_LOOP_BUDGET_HIT processed=%u activeBudget=%u",
          (unsigned)processedCount,
          (unsigned)kWakeSessionBudgetPerTick);
      shouldYield = true;
      break;
    }
  }
  if (shouldYield) {
    wakeLoopDiag.wakeLoopYieldCount++;
    LOGI(
        "RTR_WAKE_LOOP_YIELD yields=%lu budgetHits=%lu",
        (unsigned long)wakeLoopDiag.wakeLoopYieldCount,
        (unsigned long)wakeLoopDiag.wakeLoopBudgetHitCount);
    feedWatchdogIfEnabled();
    delay(1);
  }
}

static bool sendLoRaJsonFrame(
    uint32_t deviceId,
    MsgType msgType,
    const JsonVariantConst payload,
    const char** reason,
    MatrixLoRaTxReason txReason,
    const char* callerTag,
    const LoRaFrame* sourceUplinkOrNull,
    const char* commandId) {
  const size_t bytes = measureJson(payload);
  if (bytes > cfg::LORA_MAX_PAYLOAD_BYTES) {
    if (reason) *reason = "payload_too_large";
    return false;
  }

  LoRaFrame tx;
  tx.deviceId = deviceId;
  tx.scopeId = parseScopeIdHex(payload["scope_id"]);
  if (tx.scopeId == 0) tx.scopeId = bindingScopeIdValue();
  tx.msgType = msgType;
  tx.seq = nextDownlinkSeq();
  tx.timestamp = millis() / 1000;
  for (int i = 0; i < 12; ++i) tx.nonce[i] = (uint8_t)esp_random();
  tx.payloadLen = serializeJson(payload, tx.payload, sizeof(tx.payload));
  if (tx.payloadLen != bytes) {
    if (reason) *reason = "payload_truncated";
    return false;
  }

  const bool ok = sendMatrixLoRaFrame(
      tx,
      txReason,
      sourceUplinkOrNull,
      callerTag,
      commandId);
  const bool chunked = payload["chunked"].is<bool>() && payload["chunked"].as<bool>();
  const int part = payload["part"] | 0;
  const int total = payload["total"] | 1;
  const bool finalFenceChunk =
      msgType == MsgType::SET_FENCE &&
      (!chunked || (total > 0 && part >= (total - 1)));
  const bool shouldOpenFeedbackWindow =
      ok &&
      activeSimpleCommand.active &&
      activeSimpleCommand.targetDeviceCommand &&
      activeSimpleCommand.targetCount == 1 &&
      deviceId != 0 &&
      (msgType == MsgType::PING ||
       msgType == MsgType::SET_PARAMS ||
       finalFenceChunk);
  if (shouldOpenFeedbackWindow) {
    openActiveSimpleCommandFeedbackWindow(deviceId);
    pollActiveSimpleCommandFeedbackSlice();
  }
  if (!ok && reason && !*reason) *reason = "lora_send_failed";
  return ok;
}

static bool splitPointArrayForPayload(
    const JsonArrayConst& points,
    uint8_t starts[cfg::MAX_POLYGON_POINTS],
    uint8_t ends[cfg::MAX_POLYGON_POINTS],
    uint8_t& chunkCount,
    bool includePhaseMeta,
    uint8_t phaseIdx,
    uint8_t phaseTotal,
    const char** reason = nullptr) {
  chunkCount = 0;
  const uint8_t totalPoints = (uint8_t)points.size();
  const rtcmd::ValidationCode countCode =
      rtcmd::validatePointCount(totalPoints, cfg::MAX_POLYGON_POINTS);
  if (countCode != rtcmd::ValidationCode::kOk) {
    if (reason) *reason = rtcmd::validationCodeToReason(countCode);
    return false;
  }

  StaticJsonDocument<384> probe;
  probe["chunked"] = true;
  // Usa dois digitos para evitar subestimar overhead quando total>=10.
  probe["part"] = 99;
  probe["total"] = 99;
  if (includePhaseMeta) {
    probe["phase_index"] = phaseIdx;
    probe["phase_total"] = phaseTotal;
  }
  JsonArray probePoints = probe["points"].to<JsonArray>();
  const size_t overheadBytes = measureJson(probe);

  uint16_t pointCosts[cfg::MAX_POLYGON_POINTS]{};
  size_t previousSize = overheadBytes;
  for (uint8_t i = 0; i < totalPoints; ++i) {
    const JsonArrayConst srcPair = points[i].as<JsonArrayConst>();
    double lat = 0.0;
    double lon = 0.0;
    if (!readPointPair(srcPair, lat, lon)) {
      if (reason) *reason = "invalid_point_value";
      return false;
    }

    JsonArray dstPair = probePoints.add<JsonArray>();
    dstPair.add(lat);
    dstPair.add(lon);
    const size_t measured = measureJson(probe);
    if (measured <= previousSize) {
      if (reason) *reason = "invalid_point_value";
      return false;
    }
    const size_t delta = measured - previousSize;
    if (delta > 0xFFFF) {
      if (reason) *reason = "point_chunk_too_large";
      return false;
    }
    pointCosts[i] = (uint16_t)delta;
    previousSize = measured;
  }

  rtcmd::ChunkRange ranges[cfg::MAX_POLYGON_POINTS]{};
  const rtcmd::ValidationCode chunkCode = rtcmd::planPointChunks(
      pointCosts,
      totalPoints,
      (uint16_t)overheadBytes,
      cfg::LORA_MAX_PAYLOAD_BYTES,
      cfg::MAX_POLYGON_POINTS,
      ranges,
      cfg::MAX_POLYGON_POINTS,
      &chunkCount);
  if (chunkCode != rtcmd::ValidationCode::kOk) {
    if (reason) *reason = rtcmd::validationCodeToReason(chunkCode);
    return false;
  }

  for (uint8_t i = 0; i < chunkCount; ++i) {
    starts[i] = ranges[i].start;
    ends[i] = ranges[i].end;
  }
  return true;
}

static bool sendFenceCommandChunked(uint32_t deviceId, const JsonVariantConst payload, const char** reason) {
  const FencePointsResolution pointsResolution = resolveFencePoints(payload);
  const JsonArrayConst points = pointsResolution.points;
  const char* commandId = pickFirstText(
      payload["cmd_id"],
      payload["command_id"],
      payload["payload"]["cmd_id"],
      payload["payload"]["command_id"]);
  if (points.isNull()) {
    AS_MATRIX_FENCE_POINTS_RESOLUTION_FAIL(
        commandId[0] ? commandId : "-",
        "root.points,payload.points,payload.payload.points",
        "none",
        "missing_or_invalid_points");
    if (reason) *reason = "missing_points";
    return false;
  }
  AS_MATRIX_FENCE_POINTS_RESOLVED(
      commandId[0] ? commandId : "-",
      pointsResolution.source,
      points.size());

  if (payloadUsesFenceRpv2(payload)) {
    return sendFenceCommandRpv2Session(
        deviceId,
        payload,
        commandId,
        pointsResolution,
        reason);
  }

  uint8_t starts[cfg::MAX_POLYGON_POINTS]{};
  uint8_t ends[cfg::MAX_POLYGON_POINTS]{};
  uint8_t chunkCount = 0;
  if (!splitFencePointArrayForPayload(payload, points, starts, ends, chunkCount, reason)) return false;

  for (uint8_t part = 0; part < chunkCount; ++part) {
    StaticJsonDocument<384> chunkDoc;
    if (!buildFenceChunkPayload(
            chunkDoc,
            payload,
            points,
            commandId,
            part,
            chunkCount,
            starts[part],
            ends[part],
            reason)) {
      return false;
    }

    const size_t jsonBytes = measureJson(chunkDoc.as<JsonVariantConst>());
    size_t packedBytes = 0;
    size_t cipherBytes = 0;
    size_t radioBytes = 0;
    estimateLoRaPayloadSizes(jsonBytes, &packedBytes, &cipherBytes, &radioBytes);
    AS_MATRIX_FENCE_CHUNK_SIZE_EVAL(
        commandId[0] ? commandId : "-",
        part,
        chunkCount,
        jsonBytes,
        packedBytes,
        cipherBytes,
        cfg::LORA_MAX_PAYLOAD_BYTES);

    if (!sendLoRaJsonFrame(
            deviceId,
            MsgType::SET_FENCE,
            chunkDoc.as<JsonVariantConst>(),
            reason,
            MatrixLoRaTxReason::CommandDispatch,
            "sendFenceCommandChunked",
            nullptr,
            activeSimpleCommand.commandId)) return false;
  }
  return true;
}

static bool sendHerdingPlanChunked(uint32_t deviceId, const JsonVariantConst payload, const char** reason = nullptr) {
  const JsonArrayConst phases = payload["phases"].as<JsonArrayConst>();
  if (phases.isNull()) {
    if (reason) *reason = "missing_phases";
    return false;
  }
  const uint8_t phaseTotal = (uint8_t)phases.size();
  if (phaseTotal == 0 || phaseTotal > cfg::MAX_HERD_PHASES) {
    if (reason) *reason = "invalid_phase_count";
    return false;
  }

  for (uint8_t phaseIdx = 0; phaseIdx < phaseTotal; ++phaseIdx) {
    const JsonArrayConst points = phases[phaseIdx].as<JsonArrayConst>();
    if (points.isNull()) {
      if (reason) *reason = "invalid_phase_points";
      return false;
    }

    uint8_t starts[cfg::MAX_POLYGON_POINTS]{};
    uint8_t ends[cfg::MAX_POLYGON_POINTS]{};
    uint8_t chunkCount = 0;
    if (!splitPointArrayForPayload(points, starts, ends, chunkCount, true, phaseIdx, phaseTotal, reason)) return false;

    for (uint8_t part = 0; part < chunkCount; ++part) {
      StaticJsonDocument<384> chunkDoc;
      chunkDoc["chunked"] = true;
      const char* operationId = payload["operation_id"] | "";
      const char* commandId = pickFirstText(payload["cmd_id"], payload["command_id"]);
      const char* scopeId = pickFirstText(payload["scope_id"], payload["property_scope_id"]);
      const char* matrixGatewayId = pickFirstText(payload["matrix_gateway_id"]);
      const char* polygonKind = pickFirstText(payload["polygon_kind"], payload["polygonKind"]);
      const char* originDocType = pickFirstText(payload["origin_doc_type"], payload["originDocType"]);
      const char* originDocId = pickFirstText(
          payload["origin_doc_id"], payload["originDocId"], payload["operation_id"]);
      if (operationId[0] != '\0') chunkDoc["operation_id"] = operationId;
      if (commandId[0] != '\0') chunkDoc["cmd_id"] = commandId;
      if (scopeId[0] != '\0') chunkDoc["scope_id"] = scopeId;
      if (matrixGatewayId[0] != '\0') chunkDoc["matrix_gateway_id"] = matrixGatewayId;
      if (polygonKind[0] != '\0') chunkDoc["polygon_kind"] = polygonKind;
      if (originDocType[0] != '\0') chunkDoc["origin_doc_type"] = originDocType;
      if (originDocId[0] != '\0') chunkDoc["origin_doc_id"] = originDocId;
      if (!payload["requested_at_ms"].isNull()) {
        chunkDoc["requested_at_ms"] = payload["requested_at_ms"];
      }
      chunkDoc["phase_index"] = phaseIdx;
      chunkDoc["phase_total"] = phaseTotal;
      chunkDoc["part"] = part;
      chunkDoc["total"] = chunkCount;
      JsonArray chunkPoints = chunkDoc["points"].to<JsonArray>();
      for (uint8_t i = starts[part]; i < ends[part]; ++i) {
        const JsonArrayConst srcPair = points[i].as<JsonArrayConst>();
        JsonArray dstPair = chunkPoints.add<JsonArray>();
        dstPair.add(srcPair[0].as<double>());
        dstPair.add(srcPair[1].as<double>());
      }

      if (!sendLoRaJsonFrame(
              deviceId,
              MsgType::SET_HERDING_PLAN,
              chunkDoc.as<JsonVariantConst>(),
              reason,
              MatrixLoRaTxReason::CommandDispatch,
              "sendHerdingPlanChunked",
              nullptr,
              herdOp.loraCommandId)) return false;
    }
  }

  return true;
}

static bool queuePollingConfigured() {
  return cloudTelemetryConfigured() && !isUnsetCloudValue(cfg::RTDB_QUEUE_KEY);
}

static String queueRootPath() {
  return String("matrixCommandQueues/") + matrixCloudId() + "/" + String(cfg::RTDB_QUEUE_KEY);
}

static bool openQueueCommandStream() {
  queueStreamConnected = false;
  queueStreamReconnectAtUnixMs = 0;
  clearQueueStreamError();
  return false;
}

static void pollQueueCommandStream() {
  if (queueStreamConnected) closeQueueCommandStream("poll_only");
}

static String queueBodyPrefix(const String& body, size_t maxLen = 220) {
  String prefix = body;
  prefix.replace("\r", " ");
  prefix.replace("\n", " ");
  prefix.trim();
  if (prefix.length() > maxLen) {
    prefix = prefix.substring(0, maxLen);
    prefix += "...";
  }
  return prefix;
}

static const char* queueBodyShape(const DynamicJsonDocument& doc) {
  if (doc.is<JsonArrayConst>()) return "array";
  if (doc.is<JsonObjectConst>()) return "object";
  if (doc.is<const char*>()) return "string";
  if (doc.is<bool>()) return "bool";
  if (doc.is<long>() || doc.is<unsigned long>() || doc.is<float>() || doc.is<double>()) return "number";
  if (doc.isNull()) return "null";
  return "unknown";
}

static const char* deserializationErrorName(DeserializationError error) {
  switch (error.code()) {
    case DeserializationError::Ok:
      return "Ok";
    case DeserializationError::EmptyInput:
      return "EmptyInput";
    case DeserializationError::IncompleteInput:
      return "IncompleteInput";
    case DeserializationError::InvalidInput:
      return "InvalidInput";
    case DeserializationError::NoMemory:
      return "NoMemory";
    case DeserializationError::TooDeep:
      return "TooDeep";
    default:
      return "Unknown";
  }
}

static bool queueBodyLooksSemanticallyEmpty(const String& body) {
  String normalized;
  normalized.reserve(body.length());
  for (size_t i = 0; i < body.length(); ++i) {
    const char ch = body[i];
    if (ch == ' ' || ch == '\r' || ch == '\n' || ch == '\t') continue;
    if (ch >= '0' && ch <= '9') continue;
    normalized += static_cast<char>(tolower(static_cast<unsigned char>(ch)));
    if (normalized.length() > 12) break;
  }
  return normalized == "null";
}

static bool sanitizeQueueResponseBody(String& body, size_t& trimmedPrefixBytes, char& firstJsonChar) {
  trimmedPrefixBytes = 0;
  firstJsonChar = '\0';
  const size_t len = body.length();
  size_t idx = 0;
  while (idx < len) {
    const char ch = body[idx];
    if (ch == '{' || ch == '[') {
      firstJsonChar = ch;
      break;
    }
    ++idx;
  }
  if (idx >= len) return false;
  if (idx > 0) {
    body.remove(0, idx);
    trimmedPrefixBytes = idx;
  }
  return true;
}

static FencePointsResolution resolveFencePoints(const JsonVariantConst root) {
  FencePointsResolution resolution;
  const JsonArrayConst rootPoints = root["points"].as<JsonArrayConst>();
  if (!rootPoints.isNull()) {
    resolution.points = rootPoints;
    resolution.source = "root.points";
    return resolution;
  }

  const JsonVariantConst payload = root["payload"];
  const JsonArrayConst payloadPoints = payload["points"].as<JsonArrayConst>();
  if (!payloadPoints.isNull()) {
    resolution.points = payloadPoints;
    resolution.source = "payload.points";
    return resolution;
  }

  const JsonArrayConst nestedPayloadPoints = payload["payload"]["points"].as<JsonArrayConst>();
  if (!nestedPayloadPoints.isNull()) {
    resolution.points = nestedPayloadPoints;
    resolution.source = "payload.payload.points";
    return resolution;
  }

  return resolution;
}

static void promoteFencePayloadFields(
    JsonObject payloadObject,
    JsonObjectConst nestedPayload,
    JsonVariant rootValue) {
  if (!payloadObject["points"].is<JsonArrayConst>() &&
      nestedPayload["points"].is<JsonArrayConst>()) {
    payloadObject["points"] = nestedPayload["points"].as<JsonArrayConst>();
  }
  if (!payloadObject["cmd_id"].is<const char*>() &&
      nestedPayload["cmd_id"].is<const char*>()) {
    payloadObject["cmd_id"] = nestedPayload["cmd_id"].as<const char*>();
  }
  if (!payloadObject["command_id"].is<const char*>() &&
      nestedPayload["command_id"].is<const char*>()) {
    payloadObject["command_id"] = nestedPayload["command_id"].as<const char*>();
  }
  if (!payloadObject["property_id"].is<const char*>() &&
      nestedPayload["property_id"].is<const char*>()) {
    payloadObject["property_id"] = nestedPayload["property_id"].as<const char*>();
  }
  if (!payloadObject["property_scope_id"].is<const char*>() &&
      nestedPayload["property_scope_id"].is<const char*>()) {
    payloadObject["property_scope_id"] = nestedPayload["property_scope_id"].as<const char*>();
  }
  if (!payloadObject["target_device_ids"].is<JsonArrayConst>() &&
      nestedPayload["target_device_ids"].is<JsonArrayConst>()) {
    payloadObject["target_device_ids"] = nestedPayload["target_device_ids"].as<JsonArrayConst>();
  }
  if (!payloadObject["target_gateway_ids"].is<JsonArrayConst>() &&
      nestedPayload["target_gateway_ids"].is<JsonArrayConst>()) {
    payloadObject["target_gateway_ids"] = nestedPayload["target_gateway_ids"].as<JsonArrayConst>();
  }
  if (!payloadObject["matrix_gateway_id"].is<const char*>() &&
      nestedPayload["matrix_gateway_id"].is<const char*>()) {
    payloadObject["matrix_gateway_id"] = nestedPayload["matrix_gateway_id"].as<const char*>();
  }
  if (!payloadObject["matrixRuntimeId"].is<const char*>() &&
      nestedPayload["matrixRuntimeId"].is<const char*>()) {
    payloadObject["matrixRuntimeId"] = nestedPayload["matrixRuntimeId"].as<const char*>();
  }
  if (!payloadObject["polygon_kind"].is<const char*>() &&
      nestedPayload["polygon_kind"].is<const char*>()) {
    payloadObject["polygon_kind"] = nestedPayload["polygon_kind"].as<const char*>();
  }
  if (!payloadObject["origin_doc_type"].is<const char*>() &&
      nestedPayload["origin_doc_type"].is<const char*>()) {
    payloadObject["origin_doc_type"] = nestedPayload["origin_doc_type"].as<const char*>();
  }
  if (!payloadObject["origin_doc_id"].is<const char*>() &&
      nestedPayload["origin_doc_id"].is<const char*>()) {
    payloadObject["origin_doc_id"] = nestedPayload["origin_doc_id"].as<const char*>();
  }

  if (!payloadObject["points"].is<JsonArrayConst>() &&
      rootValue["points"].is<JsonArrayConst>()) {
    payloadObject["points"] = rootValue["points"].as<JsonArrayConst>();
  }
  if (!payloadObject["cmd_id"].is<const char*>() &&
      rootValue["command_id"].is<const char*>()) {
    payloadObject["cmd_id"] = rootValue["command_id"].as<const char*>();
  }
  if (!payloadObject["command_id"].is<const char*>() &&
      rootValue["command_id"].is<const char*>()) {
    payloadObject["command_id"] = rootValue["command_id"].as<const char*>();
  }
}

static void estimateLoRaPayloadSizes(
    size_t jsonBytes,
    size_t* packedBytes,
    size_t* cipherBytes,
    size_t* radioBytes) {
  const size_t safeJsonBytes = jsonBytes;
  const size_t packed = 4 + 8 + 1 + 4 + 4 + 12 + 1 + safeJsonBytes + 16;
  const size_t cipher = packed >= 16 ? packed - 16 : 0;
  const size_t radio = 12 + cipher + 16;
  if (packedBytes) *packedBytes = packed;
  if (cipherBytes) *cipherBytes = cipher;
  if (radioBytes) *radioBytes = radio;
}

static bool buildFenceChunkPayload(
    StaticJsonDocument<384>& chunkDoc,
    const JsonVariantConst payload,
    const JsonArrayConst& points,
    const char* commandId,
    uint8_t part,
    uint8_t total,
    uint8_t start,
    uint8_t end,
    const char** reason) {
  chunkDoc.clear();
  chunkDoc["chunked"] = true;
  chunkDoc["part"] = part;
  chunkDoc["total"] = total;

  const char* scopeId = pickFirstText(payload["scope_id"], payload["property_scope_id"]);
  const char* polygonKind = pickFirstText(payload["polygon_kind"], payload["polygonKind"]);
  const char* originDocType = pickFirstText(payload["origin_doc_type"], payload["originDocType"]);
  const char* originDocId = pickFirstText(payload["origin_doc_id"], payload["originDocId"]);
  if (commandId && commandId[0] != '\0') chunkDoc["cmd_id"] = commandId;
  if (scopeId[0] != '\0') chunkDoc["scope_id"] = scopeId;
  if (polygonKind[0] != '\0') chunkDoc["polygon_kind"] = polygonKind;
  if (originDocType[0] != '\0') chunkDoc["origin_doc_type"] = originDocType;
  if (originDocId[0] != '\0') chunkDoc["origin_doc_id"] = originDocId;

  JsonArray chunkPoints = chunkDoc["points"].to<JsonArray>();
  for (uint8_t i = start; i < end; ++i) {
    double lat = 0.0;
    double lon = 0.0;
    if (!readPointPair(points[i].as<JsonArrayConst>(), lat, lon)) {
      if (reason) *reason = "invalid_point_value";
      return false;
    }
    JsonArray dstPair = chunkPoints.add<JsonArray>();
    dstPair.add(lat);
    dstPair.add(lon);
  }
  return true;
}

static bool splitFencePointArrayForPayload(
    const JsonVariantConst payload,
    const JsonArrayConst& points,
    uint8_t starts[cfg::MAX_POLYGON_POINTS],
    uint8_t ends[cfg::MAX_POLYGON_POINTS],
    uint8_t& chunkCount,
    const char** reason) {
  chunkCount = 0;
  const uint8_t totalPoints = (uint8_t)points.size();
  const rtcmd::ValidationCode countCode =
      rtcmd::validatePointCount(totalPoints, cfg::MAX_POLYGON_POINTS);
  if (countCode != rtcmd::ValidationCode::kOk) {
    if (reason) *reason = rtcmd::validationCodeToReason(countCode);
    return false;
  }

  const char* commandId = pickFirstText(
      payload["cmd_id"],
      payload["command_id"],
      payload["payload"]["cmd_id"],
      payload["payload"]["command_id"]);
  uint8_t start = 0;
  while (start < totalPoints) {
    if (chunkCount >= cfg::MAX_POLYGON_POINTS) {
      if (reason) *reason = "chunk_count_exceeded";
      return false;
    }

    const uint8_t remainingPoints = totalPoints - start;
    const uint8_t worstCaseTotal = remainingPoints;
    const uint8_t worstCasePart = worstCaseTotal > 0 ? (uint8_t)(worstCaseTotal - 1) : 0;
    bool fitFound = false;

    for (uint8_t end = totalPoints; end > start; --end) {
      StaticJsonDocument<384> candidateDoc;
      if (!buildFenceChunkPayload(
              candidateDoc,
              payload,
              points,
              commandId,
              worstCasePart,
              worstCaseTotal,
              start,
              end,
              reason)) {
        return false;
      }

      const size_t jsonBytes = measureJson(candidateDoc.as<JsonVariantConst>());
      size_t packedBytes = 0;
      size_t cipherBytes = 0;
      size_t radioBytes = 0;
      estimateLoRaPayloadSizes(jsonBytes, &packedBytes, &cipherBytes, &radioBytes);
      const bool fit = jsonBytes <= cfg::LORA_MAX_PAYLOAD_BYTES;
      AS_MATRIX_FENCE_CHUNK_PLAN(
          commandId[0] ? commandId : "-",
          start,
          end,
          end - start,
          jsonBytes,
          packedBytes,
          cipherBytes,
          cfg::LORA_MAX_PAYLOAD_BYTES,
          fit);
      if (!fit) continue;

      starts[chunkCount] = start;
      ends[chunkCount] = end;
      chunkCount++;
      start = end;
      fitFound = true;
      break;
    }

    if (fitFound) continue;

    if (reason) {
      *reason = remainingPoints <= 1
                    ? "fence_single_point_chunk_too_large"
                    : "point_chunk_too_large";
    }
    return false;
  }

  return true;
}

static QueueLoadResult loadNextQueuedCommand(String& commandIdOut, DynamicJsonDocument& commandDocOut) {
  if (!queuePollingConfigured()) return QueueLoadResult::kEmpty;
  const String runtimeId = matrixCloudId();
  String body;
  CloudWriteTrace trace;
  if (!rtdbRead(queueRootPath(), body, &trace)) {
    AS_MATRIX_QUEUE_FETCH_HTTP_FAIL(
        runtimeId.c_str(),
        strlen(cfg::RTDB_QUEUE_KEY),
        trace.httpStatus,
        trace.stage,
        trace.detail);
    return QueueLoadResult::kContentError;
  }
  body.trim();
  if (body.isEmpty() || body == "null" || queueBodyLooksSemanticallyEmpty(body)) {
    const String bodyPrefix = queueBodyPrefix(body);
    AS_MATRIX_INFO(
        "QUEUE_FETCH_HTTP_OK_EMPTY_BODY",
        "runtimeId=%s queueKeyLen=%d httpStatus=%d bodyLen=%d emptyKind=%s bodyPrefix=%s",
        runtimeId.c_str(),
        (int)strlen(cfg::RTDB_QUEUE_KEY),
        trace.httpStatus,
        (int)body.length(),
        body.isEmpty() ? "empty" : "null",
        bodyPrefix.c_str());
    return QueueLoadResult::kEmpty;
  }

  size_t trimmedPrefixBytes = 0;
  char firstJsonChar = '\0';
  if (!sanitizeQueueResponseBody(body, trimmedPrefixBytes, firstJsonChar)) {
    const String bodyPrefix = queueBodyPrefix(body);
    if (queueBodyLooksSemanticallyEmpty(body)) {
      AS_MATRIX_INFO(
          "QUEUE_FETCH_HTTP_OK_EMPTY_BODY",
          "runtimeId=%s queueKeyLen=%d httpStatus=%d bodyLen=%d emptyKind=sanitized_null bodyPrefix=%s",
          runtimeId.c_str(),
          (int)strlen(cfg::RTDB_QUEUE_KEY),
          trace.httpStatus,
          (int)body.length(),
          bodyPrefix.c_str());
      return QueueLoadResult::kEmpty;
    }
    AS_MATRIX_QUEUE_FETCH_HTTP_OK_UNEXPECTED_SHAPE(
        runtimeId.c_str(),
        strlen(cfg::RTDB_QUEUE_KEY),
        trace.httpStatus,
        body.length(),
        "no_json_start",
        bodyPrefix.c_str());
    return QueueLoadResult::kContentError;
  }
  if (trimmedPrefixBytes > 0) {
    AS_MATRIX_QUEUE_BODY_SANITIZED(
        runtimeId.c_str(),
        trimmedPrefixBytes,
        firstJsonChar,
        body.length());
  }
  const String bodyPrefix = queueBodyPrefix(body);
  const size_t queueDocCapacity = body.length() + 4096 > 16384 ? body.length() + 4096 : 16384;
  DynamicJsonDocument queueDoc(queueDocCapacity);
  DeserializationError queueError = deserializeJson(queueDoc, body);
  if (queueError != DeserializationError::Ok) {
    AS_MATRIX_QUEUE_FETCH_HTTP_OK_INVALID_JSON(
        runtimeId.c_str(),
        strlen(cfg::RTDB_QUEUE_KEY),
        trace.httpStatus,
        body.length(),
        bodyPrefix.c_str());
    AS_MATRIX_QUEUE_DESERIALIZE_ERROR(
        runtimeId.c_str(),
        trace.httpStatus,
        body.length(),
        deserializationErrorName(queueError),
        queueDocCapacity,
        bodyPrefix.c_str());
    return QueueLoadResult::kContentError;
  }

  String selectedId;
  String selectedBody;
  int itemCount = 0;
  if (queueDoc.is<JsonArrayConst>()) {
    JsonArrayConst items = queueDoc.as<JsonArrayConst>();
    itemCount = (int)items.size();
    if (itemCount == 0) {
      AS_MATRIX_QUEUE_FETCH_HTTP_OK_EMPTY_ARRAY(
          runtimeId.c_str(),
          strlen(cfg::RTDB_QUEUE_KEY),
          trace.httpStatus,
          body.length(),
          bodyPrefix.c_str());
      return QueueLoadResult::kEmpty;
    }
    for (JsonVariantConst item : items) {
      if (!item.is<JsonObjectConst>()) continue;
      const char* candidateId =
          pickFirstText(item["commandId"], item["command_id"], item["payload"]["commandId"], item["payload"]["command_id"]);
      if (!candidateId[0]) continue;
      String candidateBody;
      if (item["payload"].is<JsonObjectConst>()) {
        serializeJson(item["payload"], candidateBody);
      } else {
        serializeJson(item, candidateBody);
      }
      if (!selectedId.isEmpty() && String(candidateId) >= selectedId) continue;
      selectedId = candidateId;
      selectedBody = candidateBody;
    }
    AS_MATRIX_QUEUE_FETCH_HTTP_OK_NONEMPTY_ARRAY(
        runtimeId.c_str(),
        strlen(cfg::RTDB_QUEUE_KEY),
        trace.httpStatus,
        body.length(),
        itemCount,
        selectedId.isEmpty() ? "-" : selectedId.c_str(),
        bodyPrefix.c_str());
  } else if (queueDoc.is<JsonObjectConst>()) {
    JsonObjectConst queueObject = queueDoc.as<JsonObjectConst>();
    if (queueObject.containsKey("command_id") || queueObject.containsKey("commandId")) {
      selectedId = pickFirstText(
          queueObject["commandId"],
          queueObject["command_id"],
          queueObject["payload"]["commandId"],
          queueObject["payload"]["command_id"]);
      serializeJson(queueObject, selectedBody);
      itemCount = selectedId.isEmpty() ? 0 : 1;
      AS_MATRIX_QUEUE_FETCH_HTTP_OK_OBJECT(
          runtimeId.c_str(),
          strlen(cfg::RTDB_QUEUE_KEY),
          trace.httpStatus,
          body.length(),
          itemCount,
          selectedId.isEmpty() ? "-" : selectedId.c_str(),
          bodyPrefix.c_str());
      if (selectedId.isEmpty()) {
        AS_MATRIX_QUEUE_PARSE_FAIL(
            runtimeId.c_str(),
            strlen(cfg::RTDB_QUEUE_KEY),
            "simple_object_missing_command_id",
            bodyPrefix.c_str());
        return QueueLoadResult::kContentError;
      }
    } else {
    itemCount = (int)queueObject.size();
    if (itemCount == 0) {
      AS_MATRIX_INFO(
          "QUEUE_FETCH_HTTP_OK_EMPTY_OBJECT",
          "runtimeId=%s queueKeyLen=%d httpStatus=%d bodyLen=%d bodyPrefix=%s",
          runtimeId.c_str(),
          (int)strlen(cfg::RTDB_QUEUE_KEY),
          trace.httpStatus,
          (int)body.length(),
          bodyPrefix.c_str());
      return QueueLoadResult::kEmpty;
    }
    for (JsonPairConst kv : queueObject) {
      const String key = kv.key().c_str();
      if (!selectedId.isEmpty() && key >= selectedId) continue;
      String candidateBody;
      serializeJson(kv.value(), candidateBody);
      selectedId = key;
      selectedBody = candidateBody;
    }
    AS_MATRIX_QUEUE_FETCH_HTTP_OK_OBJECT(
        runtimeId.c_str(),
        strlen(cfg::RTDB_QUEUE_KEY),
        trace.httpStatus,
        body.length(),
        itemCount,
        selectedId.isEmpty() ? "-" : selectedId.c_str(),
        bodyPrefix.c_str());
    }
  } else {
    AS_MATRIX_QUEUE_FETCH_HTTP_OK_UNEXPECTED_SHAPE(
        runtimeId.c_str(),
        strlen(cfg::RTDB_QUEUE_KEY),
        trace.httpStatus,
        body.length(),
        queueBodyShape(queueDoc),
        bodyPrefix.c_str());
    return QueueLoadResult::kContentError;
  }
  if (selectedId.isEmpty() || selectedBody.isEmpty()) {
    AS_MATRIX_QUEUE_PARSE_FAIL(
        runtimeId.c_str(),
        strlen(cfg::RTDB_QUEUE_KEY),
        "selected_item_missing",
        bodyPrefix.c_str());
    return QueueLoadResult::kContentError;
  }

  commandDocOut.clear();
  const size_t commandDocCapacity =
      selectedBody.length() + 2048 > commandDocOut.capacity()
          ? selectedBody.length() + 2048
          : commandDocOut.capacity();
  commandDocOut.garbageCollect();
  DeserializationError commandError = deserializeJson(commandDocOut, selectedBody);
  if (commandError != DeserializationError::Ok) {
    AS_MATRIX_QUEUE_PARSE_FAIL(
        runtimeId.c_str(),
        strlen(cfg::RTDB_QUEUE_KEY),
        deserializationErrorName(commandError),
        queueBodyPrefix(selectedBody).c_str());
    AS_MATRIX_QUEUE_DESERIALIZE_ERROR(
        runtimeId.c_str(),
        trace.httpStatus,
        selectedBody.length(),
        deserializationErrorName(commandError),
        commandDocCapacity,
        queueBodyPrefix(selectedBody).c_str());
    return QueueLoadResult::kContentError;
  }
  if (!commandDocOut.is<JsonObjectConst>()) {
    AS_MATRIX_QUEUE_PARSE_FAIL(
        runtimeId.c_str(),
        strlen(cfg::RTDB_QUEUE_KEY),
        "selected_item_not_object",
        queueBodyPrefix(selectedBody).c_str());
    return QueueLoadResult::kContentError;
  }

  JsonObject payloadObject;
  if (commandDocOut["payload"].is<JsonObject>()) {
    payloadObject = commandDocOut["payload"].as<JsonObject>();
  } else {
    payloadObject = commandDocOut.createNestedObject("payload");
  }
  const JsonObjectConst nestedPayload =
      payloadObject["payload"].is<JsonObjectConst>()
          ? payloadObject["payload"].as<JsonObjectConst>()
          : JsonObjectConst();
  promoteFencePayloadFields(payloadObject, nestedPayload, commandDocOut.as<JsonVariant>());

  if (!commandDocOut["command"].is<const char*>() &&
      payloadObject["command"].is<const char*>()) {
    commandDocOut["command"] = payloadObject["command"].as<const char*>();
  }
  if (!commandDocOut["commandId"].is<const char*>() &&
      payloadObject["commandId"].is<const char*>()) {
    commandDocOut["commandId"] = payloadObject["commandId"].as<const char*>();
  }
  if (!commandDocOut["commandId"].is<const char*>() &&
      payloadObject["cmd_id"].is<const char*>()) {
    commandDocOut["commandId"] = payloadObject["cmd_id"].as<const char*>();
  }
  if (!commandDocOut["propertyId"].is<const char*>() &&
      payloadObject["propertyId"].is<const char*>()) {
    commandDocOut["propertyId"] = payloadObject["propertyId"].as<const char*>();
  }
  if (!commandDocOut["propertyId"].is<const char*>() &&
      payloadObject["property_id"].is<const char*>()) {
    commandDocOut["propertyId"] = payloadObject["property_id"].as<const char*>();
  }
  if (!commandDocOut["propertyScopeId"].is<const char*>() &&
      payloadObject["propertyScopeId"].is<const char*>()) {
    commandDocOut["propertyScopeId"] = payloadObject["propertyScopeId"].as<const char*>();
  }
  if (!commandDocOut["propertyScopeId"].is<const char*>() &&
      payloadObject["property_scope_id"].is<const char*>()) {
    commandDocOut["propertyScopeId"] = payloadObject["property_scope_id"].as<const char*>();
  }
  if (!commandDocOut["matrixGatewayId"].is<const char*>() &&
      payloadObject["matrixGatewayId"].is<const char*>()) {
    commandDocOut["matrixGatewayId"] = payloadObject["matrixGatewayId"].as<const char*>();
  }
  if (!commandDocOut["matrixGatewayId"].is<const char*>() &&
      payloadObject["matrix_gateway_id"].is<const char*>()) {
    commandDocOut["matrixGatewayId"] = payloadObject["matrix_gateway_id"].as<const char*>();
  }
  if (!commandDocOut["targetDeviceIds"].is<JsonArrayConst>() &&
      payloadObject["targetDeviceIds"].is<JsonArrayConst>()) {
    commandDocOut["targetDeviceIds"] = payloadObject["targetDeviceIds"].as<JsonArrayConst>();
  }
  if (!commandDocOut["targetDeviceIds"].is<JsonArrayConst>() &&
      payloadObject["target_device_ids"].is<JsonArrayConst>()) {
    commandDocOut["targetDeviceIds"] = payloadObject["target_device_ids"].as<JsonArrayConst>();
  }
  if (!commandDocOut["targetGatewayIds"].is<JsonArrayConst>() &&
      payloadObject["targetGatewayIds"].is<JsonArrayConst>()) {
    commandDocOut["targetGatewayIds"] = payloadObject["targetGatewayIds"].as<JsonArrayConst>();
  }
  if (!commandDocOut["targetGatewayIds"].is<JsonArrayConst>() &&
      payloadObject["target_gateway_ids"].is<JsonArrayConst>()) {
    commandDocOut["targetGatewayIds"] = payloadObject["target_gateway_ids"].as<JsonArrayConst>();
  }
  if (!commandDocOut["createdAtMs"].is<uint64_t>() &&
      !payloadObject["createdAtMs"].isNull()) {
    commandDocOut["createdAtMs"] = payloadObject["createdAtMs"].as<uint64_t>();
  }
  if (!commandDocOut["createdAtMs"].is<uint64_t>() &&
      !payloadObject["created_at_ms"].isNull()) {
    commandDocOut["createdAtMs"] = payloadObject["created_at_ms"].as<uint64_t>();
  }
  if (!commandDocOut["expiresAtMs"].is<uint64_t>() &&
      !payloadObject["expiresAtMs"].isNull()) {
    commandDocOut["expiresAtMs"] = payloadObject["expiresAtMs"].as<uint64_t>();
  }
  if (!commandDocOut["expiresAtMs"].is<uint64_t>() &&
      !payloadObject["expires_at_ms"].isNull()) {
    commandDocOut["expiresAtMs"] = payloadObject["expires_at_ms"].as<uint64_t>();
  }

  commandIdOut = selectedId;
  const char* command = commandDocOut["command"] | "";
  const char* propertyId = commandDocOut["propertyId"] | "";
  AS_MATRIX_QUEUE_ITEM_FOUND(
      runtimeId.c_str(),
      commandIdOut.c_str(),
      command,
      propertyId,
      commandDocOut["payload"].is<JsonObjectConst>());
  return QueueLoadResult::kLoaded;
}

static bool deleteQueuedCommand(const String& commandId) {
  if (commandId.isEmpty()) return false;
  return rtdbDelete(queueRootPath() + "/" + commandId);
}

static bool dispatchQueuedSimpleCommand(
    const String& commandId,
    DynamicJsonDocument& commandDoc,
    const char** reason) {
  const char* command = commandDoc["command"] | "";
  const char* propertyId = commandDoc["propertyId"] | "";
  const char* propertyScopeId = commandDoc["propertyScopeId"] | "";
  const char* matrixGatewayId = commandDoc["matrixGatewayId"] | "";
  const JsonArrayConst targetDeviceIds = commandDoc["targetDeviceIds"].as<JsonArrayConst>();
  const JsonArrayConst targetGatewayIds = commandDoc["targetGatewayIds"].as<JsonArrayConst>();
  JsonVariant payloadVariant = commandDoc["payload"];
  if (!payloadVariant.isNull() && !payloadVariant.is<JsonObject>()) {
    if (reason) *reason = "invalid_payload";
    return false;
  }

  DynamicJsonDocument payloadDoc(8192);
  if (payloadVariant.is<JsonObject>()) {
    payloadDoc.set(payloadVariant);
  } else {
    payloadDoc.to<JsonObject>();
  }
  payloadDoc["cmd_id"] = commandId;

  clearActiveSimpleCommand();
  activeSimpleCommand.active = true;
  activeSimpleCommand.dispatchAtMs = millis();
  activeSimpleCommand.lastProgressAtMs = activeSimpleCommand.dispatchAtMs;
  activeSimpleCommand.lastAttemptAtMs = 0;
  activeSimpleCommand.lastReasonCode = rpv2::REASON_NONE;
  activeSimpleCommand.createdAtMs = commandDoc["createdAtMs"] | 0ULL;
  activeSimpleCommand.expiresAtMs = commandDoc["expiresAtMs"] | 0ULL;
  copyStringToBuffer(activeSimpleCommand.commandId, sizeof(activeSimpleCommand.commandId), commandId.c_str());
  copyStringToBuffer(activeSimpleCommand.command, sizeof(activeSimpleCommand.command), command);
  copyStringToBuffer(activeSimpleCommand.propertyId, sizeof(activeSimpleCommand.propertyId), propertyId);
  copyStringToBuffer(
      activeSimpleCommand.propertyScopeId,
      sizeof(activeSimpleCommand.propertyScopeId),
      propertyScopeId);
  copyStringToBuffer(
      activeSimpleCommand.matrixGatewayId,
      sizeof(activeSimpleCommand.matrixGatewayId),
      matrixGatewayId);
  copyStringToBuffer(
      activeSimpleCommand.requestedByUid,
      sizeof(activeSimpleCommand.requestedByUid),
      commandDoc["requestedByUid"] | "");
  copyStringToBuffer(
      activeSimpleCommand.requestedByRole,
      sizeof(activeSimpleCommand.requestedByRole),
      commandDoc["requestedByRole"] | "user");
  copyStringToBuffer(
      activeSimpleCommand.polygonKind,
      sizeof(activeSimpleCommand.polygonKind),
      pickFirstText(payloadDoc["polygon_kind"], payloadDoc["polygonKind"]));
  copyStringToBuffer(
      activeSimpleCommand.originDocType,
      sizeof(activeSimpleCommand.originDocType),
      pickFirstText(payloadDoc["origin_doc_type"], payloadDoc["originDocType"]));
  copyStringToBuffer(
      activeSimpleCommand.originDocId,
      sizeof(activeSimpleCommand.originDocId),
      pickFirstText(
          payloadDoc["origin_doc_id"],
          payloadDoc["originDocId"],
          payloadDoc["operation_id"]));
  copyStringToBuffer(
      activeSimpleCommand.transportState,
      sizeof(activeSimpleCommand.transportState),
      "queued");
  if (!cacheActiveSimpleCommandPayload(payloadDoc.as<JsonVariantConst>(), reason)) {
    clearActiveSimpleCommand();
    return false;
  }

  bool sentAny = false;
  if (!targetDeviceIds.isNull() && targetDeviceIds.size() > 0) {
    if (strcmp(command, "SET_FENCE") == 0) {
      AS_MATRIX_DISPATCH_BEGIN(
          commandId.c_str(),
          activeSimpleCommand.originDocId,
          propertyId,
          (int)targetDeviceIds.size());
    }
    activeSimpleCommand.targetDeviceCommand = true;
    for (JsonVariantConst rawId : targetDeviceIds) {
      const char* textId = rawId | "";
      uint32_t deviceId = rawId.is<uint32_t>() ? rawId.as<uint32_t>() : (uint32_t)strtoul(textId, nullptr, 10);
      if (deviceId == 0) {
        if (reason) *reason = "invalid_target_device";
        clearActiveSimpleCommand();
        return false;
      }
      if (activeSimpleCommand.targetCount >= cfg::MAX_HERD_OPERATION_DEVICES) {
        if (reason) *reason = "too_many_targets";
        clearActiveSimpleCommand();
        return false;
      }
      const uint8_t idx = activeSimpleCommand.targetCount++;
      snprintf(
          activeSimpleCommand.targets[idx].targetId,
          sizeof(activeSimpleCommand.targets[idx].targetId),
          "%lu",
          (unsigned long)deviceId);
      bool ok = false;
      if (strcmp(command, "SET_FENCE") == 0) {
        const FencePointsResolution pointsResolution =
            resolveFencePoints(payloadDoc.as<JsonVariantConst>());
        ok = prepareFenceWakeSession(
            deviceId,
            payloadDoc.as<JsonVariantConst>(),
            commandId.c_str(),
            pointsResolution,
            reason);
        if (!ok) {
          AS_MATRIX_LORA_TX_FAIL(commandId.c_str(), deviceId, reason ? *reason : "unknown");
        }
      } else if (strcmp(command, "SET_PARAMS") == 0 || strcmp(command, "PING") == 0) {
        const MsgType msgType =
            strcmp(command, "SET_PARAMS") == 0 ? MsgType::SET_PARAMS : MsgType::PING;
        ok = sendLoRaJsonFrame(
            deviceId,
            msgType,
            payloadDoc.as<JsonVariantConst>(),
            reason,
            MatrixLoRaTxReason::CommandDispatch,
            "startQueuedSimpleCommandDevice",
            nullptr,
            commandId.c_str());
      }
      if (!ok) {
        clearActiveSimpleCommand();
        return false;
      }
      sentAny = true;
    }
  } else if (!targetGatewayIds.isNull() && targetGatewayIds.size() > 0) {
    activeSimpleCommand.targetDeviceCommand = false;
    JsonArray gatewayTargetIds = payloadDoc["target_gateway_ids"].to<JsonArray>();
    for (JsonVariantConst rawId : targetGatewayIds) {
      const char* textId = rawId | "";
      if (!textId[0]) continue;
      if (activeSimpleCommand.targetCount >= cfg::MAX_HERD_OPERATION_DEVICES) {
        if (reason) *reason = "too_many_targets";
        clearActiveSimpleCommand();
        return false;
      }
      const uint8_t idx = activeSimpleCommand.targetCount++;
      copyStringToBuffer(
          activeSimpleCommand.targets[idx].targetId,
          sizeof(activeSimpleCommand.targets[idx].targetId),
          textId);
      gatewayTargetIds.add(textId);
    }
    const MsgType msgType =
        strcmp(command, "SET_PARAMS") == 0 ? MsgType::SET_PARAMS : MsgType::PING;
    if (!sendLoRaJsonFrame(
            0,
            msgType,
            payloadDoc.as<JsonVariantConst>(),
            reason,
            MatrixLoRaTxReason::CommandDispatch,
            "startQueuedSimpleCommandGateway",
            nullptr,
            commandId.c_str())) {
      clearActiveSimpleCommand();
      return false;
    }
    sentAny = activeSimpleCommand.targetCount > 0;
  }

  if (!sentAny || activeSimpleCommand.targetCount == 0) {
    clearActiveSimpleCommand();
    if (reason) *reason = "no_targets";
    return false;
  }
  activeSimpleCommand.lastAttemptAtMs = millis();
  activeSimpleCommand.retryCount = 1;
  if (strcmp(command, "SET_FENCE") != 0) {
    AS_MATRIX_COMMAND_MARK_DISPATCHING_BEGIN(commandId.c_str(), command);
  }
  publishSimpleCommandResult(
      strcmp(command, "SET_FENCE") == 0 ? "paging_waiting_uplink" : "dispatching",
      nullptr);
  return true;
}

static void processNextQueuedCommand() {
  const uint32_t nowMsTick = millis();
  static uint32_t lastQueuePollSkipLogAtMs = 0;
  static uint32_t lastQueueEmptyLogAtMs = 0;
  const bool queueConfigured = queuePollingConfigured();
  const bool backhaulOpen = backhaulWindowOpen();
  const bool herdActive = herdOp.active;
  const bool simpleActive = activeSimpleCommand.active;
  if (!queueConfigured || !bindingReady || !backhaulOpen || herdActive || simpleActive) {
    if ((uint32_t)(nowMsTick - lastQueuePollSkipLogAtMs) >= 10000UL) {
      const String runtimeId = matrixCloudId();
      const char* reason = !queueConfigured
                               ? "queue_polling_not_configured"
                           : !bindingReady
                               ? "binding_not_ready"
                           : !backhaulOpen
                               ? "backhaul_window_closed"
                           : herdActive
                               ? "herding_operation_active"
                               : "simple_command_active";
      AS_MATRIX_QUEUE_POLL_SKIPPED(
          reason,
          runtimeId.c_str(),
          bindingReady,
          backhaulOpen,
          herdActive,
          simpleActive);
      lastQueuePollSkipLogAtMs = nowMsTick;
    }
    return;
  }
  const bool forceDispatch = queueDispatchRequested;
  if (!forceDispatch &&
      queuePollAtMs != 0 &&
      (uint32_t)(nowMsTick - queuePollAtMs) < 1000UL) {
    return;
  }
  queueDispatchRequested = false;
  queuePollAtMs = nowMsTick;
  lastQueuePollAtUnixMs = unixNowMs(unixNowSec());
  AS_MATRIX_INFO(
      "QUEUE_POLL_START",
      "runtimeId=%s forceDispatch=%d bindingReady=%d backhaulOpen=%d",
      matrixCloudId().c_str(),
      forceDispatch ? 1 : 0,
      bindingReady ? 1 : 0,
      backhaulOpen ? 1 : 0);

  String commandId;
  DynamicJsonDocument commandDoc(24576);
  const QueueLoadResult loadResult = loadNextQueuedCommand(commandId, commandDoc);
  if (loadResult != QueueLoadResult::kLoaded) {
    if (loadResult == QueueLoadResult::kEmpty &&
        (uint32_t)(nowMsTick - lastQueueEmptyLogAtMs) >= 10000UL) {
      const String runtimeId = matrixCloudId();
      AS_MATRIX_QUEUE_EMPTY(runtimeId.c_str(), strlen(cfg::RTDB_QUEUE_KEY));
      lastQueueEmptyLogAtMs = nowMsTick;
    }
    return;
  }

  const char* command = commandDoc["command"] | "";
  const char* propertyId = commandDoc["propertyId"] | "";
  const char* propertyScopeId = commandDoc["propertyScopeId"] | "";
  const char* matrixGatewayId = commandDoc["matrixGatewayId"] | "";
  const uint64_t expiresAtMs = commandDoc["expiresAtMs"] | 0ULL;
  const uint64_t nowMs = unixNowMs(unixNowSec());

  const char* failReason = nullptr;
  const char* failStatus = nullptr;
  if (!commandId.length() || !command[0]) {
    return;
  }

  if (strcmp(command, "SET_FENCE") == 0) {
    const char* areaId = commandDoc["payload"]["originDocId"] | commandDoc["payload"]["origin_doc_id"] | "";
    const int targetCount = commandDoc["targetDeviceIds"].as<JsonArrayConst>().size();
    const FencePointsResolution pointsResolution =
        resolveFencePoints(commandDoc["payload"].as<JsonVariantConst>());
    const int pointCount = pointsResolution.points.isNull() ? 0 : (int)pointsResolution.points.size();
    AS_MATRIX_FENCE_POINTS_RESOLVED(commandId.c_str(), pointsResolution.source, pointCount);
    AS_MATRIX_QUEUE_LOADED(
        commandId.c_str(), areaId, propertyId, propertyScopeId, targetCount, pointCount);
  }

  if (expiresAtMs != 0 && expiresAtMs <= nowMs) {
    failStatus = "expired";
    failReason = "command_expired";
    char expected[24];
    char actual[24];
    snprintf(expected, sizeof(expected), ">%llu", (unsigned long long)nowMs);
    snprintf(actual, sizeof(actual), "%llu", (unsigned long long)expiresAtMs);
    AS_MATRIX_QUEUE_ITEM_FILTERED_OUT(commandId.c_str(), "expiresAtMs", expected, actual);
  } else if (!bindingReady) {
    failStatus = "rejected";
    failReason = "property_binding_missing";
    AS_MATRIX_QUEUE_ITEM_FILTERED_OUT(commandId.c_str(), "bindingReady", "1", "0");
  } else if (strcmp(propertyId, bindingPropertyId) != 0) {
    failStatus = "rejected";
    failReason = "property_binding_mismatch";
    AS_MATRIX_QUEUE_ITEM_FILTERED_OUT(commandId.c_str(), "propertyId", bindingPropertyId, propertyId);
  } else if (!rtcmd::isValidScopeId(propertyScopeId) ||
             strcmp(propertyScopeId, bindingPropertyScopeId) != 0) {
    failStatus = "rejected";
    failReason = "property_scope_mismatch";
    AS_MATRIX_QUEUE_ITEM_FILTERED_OUT(
        commandId.c_str(),
        "propertyScopeId",
        bindingPropertyScopeId,
        propertyScopeId[0] ? propertyScopeId : "invalid_or_empty");
  } else if (bindingMatrixGatewayId[0] != '\0' &&
             strcmp(matrixGatewayId, bindingMatrixGatewayId) != 0) {
    failStatus = "rejected";
    failReason = "matrix_gateway_mismatch";
    AS_MATRIX_QUEUE_ITEM_FILTERED_OUT(
        commandId.c_str(),
        "matrixGatewayId",
        bindingMatrixGatewayId,
        matrixGatewayId);
  }

  if (failStatus) {
    if (strcmp(command, "SET_FENCE") == 0) {
      AS_MATRIX_QUEUE_REJECTED(commandId.c_str(), failReason);
    }
    publishImmediateMatrixCommandResult(
        commandId.c_str(),
        command,
        propertyId,
        propertyScopeId,
        matrixGatewayId,
        commandDoc["requestedByUid"] | "",
        commandDoc["requestedByRole"] | "user",
        commandDoc["createdAtMs"] | 0ULL,
        commandDoc["expiresAtMs"] | 0ULL,
        failStatus,
        failReason,
        commandDoc["payload"].as<JsonVariantConst>(),
        commandDoc["targetDeviceIds"].as<JsonArrayConst>(),
        commandDoc["targetGatewayIds"].as<JsonArrayConst>());
    deleteQueuedCommand(commandId);
    return;
  }

  if (strcmp(command, "SET_FENCE") == 0) {
    const char* areaId = commandDoc["payload"]["originDocId"] | commandDoc["payload"]["origin_doc_id"] | "";
    AS_MATRIX_QUEUE_ACCEPTED(commandId.c_str(), areaId, propertyId, propertyScopeId);
  }

  if (strcmp(command, "SET_HERDING_PLAN") == 0) {
    JsonVariant payloadVariant = commandDoc["payload"];
    const char* startReason = nullptr;
    DynamicJsonDocument payloadDoc(8192);
    if (payloadVariant.is<JsonObject>()) {
      payloadDoc.set(payloadVariant);
    }
    payloadDoc["cmd_id"] = commandId;
    payloadDoc["command_id"] = commandId;
    payloadDoc["scope_id"] = propertyScopeId;
    payloadDoc["property_scope_id"] = propertyScopeId;
    payloadDoc["matrix_gateway_id"] = matrixGatewayId;
    payloadDoc["requested_at_ms"] = commandDoc["createdAtMs"] | 0ULL;
    if (!payloadDoc.is<JsonObject>() ||
        !startHerdingOperation(payloadDoc.as<JsonVariantConst>(), &startReason)) {
      publishImmediateMatrixCommandResult(
          commandId.c_str(),
          command,
          propertyId,
          propertyScopeId,
          matrixGatewayId,
          commandDoc["requestedByUid"] | "",
          commandDoc["requestedByRole"] | "user",
          commandDoc["createdAtMs"] | 0ULL,
          commandDoc["expiresAtMs"] | 0ULL,
          "failed",
          startReason ? startReason : "invalid_operation_payload",
          payloadDoc.as<JsonVariantConst>(),
          commandDoc["targetDeviceIds"].as<JsonArrayConst>(),
          commandDoc["targetGatewayIds"].as<JsonArrayConst>());
    } else {
      copyStringToBuffer(herdOp.loraCommandId, sizeof(herdOp.loraCommandId), commandId.c_str());
      copyStringToBuffer(
          herdOp.propertyScopeId, sizeof(herdOp.propertyScopeId), propertyScopeId);
      herdOp.createdAtMs = commandDoc["createdAtMs"] | 0ULL;
      herdOp.expiresAtMs = commandDoc["expiresAtMs"] | 0ULL;
      publishHerdingOperationSnapshot(true, "dispatching");
    }
    deleteQueuedCommand(commandId);
    return;
  }

  if (strcmp(command, "SET_FENCE") != 0 &&
      strcmp(command, "SET_PARAMS") != 0 &&
      strcmp(command, "PING") != 0) {
    publishImmediateMatrixCommandResult(
        commandId.c_str(),
        command,
        propertyId,
        propertyScopeId,
        matrixGatewayId,
        commandDoc["requestedByUid"] | "",
        commandDoc["requestedByRole"] | "user",
        commandDoc["createdAtMs"] | 0ULL,
        commandDoc["expiresAtMs"] | 0ULL,
        "rejected",
        "unsupported_command",
        commandDoc["payload"].as<JsonVariantConst>(),
        commandDoc["targetDeviceIds"].as<JsonArrayConst>(),
        commandDoc["targetGatewayIds"].as<JsonArrayConst>());
    deleteQueuedCommand(commandId);
    return;
  }

  if (!dispatchQueuedSimpleCommand(commandId, commandDoc, &failReason)) {
    publishImmediateMatrixCommandResult(
        commandId.c_str(),
        command,
        propertyId,
        propertyScopeId,
        matrixGatewayId,
        commandDoc["requestedByUid"] | "",
        commandDoc["requestedByRole"] | "user",
        commandDoc["createdAtMs"] | 0ULL,
        commandDoc["expiresAtMs"] | 0ULL,
        "failed",
        failReason ? failReason : "lora_send_failed",
        commandDoc["payload"].as<JsonVariantConst>(),
        commandDoc["targetDeviceIds"].as<JsonArrayConst>(),
        commandDoc["targetGatewayIds"].as<JsonArrayConst>());
  }
  deleteQueuedCommand(commandId);
}

static void resetHerdingOperationState() {
  herdOp = HerdingOperationState{};
}

static int findHerdingOperationDevice(uint32_t deviceId) {
  for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
    if (herdOp.devices[i].deviceId == deviceId) return i;
  }
  return -1;
}

static uint8_t herdAssembledCount() {
  uint8_t count = 0;
  for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
    if (herdOp.devices[i].assembled || herdOp.devices[i].completed) count++;
  }
  return count;
}

static uint8_t herdCompletedCount() {
  uint8_t count = 0;
  for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
    if (herdOp.devices[i].completed) count++;
  }
  return count;
}

static bool allHerdDevicesAssembled() {
  return herdOp.deviceCount > 0 && herdAssembledCount() == herdOp.deviceCount;
}

static bool allHerdDevicesCompleted() {
  return herdOp.deviceCount > 0 && herdCompletedCount() == herdOp.deviceCount;
}

static const char* herdDeviceStatusLabel(const HerdingOperationDeviceState& device) {
  if (device.completed) return "completed";
  if (device.assembled) return "assembled";
  if (device.retryCount > 0) return "dispatching";
  return "pending";
}

static const char* herdOperationStatusLabel() {
  if (herdOp.failureReason[0] != '\0') return "failed";
  if (allHerdDevicesCompleted()) return "completed";
  if (allHerdDevicesAssembled()) return "requested";
  if (herdAssembledCount() > 0) return "awaiting_assembly";
  return "dispatching";
}

static void broadcastHerdingOperationUpdate(const char* status) {
  StaticJsonDocument<1024> packet;
  packet["type"] = "herding_operation_update";
  packet["operation_id"] = herdOp.operationId;
  packet["status"] = status;
  packet["ok"] = strcmp(status, "failed") != 0;
  packet["property_id"] = herdOp.propertyId;
  packet["matrix_gateway_id"] = herdOp.matrixGatewayId;
  packet["assembled_count"] = herdAssembledCount();
  packet["completed_count"] = herdCompletedCount();
  packet["device_count"] = herdOp.deviceCount;
  if (herdOp.failureReason[0] != '\0') packet["reason"] = herdOp.failureReason;
  String out;
  serializeJson(packet, out);
  api.broadcastTelemetry(out);
  sdlog.log(String("HERD|") + out);
}

static void publishHerdingOperationSnapshot(
    bool force,
    const char* statusOverride) {
  if (!herdOp.operationId[0]) return;

  const uint32_t nowMsTick = millis();
  if (!force && herdOp.lastStatusPublishAtMs != 0 &&
      (uint32_t)(nowMsTick - herdOp.lastStatusPublishAtMs) <
          cfg::HERD_OPERATION_STATUS_PUBLISH_MS) {
    return;
  }

  const uint32_t nowSec = unixNowSec();
  const uint64_t nowMs = unixNowMs(nowSec);
  const char* status = statusOverride ? statusOverride : herdOperationStatusLabel();
  if (strcmp(status, "requested") == 0 && herdOp.requestedAtSec == 0) {
    herdOp.requestedAtSec = nowSec;
  }
  if (strcmp(status, "completed") == 0 && herdOp.completedAtSec == 0) {
    herdOp.completedAtSec = nowSec;
  }

  DynamicJsonDocument doc(6144);
  doc["operationId"] = herdOp.operationId;
  doc["status"] = status;
  doc["propertyId"] = herdOp.propertyId;
  doc["ownerUid"] = herdOp.ownerUid;
  doc["requestedByUid"] = herdOp.requestedByUid;
  doc["requestedByRole"] = herdOp.requestedByRole;
  doc["matrixGatewayId"] = herdOp.matrixGatewayId;
  if (herdOp.propertyScopeId[0] != '\0') doc["propertyScopeId"] = herdOp.propertyScopeId;
  if (herdOp.loraCommandId[0] != '\0') doc["loraCommandId"] = herdOp.loraCommandId;
  doc["polygonKind"] = "herding";
  doc["originDocType"] = "herdingOperation";
  doc["originDocId"] = herdOp.operationId;
  doc["updatedAt"] = nowMs;
  doc["writer"] = "gateway_matrix";
  doc["matrixId"] = matrixCloudId();
  doc["writerKey"] = cfg::RTDB_WRITER_KEY;
  if (herdOp.requestedAtSec != 0) {
    doc["requestedAt"] = (uint64_t)herdOp.requestedAtSec * 1000ULL;
  }
  if (herdOp.completedAtSec != 0) {
    doc["completedAt"] = (uint64_t)herdOp.completedAtSec * 1000ULL;
  }
  if (herdOp.failureReason[0] != '\0') doc["failureReason"] = herdOp.failureReason;

  JsonArray selected = doc["selectedDeviceIds"].to<JsonArray>();
  for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
    selected.add(String(herdOp.devices[i].deviceId));
  }

  JsonArray target = doc["targetPolygon"].to<JsonArray>();
  for (uint8_t i = 0; i < herdOp.pointCount; ++i) {
    JsonObject point = target.createNestedObject();
    point["lat"] = herdOp.targetPolygon[i].lat;
    point["lon"] = herdOp.targetPolygon[i].lon;
  }

  JsonObject statuses = doc["deviceStatuses"].to<JsonObject>();
  for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
    const HerdingOperationDeviceState& device = herdOp.devices[i];
    JsonObject item = statuses.createNestedObject(String(device.deviceId));
    item["status"] = herdDeviceStatusLabel(device);
    item["retryCount"] = device.retryCount;
    item["updatedAtMs"] = device.updatedAtMs ? device.updatedAtMs : nowMs;
    if (device.phaseIndex > 0) item["phaseIndex"] = device.phaseIndex;
    if (device.lastReason[0] != '\0') item["reason"] = device.lastReason;
  }

  if (herdOp.loraCommandId[0] != '\0' && herdOp.propertyId[0] != '\0' &&
      herdOp.propertyScopeId[0] != '\0') {
    const char* resultStatus = "dispatching";
    if (strcmp(status, "requested") == 0) resultStatus = "acknowledged";
    if (strcmp(status, "completed") == 0) resultStatus = "completed";
    if (strcmp(status, "failed") == 0 || strcmp(status, "superseded") == 0) {
      resultStatus = "failed";
    }

    DynamicJsonDocument resultDoc(2048);
    resultDoc["commandId"] = herdOp.loraCommandId;
    resultDoc["command"] = "SET_HERDING_PLAN";
    resultDoc["status"] = resultStatus;
    resultDoc["createdAtMs"] = herdOp.createdAtMs;
    resultDoc["updatedAtMs"] = nowMs;
    resultDoc["expiresAtMs"] = herdOp.expiresAtMs;
    resultDoc["propertyId"] = herdOp.propertyId;
    resultDoc["propertyScopeId"] = herdOp.propertyScopeId;
    resultDoc["matrixId"] = matrixCloudId();
    resultDoc["matrixGatewayId"] = herdOp.matrixGatewayId;
    resultDoc["matrixRuntimeId"] = matrixCloudId();
    resultDoc["requestedByUid"] = herdOp.requestedByUid;
    resultDoc["requestedByRole"] = herdOp.requestedByRole;
    resultDoc["writer"] = "gateway_matrix";
    resultDoc["writerKey"] = cfg::RTDB_WRITER_KEY;
    resultDoc["polygonKind"] = "herding";
    resultDoc["originDocType"] = "herdingOperation";
    resultDoc["originDocId"] = herdOp.operationId;
    if (herdOp.failureReason[0] != '\0') resultDoc["reason"] = herdOp.failureReason;
    JsonArray resultTargets = resultDoc["targetDeviceIds"].to<JsonArray>();
    for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
      resultTargets.add(String(herdOp.devices[i].deviceId));
    }
    JsonObject resultStatuses = resultDoc["deviceResults"].to<JsonObject>();
    for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
      const HerdingOperationDeviceState& device = herdOp.devices[i];
      JsonObject item = resultStatuses.createNestedObject(String(device.deviceId));
      item["status"] = herdDeviceStatusLabel(device);
      item["retryCount"] = device.retryCount;
      if (device.lastReason[0] != '\0') item["reason"] = device.lastReason;
      item["ok"] = device.lastReason[0] == '\0';
    }
    String resultBody;
    serializeJson(resultDoc, resultBody);
    const bool matrixOk = rtdbWrite(
        "PUT",
        String("matrixCommandResults/") + matrixCloudId() + "/" + herdOp.loraCommandId,
        resultBody);
    const bool propertyOk = rtdbWrite(
        "PUT",
        String("propertyCommands/") + sanitizeRtdbKey(String(herdOp.propertyId)) + "/" +
            herdOp.loraCommandId,
        resultBody);
    bool eventOk = true;
    if (strcmp(herdOp.lastCommandStatus, resultStatus) != 0) {
      eventOk = appendPropertyCommandEvent(
          herdOp.propertyId,
          herdOp.loraCommandId,
          resultStatus,
          herdOp.failureReason[0] != '\0' ? herdOp.failureReason : nullptr,
          &resultDoc);
      copyStringToBuffer(
          herdOp.lastCommandStatus,
          sizeof(herdOp.lastCommandStatus),
          resultStatus);
    }
    if (!(matrixOk && propertyOk && eventOk)) {
      setLastCloudWriteError("herd_status", herdOp.loraCommandId);
    }
  }

  herdOp.updatedAtMs = (uint32_t)(nowMs > 0xFFFFFFFFULL ? 0xFFFFFFFFUL : nowMs);
  herdOp.lastStatusPublishAtMs = nowMsTick;
  broadcastHerdingOperationUpdate(status);
  if (strcmp(status, "completed") == 0 ||
      strcmp(status, "failed") == 0 ||
      strcmp(status, "superseded") == 0) {
    herdOp.finalized = true;
    herdOp.active = false;
  }
}

static bool sendHerdingOperationToDevice(
    HerdingOperationDeviceState& device,
    const char** reason) {
  StaticJsonDocument<1024> payload;
  payload["operation_id"] = herdOp.operationId;
  payload["cmd_id"] = herdOp.loraCommandId;
  payload["command_id"] = herdOp.loraCommandId;
  payload["scope_id"] = herdOp.propertyScopeId;
  payload["property_scope_id"] = herdOp.propertyScopeId;
  payload["matrix_gateway_id"] = herdOp.matrixGatewayId;
  payload["polygon_kind"] = "herding";
  payload["origin_doc_type"] = "herdingOperation";
  payload["origin_doc_id"] = herdOp.operationId;
  payload["requested_at_ms"] = herdOp.createdAtMs;
  JsonArray phases = payload["phases"].to<JsonArray>();
  JsonArray phase = phases.createNestedArray();
  for (uint8_t i = 0; i < herdOp.pointCount; ++i) {
    JsonArray pair = phase.createNestedArray();
    pair.add(herdOp.targetPolygon[i].lat);
    pair.add(herdOp.targetPolygon[i].lon);
  }
  const bool ok =
      sendHerdingPlanChunked(device.deviceId, payload.as<JsonVariantConst>(), reason);
  if (ok) {
    device.retryCount++;
    device.lastDispatchAtMs = millis();
    device.updatedAtMs = (uint32_t)unixNowMs(unixNowSec());
    device.lastReason[0] = '\0';
  }
  return ok;
}

static bool startHerdingOperation(const JsonVariantConst payload, const char** reason) {
  if (!payload.is<JsonObjectConst>()) {
    if (reason) *reason = "invalid_operation_payload";
    return false;
  }

  const char* operationId = payload["operation_id"] | "";
  const JsonArrayConst selectedDeviceIds =
      payload["selected_device_ids"].as<JsonArrayConst>();
  const JsonArrayConst targetPolygon = payload["target_polygon"].as<JsonArrayConst>();
  if (operationId[0] == '\0') {
    if (reason) *reason = "missing_operation_id";
    return false;
  }
  if (selectedDeviceIds.isNull() || selectedDeviceIds.size() == 0 ||
      selectedDeviceIds.size() > cfg::MAX_HERD_OPERATION_DEVICES) {
    if (reason) *reason = "invalid_selected_device_count";
    return false;
  }
  const uint8_t pointCount = (uint8_t)targetPolygon.size();
  const rtcmd::ValidationCode pointCode =
      rtcmd::validatePointCount(pointCount, cfg::MAX_POLYGON_POINTS);
  if (pointCode != rtcmd::ValidationCode::kOk) {
    if (reason) *reason = rtcmd::validationCodeToReason(pointCode);
    return false;
  }

  HerdingOperationState next;
  next.active = true;
  next.finalized = false;
  next.startedAtMs = millis();
  next.createdAtMs = payload["created_at_ms"] | (payload["requested_at_ms"] | 0ULL);
  next.expiresAtMs = payload["expires_at_ms"] | 0ULL;
  copyStringToBuffer(next.operationId, sizeof(next.operationId), operationId);
  copyStringToBuffer(next.propertyId, sizeof(next.propertyId), payload["property_id"] | "");
  copyStringToBuffer(next.ownerUid, sizeof(next.ownerUid), payload["owner_uid"] | "");
  copyStringToBuffer(
      next.requestedByUid, sizeof(next.requestedByUid), payload["requested_by_uid"] | "");
  copyStringToBuffer(
      next.requestedByRole,
      sizeof(next.requestedByRole),
      payload["requested_by_role"] | "user");
  copyStringToBuffer(
      next.matrixGatewayId,
      sizeof(next.matrixGatewayId),
      payload["matrix_gateway_id"] | "");
  const char* nextPropertyScopeId =
      pickFirstText(payload["property_scope_id"], payload["scope_id"]);
  if (!nextPropertyScopeId[0]) nextPropertyScopeId = bindingPropertyScopeId;
  copyStringToBuffer(
      next.propertyScopeId,
      sizeof(next.propertyScopeId),
      nextPropertyScopeId);
  copyStringToBuffer(
      next.loraCommandId,
      sizeof(next.loraCommandId),
      pickFirstText(payload["cmd_id"], payload["command_id"]));

  for (uint8_t i = 0; i < pointCount; ++i) {
    double lat = 0.0;
    double lon = 0.0;
    if (!readPointPair(targetPolygon[i].as<JsonArrayConst>(), lat, lon)) {
      if (reason) *reason = "invalid_target_point";
      return false;
    }
    next.targetPolygon[next.pointCount++] = HerdPoint{lat, lon};
  }

  for (JsonVariantConst rawId : selectedDeviceIds) {
    uint32_t deviceId = 0;
    if (rawId.is<uint32_t>() || rawId.is<int>()) {
      deviceId = rawId.as<uint32_t>();
    } else {
      const char* text = rawId | "";
      if (text[0] == '\0') {
        if (reason) *reason = "invalid_selected_device";
        return false;
      }
      deviceId = (uint32_t)strtoul(text, nullptr, 10);
    }
    if (deviceId == 0) {
      if (reason) *reason = "invalid_selected_device";
      return false;
    }
    next.devices[next.deviceCount].deviceId = deviceId;
    next.devices[next.deviceCount].updatedAtMs = (uint32_t)unixNowMs(unixNowSec());
    next.deviceCount++;
  }

  if (herdOp.operationId[0] != '\0' && herdOp.active) {
    publishHerdingOperationSnapshot(true, "superseded");
  }
  herdOp = next;
  publishHerdingOperationSnapshot(true, "dispatching");
  return true;
}

static void dispatchActiveHerdingOperation() {
  if (!herdOp.active || herdOp.finalized || herdOp.operationId[0] == '\0') return;

  const uint32_t nowMsTick = millis();
  if ((uint32_t)(nowMsTick - herdOp.startedAtMs) > cfg::HERD_OPERATION_TIMEOUT_MS &&
      !allHerdDevicesAssembled()) {
    copyStringToBuffer(
        herdOp.failureReason,
        sizeof(herdOp.failureReason),
        "timeout_waiting_assembly");
    for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
      if (!herdOp.devices[i].assembled && herdOp.devices[i].lastReason[0] == '\0') {
        copyStringToBuffer(
            herdOp.devices[i].lastReason,
            sizeof(herdOp.devices[i].lastReason),
            "timeout_waiting_assembly");
      }
    }
    publishHerdingOperationSnapshot(true, "failed");
    return;
  }

  if (allHerdDevicesCompleted()) {
    publishHerdingOperationSnapshot(true, "completed");
    return;
  }
  if (allHerdDevicesAssembled()) {
    publishHerdingOperationSnapshot(true, "requested");
    return;
  }

  for (uint8_t i = 0; i < herdOp.deviceCount; ++i) {
    HerdingOperationDeviceState& device = herdOp.devices[i];
    if (device.assembled || device.completed) continue;
    if (device.lastDispatchAtMs != 0 &&
        (uint32_t)(nowMsTick - device.lastDispatchAtMs) <
            cfg::HERD_OPERATION_RETRY_MS) {
      continue;
    }

    const char* sendReason = nullptr;
    if (sendHerdingOperationToDevice(device, &sendReason)) {
      publishHerdingOperationSnapshot(true, "dispatching");
      return;
    }
    copyStringToBuffer(
        device.lastReason,
        sizeof(device.lastReason),
        sendReason ? sendReason : "lora_send_failed");
    device.updatedAtMs = (uint32_t)unixNowMs(unixNowSec());
  }

  publishHerdingOperationSnapshot(false, nullptr);
}

static void handleHerdingOperationFeedback(const LoRaFrame& rx) {
  if (!herdOp.operationId[0]) return;
  if (rx.msgType != MsgType::ACK && rx.msgType != MsgType::NACK) return;

  StaticJsonDocument<256> payload;
  if (deserializeJson(payload, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return;
  }

  String command;
  if (payload["cmd"].is<const char*>()) {
    command = payload["cmd"].as<const char*>();
  } else if ((payload["cmd"] | 0) == (int)MsgType::SET_HERDING_PLAN ||
             (payload["cmd_code"] | 0) == (int)MsgType::SET_HERDING_PLAN) {
    command = "SET_HERDING_PLAN";
  }
  if (!command.equalsIgnoreCase("SET_HERDING_PLAN")) return;

  const char* operationId = payload["operation_id"] | "";
  if (operationId[0] != '\0' && strcmp(operationId, herdOp.operationId) != 0) return;

  const int idx = findHerdingOperationDevice(rx.deviceId);
  if (idx < 0) return;

  HerdingOperationDeviceState& device = herdOp.devices[idx];
  device.updatedAtMs = (uint32_t)unixNowMs(unixNowSec());
  const char* reason = payload["reason"] | "";
  const char* status = payload["status"] | "";

  if (rx.msgType == MsgType::NACK) {
    copyStringToBuffer(
        device.lastReason,
        sizeof(device.lastReason),
        reason[0] != '\0' ? reason : "nack");
    device.lastDispatchAtMs = 0;
    publishHerdingOperationSnapshot(true, nullptr);
    return;
  }

  device.assembled = true;
  if (device.assembledAtSec == 0) device.assembledAtSec = unixNowSec();
  if (reason[0] != '\0' &&
      strcmp(reason, "assembled") != 0 &&
      strcmp(reason, "applied") != 0) {
    copyStringToBuffer(device.lastReason, sizeof(device.lastReason), reason);
  } else if (status[0] != '\0' &&
             strcmp(status, "assembled") != 0 &&
             strcmp(status, "applied") != 0) {
    copyStringToBuffer(device.lastReason, sizeof(device.lastReason), status);
  } else {
    device.lastReason[0] = '\0';
  }

  if (allHerdDevicesAssembled() && herdOp.requestedAtSec == 0) {
    herdOp.requestedAtSec = unixNowSec();
  }
  publishHerdingOperationSnapshot(true, nullptr);
}

static void handleHerdingOperationEvent(const LoRaFrame& rx) {
  if (!herdOp.operationId[0] || rx.msgType != MsgType::EVENT) return;

  StaticJsonDocument<256> payload;
  if (deserializeJson(payload, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return;
  }

  const char* operationId = payload["operation_id"] | "";
  if (operationId[0] != '\0' && strcmp(operationId, herdOp.operationId) != 0) return;

  String eventType;
  if (payload["event_type"].is<const char*>()) {
    eventType = payload["event_type"].as<const char*>();
  } else if (payload["type"].is<const char*>()) {
    eventType = payload["type"].as<const char*>();
  } else {
    const int eventCode = payload["event_code"].is<int>()
                              ? payload["event_code"].as<int>()
                              : (payload["type"] | 0);
    if (eventCode == 8) eventType = "herd_phase_change";
    if (eventCode == 9) eventType = "herd_done";
  }
  eventType.toLowerCase();
  if (eventType.isEmpty()) return;

  const int idx = findHerdingOperationDevice(rx.deviceId);
  if (idx < 0) return;

  HerdingOperationDeviceState& device = herdOp.devices[idx];
  device.updatedAtMs = (uint32_t)unixNowMs(unixNowSec());

  if (eventType == "herd_phase_change") {
    const int phaseIndex = payload["phase_index"].is<int>()
                               ? payload["phase_index"].as<int>()
                               : (payload["d1"] | device.phaseIndex);
    if (phaseIndex >= 0) device.phaseIndex = (uint8_t)phaseIndex;
    publishHerdingOperationSnapshot(true, nullptr);
    return;
  }

  if (eventType == "herd_done") {
    device.assembled = true;
    device.completed = true;
    device.lastReason[0] = '\0';
    if (device.assembledAtSec == 0) device.assembledAtSec = unixNowSec();
    if (device.completedAtSec == 0) device.completedAtSec = unixNowSec();
    if (allHerdDevicesCompleted() && herdOp.completedAtSec == 0) {
      herdOp.completedAtSec = unixNowSec();
    }
    publishHerdingOperationSnapshot(true, nullptr);
  }
}

static void handleSimpleCommandFeedback(const LoRaFrame& rx) {
  if (!activeSimpleCommand.active) return;
  if (rx.msgType != MsgType::ACK && rx.msgType != MsgType::NACK) return;

  StaticJsonDocument<256> payload;
  if (deserializeJson(payload, rx.payload, rx.payloadLen) != DeserializationError::Ok) {
    return;
  }

  const char* commandId = pickFirstText(payload["cmd_id"], payload["command_id"]);
  if (strcmp(commandId, activeSimpleCommand.commandId) != 0) return;

  char targetId[32]{};
  const char* gatewayId = payload["gateway_id"] | "";
  if (gatewayId[0] != '\0') {
    copyStringToBuffer(targetId, sizeof(targetId), gatewayId);
  } else {
    snprintf(targetId, sizeof(targetId), "%lu", (unsigned long)rx.deviceId);
  }

  const char* reason = payload["reason"] | "";
  const char* status = payload["status"] | (rx.msgType == MsgType::ACK ? "completed" : "nacked");
  markActiveSimpleCommandTarget(targetId, rx.msgType == MsgType::ACK, status, reason);

  if (strcmp(activeSimpleCommand.command, "SET_FENCE") == 0) {
    if (rx.msgType == MsgType::ACK) {
      AS_MATRIX_ACK_MATCH(commandId, rx.deviceId, status, reason);
    } else {
      AS_MATRIX_NACK_MATCH(commandId, rx.deviceId, status, reason);
    }
  }

  if (rx.msgType == MsgType::NACK) {
    publishSimpleCommandResult("nacked", reason[0] ? reason : "nack");
    clearActiveSimpleCommand();
    return;
  }

  if (allActiveSimpleTargetsTerminal()) {
    if (strcmp(activeSimpleCommand.command, "SET_FENCE") == 0) {
      AS_MATRIX_RESULT_PUBLISHED(commandId, anyActiveSimpleTargetFailed() ? "failed" : "completed");
    }
    publishSimpleCommandResult(anyActiveSimpleTargetFailed() ? "failed" : "completed", nullptr);
    clearActiveSimpleCommand();
    return;
  }
  publishSimpleCommandResult("acknowledged", nullptr);
}

static void relayFrameToPeerGateways(const LoRaFrame& rx) {
  if (!cfg::GATEWAY_RELAY_ENABLED) return;
  if (!isRelayCandidate(rx)) return;
  if (!scopeMatchesBinding(rx.scopeId)) return;

  LoRaFrame relay = rx;
  for (int i = 0; i < 12; ++i) relay.nonce[i] = (uint8_t)esp_random();
  if (!sendMatrixLoRaFrame(
          relay,
          MatrixLoRaTxReason::RelayForwardValidated,
          &rx,
          "relayFrameToPeerGateways")) {
    LOGI(
        "RELAY_SUPPRESSED_UPLINK_ECHO deviceId=%lu msgType=%u seq=%lu reason=accepted_uplink_echo_guard",
        (unsigned long)rx.deviceId,
        (unsigned)rx.msgType,
        (unsigned long)rx.seq);
    return;
  }
}

static void drawStatus(const char* line1, const char* line2) {
#if RT_MATRIX_OLED_ENABLED
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(0, 0);
  display.println("RuralTech Matriz");
  display.println(line1);
  display.println(line2);
  if (cfg::FEATURE_BACKHAUL) {
    display.print("BH: ");
    display.println(backhaulOledLabel(backhaulDiag.state));
  }
  display.display();
#else
  (void)line1;
  (void)line2;
#endif
}

static void checklistLine(
    const char* component,
    bool ok,
    const char* offHint,
    const char* okDetail = nullptr) {
  if (ok) {
    if (okDetail && okDetail[0] != '\0') {
      Serial.printf("[CHECK] %-24s : OK (%s)\n", component, okDetail);
    } else {
      Serial.printf("[CHECK] %-24s : OK\n", component);
    }
    return;
  }
  Serial.printf("[CHECK] %-24s : OFF\n", component);
  if (offHint && offHint[0] != '\0') {
    LOGW("CHECKLIST %s OFF: %s", component, offHint);
  }
}

static void printBootChecklist(
    bool displayOk,
    bool wifiOk,
    bool bleInitOk,
    bool rtcOk,
    bool sdOk,
    bool loraOk,
    bool cloudConfigured,
    bool queueConfigured) {
  Serial.println("==== HW CHECKLIST | GATEWAY MATRIX ====");
  Serial.printf("[MODE ] %-24s : %u\n", "DIAG_STAGE", (unsigned)cfg::DIAG_STAGE);
  Serial.printf("[MODE ] %-24s : %s\n", "DIAG_PROFILE", cfg::DIAG_PROFILE_NAME);
  Serial.printf("[MODE ] %-24s : %s\n", "MATRIX_RUNTIME_ID", matrixCloudId().c_str());
  Serial.printf("[MODE ] %-24s : %u\n", "PROTO_VERSION", (unsigned)cfg::LORA_PROTO_VERSION);
  Serial.printf("[MODE ] %-24s : %u\n", "KEY_ID", (unsigned)cfg::LORA_KEY_ID);
  Serial.printf("[MODE ] %-24s : %u\n", "RADIO_PROFILE", (unsigned)cfg::LORA_RADIO_PROFILE_ID);
  Serial.printf(
      "[MODE ] %-24s : %s\n",
      "ANTI_REPLAY_MODE",
      cfg::DISABLE_LORA_REPLAY_FOR_TESTS ? "test-disabled" : "strict");
  Serial.printf(
      "[MODE ] %-24s : %s\n",
      "BINDING_READY",
      bindingReady ? "true" : "false");
  checklistLine(
      "NVS_SEQ_DOWN",
      seqPrefsReady,
      "Falha ao abrir NVS lora_down; revisar flash/NVS.");
#if RT_MATRIX_OLED_ENABLED
  checklistLine(
      "OLED_0x3C",
      displayOk,
      "OLED nao inicializou; revisar SDA/SCL, VCC, GND e endereco 0x3C.");
#else
  checklistLine("OLED_0x3C", true, nullptr, "desabilitado em config");
#endif
  checklistLine(
      "WIFI_AP_OTA",
      !wifiOtaEnabled || wifiOk,
      "wifi_ota_enabled=true sem AP/OTA; revisar SSID/AP e RF.");
  checklistLine(
      "BLE_PRESENCE",
      !cfg::BLE_PRESENCE_ENABLED || bleInitOk,
      "BLE nao inicializou; revisar memoria BT e stack.");
  checklistLine(
      "API_HTTP_WS",
      true,
      nullptr,
      "porta 80 + ws:81");
  checklistLine(
      "RTC_DS3231",
      rtcOk,
      "RTC indisponivel; revisar SDA/SCL, VCC, GND e bateria.");
  checklistLine(
      "SD_CARD",
      sdOk,
      "SD indisponivel; revisar CS/MOSI/MISO/SCK e cartao.");
  checklistLine(
      "LORA_RFM95",
      loraOk,
      "Falha LoRa begin; revisar CS/RST/DIO0/DIO1, antena e modulo.");
  checklistLine(
      "CLOUD_BACKHAUL_CFG",
      cloudConfigured,
      "Telemetria cloud sem credenciais validas; revisar manual_settings.local.h.");
  checklistLine(
      "QUEUE_POLLING_CFG",
      queueConfigured,
      "Polling da fila cloud indisponivel; revisar RT_CFG_RTDB_QUEUE_KEY e placeholders cloud.");
  Serial.println("=======================================");
}

void setup() {
  bootStartedAtMs = millis();
  Serial.begin(cfg::SERIAL_BAUD);
  LOGI("Boot reset_reason=%d", (int)esp_reset_reason());
#if defined(ESP_IDF_VERSION_MAJOR) && ESP_IDF_VERSION_MAJOR >= 5
  esp_task_wdt_config_t wdtConfig = {};
  wdtConfig.timeout_ms = (uint32_t)cfg::TASK_WDT_TIMEOUT_SEC * 1000U;
  wdtConfig.idle_core_mask = 0;
  wdtConfig.trigger_panic = true;
  esp_err_t wdtErr = esp_task_wdt_reconfigure(&wdtConfig);
  if (wdtErr == ESP_ERR_INVALID_STATE) {
    wdtErr = esp_task_wdt_init(&wdtConfig);
  }
  if (wdtErr != ESP_OK) {
    LOGW("TWDT setup retornou err=%d", (int)wdtErr);
  }
#else
  esp_task_wdt_init(cfg::TASK_WDT_TIMEOUT_SEC, true);
#endif
  WiFi.onEvent(onWifiEvent);
  restoreDownlinkSeq();
  loadBindingConfig();
  primeSpiChipSelectLines();

  Wire.begin(cfg::PIN_I2C_SDA, cfg::PIN_I2C_SCL);
  bool displayOk = true;
#if RT_MATRIX_OLED_ENABLED
  displayOk = display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  if (!displayOk) LOGW("OLED indisponivel");
#endif
  drawStatus("Boot", cfg::FW_VERSION);

  bool wifiOk = !cfg::FEATURE_WIFI_AP;
  if (cfg::FEATURE_WIFI_AP && wifiOtaEnabled) {
    wifiOk = setupWiFi();
    if (wifiOk) setupOta();
  }
  bool bleInitOk = !cfg::FEATURE_BLE;
  if (cfg::FEATURE_BLE) {
    const String nodeId = gatewayNodeId();
    bleInitOk = blePresence.begin(
        BleNodeKind::MATRIX,
        nodeId,
        gatewayAdvName(nodeId),
        cfg::BLE_COMPANY_ID,
        cfg::BLE_SERVICE_UUID);
    blePresence.setEnabled(shouldBlePresenceBeEnabled());
    blePresence.setFlags(wifiOtaEnabled, WiFi.status() == WL_CONNECTED);
  }
  if (cfg::FEATURE_HTTP || cfg::FEATURE_WS) {
    api.begin();
  }
  const bool rtcOk = rtc.begin();
  if (!rtcOk) LOGW("RTC indisponivel");
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");

  bool sdOk = !cfg::FEATURE_SD;
  if (cfg::FEATURE_SD) {
    sdOk = sdlog.begin(cfg::PIN_SD_CS);
    if (!sdOk) LOGW("SD indisponivel");
  }
  const bool loraOk = lora.begin();
  if (!loraOk) LOGE("LoRa indisponivel");
  const bool cloudConfigured = cloudTelemetryConfigured();
  const bool queueConfigured = queuePollingConfigured();
  setWatchdogEnabled(wifiOtaEnabled);
  printBootChecklist(
      displayOk,
      wifiOk,
      bleInitOk,
      rtcOk,
      sdOk,
      loraOk,
      cloudConfigured,
      queueConfigured);

  LOGI("Matrix diag_stage=%u profile=%s", (unsigned)cfg::DIAG_STAGE, cfg::DIAG_PROFILE_NAME);
  LOGW("Matrix anti_replay_test_mode=%d", cfg::DISABLE_LORA_REPLAY_FOR_TESTS ? 1 : 0);
  LOGI("Matrix lora_only_bench_mode=%d", cfg::DIAG_STAGE == 1 ? 1 : 0);
  LOGI(
      "Matrix cloud_preflight runtimeId=%s cloudConfigured=%d queuePollingConfigured=%d backhaulFeature=%d cloudFeature=%d",
      matrixCloudId().c_str(),
      cloudConfigured ? 1 : 0,
      queueConfigured ? 1 : 0,
      cfg::FEATURE_BACKHAUL ? 1 : 0,
      cfg::FEATURE_CLOUD ? 1 : 0);
  LOGI(
      "Matrix boot fw=%s diag_stage=%u proto_version=%u key_id=%u radio_profile=%u bindingReady=%d profile_name=%s",
      cfg::FW_VERSION,
      (unsigned)cfg::DIAG_STAGE,
      (unsigned)cfg::LORA_PROTO_VERSION,
      (unsigned)cfg::LORA_KEY_ID,
      (unsigned)cfg::LORA_RADIO_PROFILE_ID,
      bindingReady ? 1 : 0,
      cfg::DIAG_PROFILE_NAME);
  {
    const buildinfo::BuildInfo build = buildinfo::current();
    LOGI(
        "FW_PROVENANCE role=matrix gitSha=%s gitShort=%s dirty=%s buildUtc=%s buildSource=%s firmwareVersion=%s profile=%s diagStage=%u runtimeId=%s",
        build.gitSha,
        build.gitShortSha,
        buildinfo::dirtyString(build.dirty),
        build.buildUtc,
        build.buildSource,
        cfg::FW_VERSION,
        cfg::DIAG_PROFILE_NAME,
        (unsigned)cfg::DIAG_STAGE,
        matrixCloudId().c_str());
    LOGI(
        "RPV2_PLANNER_REV rev=canonical_fence_planner_v1 gitShort=%s",
        build.gitShortSha);
  }
  LOGI("Gateway matriz pronto fw=%s", cfg::FW_VERSION);
}

void loop() {
  feedWatchdogIfEnabled();
  ensureWifiOtaServices();
  feedWatchdogIfEnabled();
  if (processPrioritySimpleCommandFeedbackWindow()) {
    feedWatchdogIfEnabled();
    delay(1);
    return;
  }
  flushDeferredAcceptedUplinksIfReady();
  if (cfg::FEATURE_BACKHAUL && backhaulWindowOpen()) {
    ensureCloudBackhaulConnected();
  }
  if (cfg::FEATURE_BACKHAUL) {
    emitBackhaulHeartbeatIfNeeded(millis());
  }
  if (cfg::FEATURE_CLOUD && backhaulWindowOpen()) {
    publishMatrixRuntimeMirrors(false);
  }
  if (cfg::FEATURE_CLOUD) {
    pollQueueCommandStream();
  }
  feedWatchdogIfEnabled();
  const bool apClientConnected = wifiApClientConnected();
  if (wifiOtaEnabled && cfg::FEATURE_OTA && cfg::OTA_ENABLED) {
    ArduinoOTA.handle();
    feedWatchdogIfEnabled();
    if (otaUploadInProgress) {
      delay(2);
      return;
    }
  }
  if (apClientConnected) {
    static uint32_t lastApClientLoopLogAtMs = 0;
    const uint32_t now = millis();
    if (now - lastApClientLoopLogAtMs >= 10000UL) {
      lastApClientLoopLogAtMs = now;
      LOGI("Cliente no AP ativo; mantendo loop LoRa/cloud (n=%d)", WiFi.softAPgetStationNum());
    }
  }
  if (cfg::FEATURE_BLE) {
    const bool bleEnabled = shouldBlePresenceBeEnabled();
    blePresence.setEnabled(bleEnabled);
    blePresence.setFlags(wifiOtaEnabled, WiFi.status() == WL_CONNECTED);
    if (bleEnabled) blePresence.loop();
  }
  feedWatchdogIfEnabled();
  if ((cfg::FEATURE_HTTP || cfg::FEATURE_WS) &&
      (!cfg::FEATURE_WIFI_AP || (wifiOtaEnabled && WiFi.getMode() != WIFI_OFF))) {
    api.loop();
  }
  feedWatchdogIfEnabled();

  LoRaFrame rx;
  if (lora.receive(rx)) {
    if (tryHandlePendingWakePageAckFastPath(rx)) {
      feedWatchdogIfEnabled();
    } else if (!scopeMatchesBinding(rx.scopeId)) {
      LOGW(
          "scope_reject device=%lu msg=%u seq=%lu scope=%s ready=%d",
          (unsigned long)rx.deviceId,
          (unsigned)rx.msgType,
          (unsigned long)rx.seq,
          scopeIdToHex(rx.scopeId).c_str(),
          bindingReady ? 1 : 0);
    } else {
      if (rx.msgType == MsgType::SET_PARAMS) {
        StaticJsonDocument<256> params;
        if (deserializeJson(params, rx.payload, rx.payloadLen) == DeserializationError::Ok) {
          bool wifiEnabled = false;
          const JsonVariantConst payload = params.as<JsonVariantConst>();
          const bool hasWifiField = parseWifiOtaParam(payload, wifiEnabled);
          const JsonVariantConst requestedByAdmin = payload["requested_by_admin"];
          const rtcmd::ValidationCode setParamsCode = rtcmd::validateSetParamsPayload(
              hasWifiField,
              wifiEnabled,
              requestedByAdmin.is<bool>() && requestedByAdmin.as<bool>(),
              payload["requested_by_role"] | "",
              payload["actor_role"] | "");
          if (setParamsCode == rtcmd::ValidationCode::kOk && targetIncludesGateway(payload)) {
            applyWifiOtaMode(wifiEnabled, "LoRa");
          } else if (setParamsCode == rtcmd::ValidationCode::kAdminRequiredForLoraOnly) {
            LOGW("SET_PARAMS LoRa rejeitado: admin requerido para LoRa-only");
          }
        }
      }
      tryHandleWakePageImmediatelyAfterAcceptedUplink(rx, lora.lastAcceptedRxAtMs());
      enqueueAcceptedUplink(rx);
      if (activeSimpleCommand.active) {
        scheduleActiveSimpleCommandRetryForRx(rx);
      }
    }
  }
  feedWatchdogIfEnabled();

  if (api.hasPendingCommand()) {
    StaticJsonDocument<4096> cmd;
    if (api.popCommand(cmd)) {
      const String type = cmd["type"] | "send_command";
      if (type == "start_herding_operation") {
        const JsonVariantConst payload = cmd["payload"].as<JsonVariantConst>();
        const char* failReason = nullptr;
        const bool ok = startHerdingOperation(payload, &failReason);
        StaticJsonDocument<256> res;
        res["type"] = "herding_operation_update";
        res["operation_id"] = payload["operation_id"] | "";
        res["status"] = ok ? "dispatching" : "failed";
        res["ok"] = ok;
        if (!ok && failReason) res["reason"] = failReason;
        String out;
        serializeJson(res, out);
        api.broadcastTelemetry(out);
        if (cfg::FEATURE_SD) sdlog.log(String("HERD_CMD|") + out);
      } else {
        const String command = cmd["command"] | "PING";
        const JsonVariantConst payload = cmd["payload"].as<JsonVariantConst>();
        bool handledLocally = false;
        if (command == "SET_BINDING") {
          const char* failReason = nullptr;
          const bool ok = persistBindingConfig(payload, &failReason);
          StaticJsonDocument<256> res;
          res["type"] = "command_result";
          res["ok"] = ok;
          res["command"] = command;
          res["supports_scoped_lora"] = true;
          res["binding_ready"] = bindingReady;
          if (bindingPropertyId[0]) res["property_id"] = bindingPropertyId;
          if (bindingPropertyScopeId[0]) res["property_scope_id"] = bindingPropertyScopeId;
          if (bindingMatrixGatewayId[0]) res["matrix_gateway_id"] = bindingMatrixGatewayId;
          res["binding_version"] = bindingVersion;
          if (!ok && failReason) res["reason"] = failReason;
          String out;
          serializeJson(res, out);
          api.broadcastTelemetry(out);
          if (cfg::FEATURE_SD) sdlog.log(String("CFG|") + out);
          if (ok && cfg::FEATURE_CLOUD) publishMatrixRuntimeMirrors(true);
          publishHerdingOperationSnapshot(false, nullptr);
          handledLocally = true;
        }

        if (handledLocally) {
          dispatchActiveHerdingOperation();
          feedWatchdogIfEnabled();
          return;
        }

        bool localToggleRequested = false;
        bool localWifiEnabled = wifiOtaEnabled;
        bool requestedWifiEnabled = true;
        rtcmd::ValidationCode setParamsCode = rtcmd::ValidationCode::kOk;
        if (command == "SET_PARAMS") {
          const bool hasWifiField =
              parseWifiOtaParam(payload, requestedWifiEnabled);
          const JsonVariantConst requestedByAdmin = payload["requested_by_admin"];
          setParamsCode = rtcmd::validateSetParamsPayload(
              hasWifiField,
              requestedWifiEnabled,
              requestedByAdmin.is<bool>() && requestedByAdmin.as<bool>(),
              payload["requested_by_role"] | "",
              payload["actor_role"] | "");
          if (setParamsCode == rtcmd::ValidationCode::kOk &&
              targetIncludesGateway(payload)) {
            localToggleRequested = true;
            localWifiEnabled = requestedWifiEnabled;
          }
        }

        const uint32_t deviceId = cmd["device_id"] | 0;
        bool shouldRelayLoRa = !(command == "SET_PARAMS" && !targetIncludesCollars(payload));
        const bool setParamsRejected =
            command == "SET_PARAMS" && setParamsCode != rtcmd::ValidationCode::kOk;
        const uint64_t commandScopeId = parseScopeIdHex(payload["scope_id"]);
        if (!bindingReady) {
          shouldRelayLoRa = false;
        } else if (commandScopeId != 0 && !scopeMatchesBinding(commandScopeId)) {
          shouldRelayLoRa = false;
        }
        if (setParamsRejected) {
          shouldRelayLoRa = false;
          localToggleRequested = false;
        }

        const MsgType msgType = command == "SET_FENCE" ? MsgType::SET_FENCE :
                                command == "SET_HERDING_PLAN" ? MsgType::SET_HERDING_PLAN :
                                command == "SET_PARAMS" ? MsgType::SET_PARAMS : MsgType::PING;

        bool ok = true;
        const char* failReason = nullptr;
        if (setParamsRejected) {
          ok = false;
          failReason = rtcmd::validationCodeToReason(setParamsCode);
        } else if (!bindingReady) {
          ok = false;
          failReason = "property_binding_missing";
        } else if (commandScopeId != 0 && !scopeMatchesBinding(commandScopeId)) {
          ok = false;
          failReason = "property_scope_mismatch";
        } else if (shouldRelayLoRa) {
          if (command == "SET_FENCE") {
            ok = sendFenceCommandChunked(deviceId, payload, &failReason);
          } else if (command == "SET_HERDING_PLAN") {
            ok = sendHerdingPlanChunked(deviceId, payload, &failReason);
          } else {
            ok = sendLoRaJsonFrame(
                deviceId,
                msgType,
                payload,
                &failReason,
                MatrixLoRaTxReason::CommandDispatch,
                "apiSendCommand",
                nullptr,
                nullptr);
          }
        }

        StaticJsonDocument<256> res;
        res["type"] = "command_result";
        res["ok"] = ok;
        res["device_id"] = deviceId;
        res["command"] = command;
        if (!ok && failReason) res["reason"] = failReason;
        String out;
        serializeJson(res, out);
        api.broadcastTelemetry(out);
        if (cfg::FEATURE_SD) sdlog.log(String("DL|") + out);

        if (localToggleRequested) {
          applyWifiOtaMode(localWifiEnabled, "WiFi");
        } else {
          publishHerdingOperationSnapshot(false, nullptr);
        }
      }
    }
  }

  if (cfg::FEATURE_CLOUD) processNextQueuedCommand();
  flushDeferredAcceptedUplinksIfReady();
  processQueuedAcceptedUplinks();
  processPendingWakeSessions();
  if (activeSimpleCommand.active) {
    processScheduledActiveSimpleCommandRetry();
    const uint32_t nowTick = millis();
    const bool recentRawRx =
        lora.lastRawRxAtMs() != 0 &&
        (uint32_t)(nowTick - lora.lastRawRxAtMs()) < cfg::SIMPLE_COMMAND_RAW_RX_HOLDOFF_MS;
    const bool allowBlindPeriodicRetry =
        !activeSimpleCommand.targetDeviceCommand &&
        strcmp(activeSimpleCommand.command, "SET_FENCE") != 0;
    if (allowBlindPeriodicRetry &&
        !activeSimpleCommand.targetedRetryPending &&
        !recentRawRx) {
      resendActiveSimpleCommand(nullptr, nullptr);
    }
    const uint64_t nowMs = unixNowMs(unixNowSec());
    if (activeSimpleCommand.expiresAtMs != 0 && nowMs >= activeSimpleCommand.expiresAtMs) {
      publishSimpleCommandResult("failed", "command_timeout");
      clearActiveSimpleCommand();
    } else {
      checkSetFencePlannerDispatchStall(nowTick, nowMs);
    }
  }
  dispatchActiveHerdingOperation();
  feedWatchdogIfEnabled();

  delay(5);
}
