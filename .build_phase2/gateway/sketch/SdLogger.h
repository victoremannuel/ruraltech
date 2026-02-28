#line 1 "/Users/victor/Downloads/code/ruraltech/gateway/SdLogger.h"
/**
 * @file SdLogger.h
 * @brief Log diário em microSD com hash chain simples para integridade lógica.
 */
#pragma once
#include <SD.h>
#include <SPI.h>

class SdLogger {
 public:
  bool begin(int csPin);
  void log(const String& line);

 private:
  String lastHash_ = "GENESIS";
  String hashLine(const String& line);
};
