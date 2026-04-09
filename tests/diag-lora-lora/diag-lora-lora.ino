#include <Arduino.h>
#include <SPI.h>
#include <RadioLib.h>
#include <time.h>
#include <sys/time.h>
#include <stdio.h>
#include <string.h>

namespace diag {
constexpr uint32_t SERIAL_BAUD = 115200;
constexpr uint32_t TURN_INTERVAL_MS = 500;
constexpr uint32_t REPLY_TIMEOUT_MS = 900;
constexpr uint32_t LOOP_IDLE_MS = 5;
constexpr uint32_t ACQUIRE_BACKOFF_MIN_MS = 120;
constexpr uint32_t ACQUIRE_BACKOFF_SPREAD_MS = 280;
constexpr uint32_t RESYNC_BACKOFF_MIN_MS = 650;
constexpr uint32_t RESYNC_BACKOFF_SPREAD_MS = 300;
constexpr uint16_t ACQUIRE_RX_TIMEOUT_SYMBOLS = 24;
constexpr uint16_t REPLY_RX_TIMEOUT_SYMBOLS = 220;

constexpr int PIN_SPI_SCK = 18;
constexpr int PIN_SPI_MISO = 19;
constexpr int PIN_SPI_MOSI = 23;
constexpr int PIN_LORA_CS = 5;
constexpr int PIN_LORA_RST = 14;
constexpr int PIN_LORA_DIO0 = 27;
constexpr int PIN_LORA_DIO1 = 33;

constexpr float LORA_FREQ_MHZ = 915.0;
constexpr uint8_t LORA_SF = 9;
constexpr uint8_t LORA_CR = 7;
constexpr float LORA_BW = 125.0;
constexpr uint8_t LORA_SYNC_WORD = 0x12;

constexpr size_t SERIAL_LINE_MAX = 48;
constexpr size_t NODE_ID_LEN = 12;
constexpr size_t TIMESTAMP_BUFFER_LEN = 24;
constexpr size_t PAYLOAD_BUFFER_LEN = 96;
constexpr char PAYLOAD_PREFIX[] = "diag-lora-lora";
}

SX1276 radio = new Module(
    diag::PIN_LORA_CS,
    diag::PIN_LORA_DIO0,
    diag::PIN_LORA_RST,
    diag::PIN_LORA_DIO1);

enum class SyncState : uint8_t {
  Acquiring,
  WaitingTurn,
  WaitingReply,
};

bool radioReady = false;
uint32_t nextSendAtMs = UINT32_MAX;
uint32_t lastSendAtMs = 0;
uint32_t packetSeq = 0;
bool waitingForPeerReply = false;
SyncState syncState = SyncState::Acquiring;
uint32_t acquireDeadlineMs = 0;
char serialLine[diag::SERIAL_LINE_MAX] = {0};
size_t serialLineLen = 0;
char localNodeId[diag::NODE_ID_LEN + 1] = {0};

int monthFromShortName(const char* monthText) {
  static const char* const kMonths[] = {
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  };

  for (int index = 0; index < 12; ++index) {
    if (strncmp(monthText, kMonths[index], 3) == 0) return index + 1;
  }
  return 0;
}

bool applyClock(struct tm* timeInfo) {
  if (timeInfo == nullptr) return false;
  const time_t epoch = mktime(timeInfo);
  if (epoch < 0) return false;

  timeval tv = {};
  tv.tv_sec = epoch;
  tv.tv_usec = 0;
  return settimeofday(&tv, nullptr) == 0;
}

bool seedClockFromBuildTime() {
  char monthText[4] = {0};
  int day = 0;
  int year = 0;
  int hour = 0;
  int minute = 0;
  int second = 0;

  if (sscanf(__DATE__, "%3s %d %d", monthText, &day, &year) != 3) return false;
  if (sscanf(__TIME__, "%d:%d:%d", &hour, &minute, &second) != 3) return false;

  const int month = monthFromShortName(monthText);
  if (month == 0) return false;

  struct tm buildTime = {};
  buildTime.tm_year = year - 1900;
  buildTime.tm_mon = month - 1;
  buildTime.tm_mday = day;
  buildTime.tm_hour = hour;
  buildTime.tm_min = minute;
  buildTime.tm_sec = second;
  buildTime.tm_isdst = -1;
  return applyClock(&buildTime);
}

bool parseClockCommand(const char* rawText, struct tm* parsedTime) {
  if (rawText == nullptr || parsedTime == nullptr) return false;

  int year = 0;
  int month = 0;
  int day = 0;
  int hour = 0;
  int minute = 0;
  int second = 0;
  const int fields = sscanf(
      rawText,
      "TIME=%d-%d-%d %d:%d:%d",
      &year,
      &month,
      &day,
      &hour,
      &minute,
      &second);
  if (fields != 6) return false;
  if (year < 2024 || month < 1 || month > 12 || day < 1 || day > 31) return false;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) return false;

  *parsedTime = {};
  parsedTime->tm_year = year - 1900;
  parsedTime->tm_mon = month - 1;
  parsedTime->tm_mday = day;
  parsedTime->tm_hour = hour;
  parsedTime->tm_min = minute;
  parsedTime->tm_sec = second;
  parsedTime->tm_isdst = -1;
  return true;
}

