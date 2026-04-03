#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_MLX90614.h>
#include <TinyGPSPlus.h>
#include <math.h>
#include <string.h>

namespace diag {
constexpr int PIN_I2C_SDA = 21;
constexpr int PIN_I2C_SCL = 22;
constexpr int GPS_PIN_PAIRS[][2] = {
    {16, 17},
    {17, 16},
    {4, 2},
    {2, 4},
};
constexpr uint32_t GPS_BAUDS[] = {9600, 4800, 19200, 38400, 57600, 115200};
constexpr uint32_t GPS_PROBE_WINDOW_MS = 1500;
constexpr uint32_t GPS_REPORT_MS = 5000;
constexpr uint8_t I2C_SCAN_BUFFER_MAX = 32;
constexpr uint8_t MLX_CANDIDATE_ADDRS[] = {0x5A, 0x5B, 0x5C, 0x5D};
constexpr uint8_t MLX_RETRIES = 10;
constexpr uint16_t MLX_RETRY_DELAY_MS = 150;
constexpr uint32_t I2C_CLOCK_HZ = 100000;
constexpr uint32_t I2C_CLOCK_SLOW_HZ = 50000;
}

struct GpsProbeResult {
  int rxPin = -1;
  int txPin = -1;
  uint32_t baud = 0;
  uint32_t bytes = 0;
  uint32_t dollar = 0;
  char sample[33] = {0};
};

HardwareSerial gpsSerial(1);
Adafruit_MLX90614 mlx;
TinyGPSPlus gpsParser;

bool gpsLiveConfigured = false;
GpsProbeResult gpsLiveConfig;
uint32_t gpsLiveBytes = 0;
uint32_t gpsLiveDollar = 0;
uint32_t gpsLiveLines = 0;
uint32_t gpsLastReportMs = 0;

void appendSample(char* sample, size_t sampleLen, char c) {
  const size_t curLen = strlen(sample);
  if (curLen + 1 >= sampleLen) return;
  sample[curLen] = (c >= 32 && c <= 126) ? c : '.';
  sample[curLen + 1] = '\0';
}

bool probeI2cAddress(uint8_t address) {
  Wire.beginTransmission(address);
  return Wire.endTransmission() == 0;
}

uint8_t scanI2cBus(uint8_t* addresses, uint8_t maxAddrs) {
  uint8_t found = 0;
  for (uint8_t addr = 1; addr < 127; ++addr) {
    if (!probeI2cAddress(addr)) continue;
    if (found < maxAddrs) addresses[found] = addr;
    ++found;
  }
  return found;
}

void printI2cScan() {
  uint8_t addresses[diag::I2C_SCAN_BUFFER_MAX] = {0};
  const uint8_t found = scanI2cBus(addresses, diag::I2C_SCAN_BUFFER_MAX);
  Serial.printf("[I2C] found=%u", found);
  if (found == 0) {
    Serial.println(" (none)");
    return;
  }
  Serial.print(" [");
  const uint8_t printCount = found > diag::I2C_SCAN_BUFFER_MAX ? diag::I2C_SCAN_BUFFER_MAX : found;
  for (uint8_t i = 0; i < printCount; ++i) {
    if (i > 0) Serial.print(",");
    Serial.printf("0x%02X", addresses[i]);
  }
  if (found > printCount) Serial.print(",...");
  Serial.println("]");
}

void wakeMlxBus() {
  // Wake pulse used by some MLX modules after brown-out/sleep.
  pinMode(diag::PIN_I2C_SDA, INPUT_PULLUP);
  pinMode(diag::PIN_I2C_SCL, OUTPUT);
  digitalWrite(diag::PIN_I2C_SCL, LOW);
  delay(40);
  pinMode(diag::PIN_I2C_SCL, INPUT_PULLUP);
  delay(8);
  Wire.begin(diag::PIN_I2C_SDA, diag::PIN_I2C_SCL);
  Wire.setClock(diag::I2C_CLOCK_SLOW_HZ);
}

