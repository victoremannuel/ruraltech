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
  int csPin_ = -1;
  bool ready_ = false;
  String lastHash_ = "GENESIS";
  String hashLine(const String& line);
  void releaseChipSelect();
};