bool formatTimestamp(char* out, size_t outLen) {
  if (out == nullptr || outLen == 0) return false;

  const time_t now = time(nullptr);
  if (now <= 0) return false;

  struct tm localNow = {};
  if (localtime_r(&now, &localNow) == nullptr) return false;

  return strftime(out, outLen, "%Y-%m-%d %H:%M:%S", &localNow) > 0;
}

void printClockHelp() {
  Serial.println("para ajustar a hora real use: TIME=AAAA-MM-DD HH:MM:SS");
}

void populateLocalNodeId() {
  const uint64_t mac = ESP.getEfuseMac() & 0xFFFFFFFFFFFFULL;
  snprintf(
      localNodeId,
      sizeof(localNodeId),
      "%012llX",
      static_cast<unsigned long long>(mac));
}

uint32_t macSeed() {
  const uint64_t mac = ESP.getEfuseMac();
  return static_cast<uint32_t>(mac ^ (mac >> 16) ^ (mac >> 32));
}

uint32_t computeAcquireBackoffMs() {
  return diag::ACQUIRE_BACKOFF_MIN_MS + (macSeed() % diag::ACQUIRE_BACKOFF_SPREAD_MS);
}

uint32_t computeResyncBackoffMs() {
  return diag::RESYNC_BACKOFF_MIN_MS +
         ((macSeed() + (packetSeq * 97U)) % diag::RESYNC_BACKOFF_SPREAD_MS);
}

bool parseSyncPayload(
    const String& text,
    char* senderNodeId,
    size_t senderNodeIdLen,
    uint32_t* seqOut) {
  if (senderNodeId == nullptr || senderNodeIdLen == 0 || seqOut == nullptr) return false;

  char senderBuf[diag::NODE_ID_LEN + 1] = {0};
  unsigned long parsedSeq = 0;
  char timestampBuf[diag::TIMESTAMP_BUFFER_LEN] = {0};
  const int fields = sscanf(
      text.c_str(),
      "diag-lora-lora|%12[^|]|%lu|%23[^\n]",
      senderBuf,
      &parsedSeq,
      timestampBuf);
  if (fields != 3) return false;

  strncpy(senderNodeId, senderBuf, senderNodeIdLen - 1);
  senderNodeId[senderNodeIdLen - 1] = '\0';
  *seqOut = static_cast<uint32_t>(parsedSeq);
  return true;
}

void scheduleSyncSend(uint32_t delayMs) {
  nextSendAtMs = millis() + delayMs;
}

void scheduleAcquireAttempt(uint32_t delayMs, const char* reason) {
  waitingForPeerReply = false;
  syncState = SyncState::Acquiring;
  nextSendAtMs = UINT32_MAX;
  acquireDeadlineMs = millis() + delayMs;

  if (reason != nullptr) {
    Serial.printf(
        "sincronizacao reiniciada (%s) em %lu ms\n",
        reason,
        static_cast<unsigned long>(delayMs));
  }
}

void scheduleResync(const char* reason) {
  scheduleAcquireAttempt(computeResyncBackoffMs(), reason);
}

int receiveWithTimeout(uint16_t timeoutSymbols, String* outText) {
  if (outText == nullptr) return RADIOLIB_ERR_UNKNOWN;

  const int startState = radio.startReceive(timeoutSymbols, 0, 0, 0);
  if (startState != RADIOLIB_ERR_NONE) return startState;

  while (!digitalRead(diag::PIN_LORA_DIO0)) {
    if (digitalRead(diag::PIN_LORA_DIO1)) {
      return RADIOLIB_ERR_RX_TIMEOUT;
    }
    yield();
  }

  return radio.readData(*outText);
}

bool handleReceivedPacket(uint16_t timeoutSymbols) {
  String text;
  const int state = receiveWithTimeout(timeoutSymbols, &text);
  if (state == RADIOLIB_ERR_NONE) {
    Serial.print("recebido - ");
    Serial.println(text);

    char senderNodeId[diag::NODE_ID_LEN + 1] = {0};
    uint32_t remoteSeq = 0;
    if (parseSyncPayload(text, senderNodeId, sizeof(senderNodeId), &remoteSeq) &&
        strcmp(senderNodeId, localNodeId) != 0) {
      waitingForPeerReply = false;
      scheduleSyncSend(diag::TURN_INTERVAL_MS);
      syncState = SyncState::WaitingTurn;
      Serial.printf(
          "proximo envio agendado em %lu ms apos pacote de %s seq=%lu\n",
          static_cast<unsigned long>(diag::TURN_INTERVAL_MS),
          senderNodeId,
          static_cast<unsigned long>(remoteSeq));
    }
    return true;
  }

  if (state == RADIOLIB_ERR_CRC_MISMATCH) {
    Serial.println("falha ao ler pacote recebido - crc_mismatch");
    return false;
  }

  if (state != RADIOLIB_ERR_RX_TIMEOUT) {
    Serial.printf("falha ao ler pacote recebido - codigo=%d\n", state);
  }
  return false;
}