bool tryMlxAt(uint8_t address, float& objectC, float& ambientC) {
  if (!probeI2cAddress(address)) return false;
  if (!mlx.begin(address, &Wire)) return false;
  delay(40);

  objectC = mlx.readObjectTempC();
  ambientC = mlx.readAmbientTempC();
  if (isnan(objectC) || isinf(objectC) || isnan(ambientC) || isinf(ambientC)) return false;
  return true;
}

void runMlxDiagnostics() {
  Serial.println("[MLX] probing addresses 0x5A..0x5D");
  bool mlxSeenOnBus = false;
  bool mlxReady = false;
  uint8_t readyAddr = 0;
  float obj = NAN;
  float amb = NAN;

  for (uint8_t attempt = 0; attempt < diag::MLX_RETRIES && !mlxReady; ++attempt) {
    if (attempt > 0) {
      wakeMlxBus();
      delay(diag::MLX_RETRY_DELAY_MS);
    }
    for (size_t i = 0; i < (sizeof(diag::MLX_CANDIDATE_ADDRS) / sizeof(diag::MLX_CANDIDATE_ADDRS[0])); ++i) {
      const uint8_t addr = diag::MLX_CANDIDATE_ADDRS[i];
      if (!probeI2cAddress(addr)) continue;
      mlxSeenOnBus = true;
      if (tryMlxAt(addr, obj, amb)) {
        mlxReady = true;
        readyAddr = addr;
        break;
      }
    }
  }

  if (mlxReady) {
    Serial.printf("[MLX] PASS addr=0x%02X obj=%.2fC amb=%.2fC\n", readyAddr, obj, amb);
  } else if (mlxSeenOnBus) {
    Serial.println("[MLX] FAIL: detected on I2C but driver/read failed");
  } else {
    Serial.println("[MLX] FAIL: no MLX address found on I2C bus");
  }
}

GpsProbeResult probeGps(int rxPin, int txPin, uint32_t baud, uint32_t windowMs) {
  GpsProbeResult result;
  result.rxPin = rxPin;
  result.txPin = txPin;
  result.baud = baud;

  pinMode(rxPin, INPUT);
  gpsSerial.end();
  gpsSerial.begin(baud, SERIAL_8N1, rxPin, txPin);
  delay(60);
  while (gpsSerial.available()) gpsSerial.read();

  const uint32_t startMs = millis();
  while ((uint32_t)(millis() - startMs) < windowMs) {
    while (gpsSerial.available()) {
      const int c = gpsSerial.read();
      if (c < 0) continue;
      ++result.bytes;
      if (c == '$') ++result.dollar;
      appendSample(result.sample, sizeof(result.sample), (char)c);
    }
    delay(5);
  }

  return result;
}

bool isBetterGpsResult(const GpsProbeResult& candidate, const GpsProbeResult& currentBest) {
  if (candidate.dollar != currentBest.dollar) return candidate.dollar > currentBest.dollar;
  return candidate.bytes > currentBest.bytes;
}

