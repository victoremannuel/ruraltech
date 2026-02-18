/**
 * @file Logger.h
 * @brief Macros de log com nível para firmware embarcado.
 * @version 1.0.0
 * @date 2026-02-18
 */
#pragma once
#include <Arduino.h>
#include "config.h"

#define LOGE(fmt, ...) do { if (cfg::LOG_LEVEL >= 1) Serial.printf("[E] " fmt "\n", ##__VA_ARGS__); } while(0)
#define LOGW(fmt, ...) do { if (cfg::LOG_LEVEL >= 2) Serial.printf("[W] " fmt "\n", ##__VA_ARGS__); } while(0)
#define LOGI(fmt, ...) do { if (cfg::LOG_LEVEL >= 3) Serial.printf("[I] " fmt "\n", ##__VA_ARGS__); } while(0)