void sendTimestampPacket() {
  char timestamp[diag::TIMESTAMP_BUFFER_LEN] = {0};
  char payload[diag::PAYLOAD_BUFFER_LEN] = {0};

  if (!formatTimestamp(timestamp, sizeof(timestamp))) {
    strncpy(timestamp, "sem-tempo-valido", sizeof(timestamp) - 1);
  }

  ++packetSeq;
  snprintf(
      payload,
      sizeof(payload),
      "%s|%s|%lu|%s",
      diag::PAYLOAD_PREFIX,
      localNodeId,
      static_cast<unsigned long>(packetSeq),
      timestamp);

  const int standbyState = radio.standby();
  if (standbyState != RADIOLIB_ERR_NONE) {
    Serial.printf("falha ao preparar envio - codigo=%d\n", standbyState);
  }

  const int state = radio.transmit(payload);
  if (state == RADIOLIB_ERR_NONE) {
    Serial.println("envio feito com sucesso");
    lastSendAtMs = millis();
    waitingForPeerReply = true;
    nextSendAtMs = UINT32_MAX;
    syncState = SyncState::WaitingReply;
  } else {
    Serial.printf("falha no envio - codigo=%d\n", state);
    scheduleResync("falha_no_envio");
  }
}

void handleSerialClockCommand() {
  while (Serial.available() > 0) {
    const int raw = Serial.read();
    if (raw < 0) continue;

    const char ch = static_cast<char>(raw);
    if (ch == '\r') continue;

    if (ch == '\n') {
      serialLine[serialLineLen] = '\0';
      if (serialLineLen > 0) {
        struct tm parsedTime = {};
        if (parseClockCommand(serialLine, &parsedTime)) {
          if (applyClock(&parsedTime)) {
            Serial.println("hora ajustada com sucesso");
          } else {
            Serial.println("falha ao ajustar hora");
          }
        } else {
          Serial.println("comando invalido");
          printClockHelp();
        }
      }
      serialLineLen = 0;
      continue;
    }

    if (serialLineLen + 1 < sizeof(serialLine)) {
      serialLine[serialLineLen++] = ch;
      continue;
    }

    serialLineLen = 0;
    Serial.println("linha serial muito longa");
  }
}

bool isTimeToSend(uint32_t nowMs, uint32_t scheduledMs) {
  return static_cast<int32_t>(nowMs - scheduledMs) >= 0;
}

void setup() {
  Serial.begin(diag::SERIAL_BAUD);
  delay(1200);

  Serial.println();
  Serial.println("diag-lora-lora");
  Serial.println("pinagem LoRa: CS=5 RST=14 DIO0=27 DIO1=33 SCK=18 MISO=19 MOSI=23");

  if (seedClockFromBuildTime()) {
    Serial.println("relogio iniciado com data/hora de compilacao");
  } else {
    Serial.println("falha ao iniciar relogio com data/hora de compilacao");
  }
  printClockHelp();

  SPI.begin(diag::PIN_SPI_SCK, diag::PIN_SPI_MISO, diag::PIN_SPI_MOSI, diag::PIN_LORA_CS);

  const int state = radio.begin(
      diag::LORA_FREQ_MHZ,
      diag::LORA_BW,
      diag::LORA_SF,
      diag::LORA_CR,
      diag::LORA_SYNC_WORD);
  if (state != RADIOLIB_ERR_NONE) {
    Serial.printf("falha no begin LoRa - codigo=%d\n", state);
    return;
  }

  radioReady = true;
  populateLocalNodeId();
  const uint32_t initialOffsetMs = computeAcquireBackoffMs();
  scheduleAcquireAttempt(initialOffsetMs, nullptr);
  Serial.printf("node_id: %s\n", localNodeId);
  Serial.printf(
      "backoff inicial de sincronizacao: %lu ms\n",
      static_cast<unsigned long>(initialOffsetMs));
}

void loop() {
  handleSerialClockCommand();

  if (!radioReady) {
    delay(1000);
    return;
  }

  const uint32_t nowMs = millis();
  if (syncState == SyncState::WaitingTurn) {
    if (isTimeToSend(nowMs, nextSendAtMs)) {
      sendTimestampPacket();
    }
    delay(diag::LOOP_IDLE_MS);
    return;
  }

  if (syncState == SyncState::Acquiring) {
    if (handleReceivedPacket(diag::ACQUIRE_RX_TIMEOUT_SYMBOLS)) {
      delay(diag::LOOP_IDLE_MS);
      return;
    }

    if (isTimeToSend(nowMs, acquireDeadlineMs)) {
      sendTimestampPacket();
    }
    delay(diag::LOOP_IDLE_MS);
    return;
  }

  if (handleReceivedPacket(diag::REPLY_RX_TIMEOUT_SYMBOLS)) {
    delay(diag::LOOP_IDLE_MS);
    return;
  }

  if (waitingForPeerReply &&
      isTimeToSend(nowMs, lastSendAtMs + diag::REPLY_TIMEOUT_MS)) {
    scheduleResync("timeout_sem_resposta");
  }

  delay(diag::LOOP_IDLE_MS);
}
