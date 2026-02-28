#line 1 "/Users/victor/Downloads/code/ruraltech/coleira/SafetyController.cpp"
/**
 * @file SafetyController.cpp
 * @brief Escalonamento buzzer->buzzer intenso->pulso com travas locais.
 */
#include "SafetyController.h"
#include "config.h"
#include "Logger.h"
#include <Arduino.h>

void SafetyController::begin() {
  pinMode(cfg::PIN_BUZZER, OUTPUT);
  pinMode(cfg::PIN_PULSE, OUTPUT);
  digitalWrite(cfg::PIN_BUZZER, LOW);
  digitalWrite(cfg::PIN_PULSE, LOW);
  windowStartMs_ = millis();
}

void SafetyController::beep(uint8_t level) {
  const uint16_t onMs = (level == 1) ? 120 : 280;
  digitalWrite(cfg::PIN_BUZZER, HIGH);
  delay(onMs);
  digitalWrite(cfg::PIN_BUZZER, LOW);
}

bool SafetyController::canPulse(const GpsData&) {
  const uint32_t now = millis();
  if (now - windowStartMs_ > cfg::PULSE_WINDOW_MS) {
    windowStartMs_ = now;
    pulseCountWindow_ = 0;
  }
  if (pulseCountWindow_ >= cfg::MAX_PULSES_PER_10_MIN) return false;
  if (now - lastPulseMs_ < cfg::MIN_PULSE_GAP_MS) return false;
  return true;
}

void SafetyController::pulseLight() {
  digitalWrite(cfg::PIN_PULSE, HIGH);
  delay(cfg::PULSE_DURATION_MS);
  digitalWrite(cfg::PIN_PULSE, LOW);
  pulseCountWindow_++;
  lastPulseMs_ = millis();
  LOGW("Pulso leve aplicado. qtdJanela=%u", pulseCountWindow_);
}