void runGpsDiagnostics() {
  Serial.println("[GPS] scanning RX/TX + baud combinations");

  GpsProbeResult best;
  bool hasBest = false;

  for (size_t pair = 0; pair < (sizeof(diag::GPS_PIN_PAIRS) / sizeof(diag::GPS_PIN_PAIRS[0])); ++pair) {
    const int rxPin = diag::GPS_PIN_PAIRS[pair][0];
    const int txPin = diag::GPS_PIN_PAIRS[pair][1];
    for (size_t i = 0; i < (sizeof(diag::GPS_BAUDS) / sizeof(diag::GPS_BAUDS[0])); ++i) {
      const uint32_t baud = diag::GPS_BAUDS[i];
      const GpsProbeResult r = probeGps(rxPin, txPin, baud, diag::GPS_PROBE_WINDOW_MS);
      Serial.printf(
          "[GPS] rx=%d tx=%d baud=%lu bytes=%lu dollar=%lu sample=%s\n",
          rxPin,
          txPin,
          (unsigned long)baud,
          (unsigned long)r.bytes,
          (unsigned long)r.dollar,
          r.sample[0] ? r.sample : "-");
      if (!hasBest || isBetterGpsResult(r, best)) {
        best = r;
        hasBest = true;
      }
    }
  }

  if (!hasBest) {
    Serial.println("[GPS] FAIL: no probe data");
    return;
  }

  gpsLiveConfig = best;
  gpsLiveConfigured = true;
  gpsLiveBytes = 0;
  gpsLiveDollar = 0;
  gpsLiveLines = 0;
  gpsLastReportMs = millis();

  gpsSerial.end();
  gpsSerial.begin(gpsLiveConfig.baud, SERIAL_8N1, gpsLiveConfig.rxPin, gpsLiveConfig.txPin);

  Serial.printf(
      "[GPS] BEST rx=%d tx=%d baud=%lu bytes=%lu dollar=%lu\n",
      gpsLiveConfig.rxPin,
      gpsLiveConfig.txPin,
      (unsigned long)gpsLiveConfig.baud,
      (unsigned long)gpsLiveConfig.bytes,
      (unsigned long)gpsLiveConfig.dollar);

  if (gpsLiveConfig.dollar > 0) {
    Serial.println("[GPS] PASS: NMEA marker '$' detected");
  } else if (gpsLiveConfig.bytes > 0) {
    Serial.println("[GPS] WARN: bytes seen but no '$' (baud/noise/protocol mismatch)");
  } else {
    Serial.println("[GPS] FAIL: no serial bytes from GPS");
  }
}

void setup() {
  Serial.begin(115200);
  delay(1200);

  Serial.println();
  Serial.println("==== RT ESP32 Sensor Diagnostic ====");
  Serial.printf("build=%s %s\n", __DATE__, __TIME__);

  Wire.begin(diag::PIN_I2C_SDA, diag::PIN_I2C_SCL);
  Wire.setClock(diag::I2C_CLOCK_HZ);

  printI2cScan();
  runMlxDiagnostics();

  Wire.begin(diag::PIN_I2C_SDA, diag::PIN_I2C_SCL);
  Wire.setClock(diag::I2C_CLOCK_HZ);
  printI2cScan();

  runGpsDiagnostics();
  Serial.println("[INFO] live GPS monitor active");
  Serial.println("====================================");
}

void loop() {
  if (!gpsLiveConfigured) {
    delay(1000);
    return;
  }

  while (gpsSerial.available()) {
    const int c = gpsSerial.read();
    if (c < 0) continue;
    ++gpsLiveBytes;
    if (c == '$') ++gpsLiveDollar;
    if (c == '\n') ++gpsLiveLines;
    gpsParser.encode((char)c);
    if (c == '\r' || c == '\n' || (c >= 32 && c <= 126)) {
      Serial.write((char)c);
    }
  }

  if ((uint32_t)(millis() - gpsLastReportMs) >= diag::GPS_REPORT_MS) {
    if (gpsParser.location.isValid()) {
      Serial.printf(
          "\n[GPS-LIVE] status=OK lat=%.6f lon=%.6f rx=%d tx=%d baud=%lu bytes=%lu dollar=%lu lines=%lu\n",
          gpsParser.location.lat(),
          gpsParser.location.lng(),
          gpsLiveConfig.rxPin,
          gpsLiveConfig.txPin,
          (unsigned long)gpsLiveConfig.baud,
          (unsigned long)gpsLiveBytes,
          (unsigned long)gpsLiveDollar,
          (unsigned long)gpsLiveLines);
    } else {
      const char* status = gpsLiveDollar > 0 ? "WAIT_FIX"
                                             : (gpsLiveBytes > 0 ? "SERIAL_ONLY"
                                                                 : "NO_DATA");
      Serial.printf(
          "\n[GPS-LIVE] status=%s rx=%d tx=%d baud=%lu bytes=%lu dollar=%lu lines=%lu\n",
          status,
          gpsLiveConfig.rxPin,
          gpsLiveConfig.txPin,
          (unsigned long)gpsLiveConfig.baud,
          (unsigned long)gpsLiveBytes,
          (unsigned long)gpsLiveDollar,
          (unsigned long)gpsLiveLines);
    }
    gpsLastReportMs = millis();
  }

  delay(5);
}
