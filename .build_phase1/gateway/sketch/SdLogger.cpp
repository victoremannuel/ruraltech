#line 1 "/Users/victor/Downloads/code/ruraltech/gateway/SdLogger.cpp"
/** @file SdLogger.cpp */
#include "SdLogger.h"
#include <mbedtls/sha256.h>

bool SdLogger::begin(int csPin) { return SD.begin(csPin); }

String SdLogger::hashLine(const String& line) {
  uint8_t out[32];
  String input = lastHash_ + line;
  mbedtls_sha256_context c;
  mbedtls_sha256_init(&c);
  mbedtls_sha256_starts(&c, 0);
  mbedtls_sha256_update(&c, (const unsigned char*)input.c_str(), input.length());
  mbedtls_sha256_finish(&c, out);
  mbedtls_sha256_free(&c);
  char hex[65];
  for (int i = 0; i < 32; ++i) sprintf(&hex[i*2], "%02x", out[i]);
  hex[64] = '\0';
  lastHash_ = String(hex);
  return lastHash_;
}

void SdLogger::log(const String& line) {
  struct tm tmNow;
  getLocalTime(&tmNow);
  char fn[24];
  strftime(fn, sizeof(fn), "/%Y-%m-%d.log", &tmNow);
  File f = SD.open(fn, FILE_APPEND);
  if (!f) return;
  String h = hashLine(line);
  f.printf("%lu|%s|%s\n", millis(), h.c_str(), line.c_str());
  f.close();
}
