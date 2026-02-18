/**
 * @file SafetyController.h
 * @brief Controle de estímulos e limites rígidos de segurança animal.
 */
#pragma once
#include "Types.h"

class SafetyController {
 public:
  void begin();
  void beep(uint8_t level);
  bool canPulse(const GpsData& gpsHealthyRef);
  void pulseLight();

 private:
  uint8_t pulseCountWindow_ = 0;
  uint32_t windowStartMs_ = 0;
  uint32_t lastPulseMs_ = 0;
};
