/** @file Logger.h */
#pragma once
#include <Arduino.h>
#include "config.h"

#if RT_MATRIX_LOG_LEVEL >= 1
#define LOGE(fmt, ...) do { Serial.printf("[E] " fmt "\n", ##__VA_ARGS__); } while(0)
#else
#define LOGE(...) do {} while(0)
#endif

#if RT_MATRIX_LOG_LEVEL >= 2
#define LOGW(fmt, ...) do { Serial.printf("[W] " fmt "\n", ##__VA_ARGS__); } while(0)
#else
#define LOGW(...) do {} while(0)
#endif

#if RT_MATRIX_LOG_LEVEL >= 3
#define LOGI(fmt, ...) do { Serial.printf("[I] " fmt "\n", ##__VA_ARGS__); } while(0)
#else
#define LOGI(...) do {} while(0)
#endif
