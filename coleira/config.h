/**
 * @file config.h
 * @brief Configuração central da coleira RuralTech (ESP32 DevKit V1).
 * @version 1.0.0
 * @date 2026-02-18
 *
 * Trade-off: concentrar parâmetros aqui evita "números mágicos" e reduz risco
 * de inconsistência entre módulos críticos de segurança animal.
 */
#pragma once

#include <Arduino.h>
#include "manual_settings.h"

namespace cfg {
constexpr char FW_VERSION[] = "coleira-1.0.0";
constexpr uint32_t DEVICE_ID = 0xC011A001;

// Debug/log
constexpr uint8_t LOG_LEVEL = 3;  // 1=ERRO,2=WARNING,3=INFO
constexpr uint32_t SERIAL_BAUD = 115200;
constexpr uint16_t TASK_WDT_TIMEOUT_SEC = 30;
constexpr bool TASK_WDT_ENABLED = true;

// Pinos ESP32 DevKit V1
constexpr int PIN_GPS_RX = 16;
constexpr int PIN_GPS_TX = 17;
constexpr int PIN_BUZZER = 25;
constexpr int PIN_PULSE = 26;
constexpr int PIN_LORA_CS = 5;
constexpr int PIN_LORA_RST = 14;
constexpr int PIN_LORA_DIO0 = 27;
constexpr int PIN_LORA_DIO1 = 33;
constexpr int PIN_LORA_BUSY = -1;
constexpr int PIN_I2C_SDA = 21;
constexpr int PIN_I2C_SCL = 22;

// LoRa
constexpr float LORA_FREQ_MHZ = 915.0;
constexpr uint8_t LORA_BW = 125;
constexpr uint8_t LORA_SF = 9;
constexpr uint8_t LORA_CR = 7;
constexpr uint8_t LORA_SYNC_WORD = 0x12;

// Wi-Fi / OTA (manutenção)
constexpr bool OTA_ENABLED = true;
constexpr bool WIFI_OTA_DEFAULT_ENABLED = cfg_manual::WIFI_OTA_DEFAULT_ENABLED;
constexpr const char* WIFI_SSID = cfg_manual::WIFI_SSID;
constexpr const char* WIFI_PASS = cfg_manual::WIFI_PASS;
constexpr const char* OTA_HOSTNAME = cfg_manual::OTA_HOSTNAME;
constexpr const char* OTA_PASSWORD = cfg_manual::OTA_PASSWORD;
constexpr uint32_t OTA_CONNECT_TIMEOUT_MS = 12000;
constexpr uint32_t OTA_ARDUINO_TIMEOUT_MS = 60000;
constexpr uint32_t OTA_HANDSHAKE_TIMEOUT_MS = 120000;
constexpr uint32_t OTA_WINDOW_MS = 300000;
constexpr bool OTA_AP_FALLBACK_ENABLED = true;
constexpr bool OTA_FORCE_AP_ONLY = true;
constexpr const char* OTA_AP_SSID = cfg_manual::OTA_AP_SSID;
constexpr const char* OTA_AP_PASS = cfg_manual::OTA_AP_PASS;
constexpr uint8_t OTA_AP_CHANNEL = 6;
constexpr uint8_t OTA_AP_MAX_CLIENTS = 2;
constexpr uint32_t OTA_DISABLE_GUARD_MS = 300000;
constexpr uint16_t OTA_UPLOAD_RX_WINDOW_MS = 120;
constexpr uint8_t OTA_UPLOAD_EVENT_BURST = 2;
constexpr uint32_t MAINTENANCE_BOOT_WINDOW_MS = 30000;

// BLE discovery for app onboarding
#if defined(ARDUINO_PARTITION_min_spiffs)
constexpr bool BLE_PRESENCE_ENABLED = false;
#else
constexpr bool BLE_PRESENCE_ENABLED = true;
#endif
constexpr char BLE_DEVICE_PREFIX[] = "RT-C";
constexpr uint16_t BLE_COMPANY_ID = 0x1234;
constexpr char BLE_SERVICE_UUID[] = "7f920001-0a26-4d09-a606-0cfef4f9a1f0";

// NVS (persistência de configuração operacional)
constexpr char PREF_NAMESPACE[] = "collar_cfg";
constexpr char PREF_KEY_WIFI_OTA[] = "wifi_ota";
constexpr char PREF_KEY_FENCE[] = "fence";
constexpr char PREF_KEY_HERD[] = "herd";
constexpr char PREF_KEY_LORA_SEQ_HI[] = "lora_seq_hi";
constexpr char PREF_KEY_HEALTH_DAY[] = "health_day";
constexpr char PREF_KEY_REBOOT_COUNT[] = "reboot_count";
constexpr uint16_t LORA_SEQ_RESERVE_WINDOW = 128;

// Intervalos (ms)
constexpr uint32_t NORMAL_INTERVAL_MS = 180000;
constexpr uint32_t ALERT_INTERVAL_MS = 20000;
constexpr uint32_t HERDING_INTERVAL_MS = 15000;
constexpr uint32_t RX_WINDOW_MS = 2500;
constexpr uint32_t LORA_POST_BEGIN_SETTLE_MS = 350;
constexpr uint32_t LORA_COMMAND_FEEDBACK_DELAY_MS = 180;
constexpr uint32_t LORA_POST_COMMAND_EVENT_HOLDOFF_MS = 300;
constexpr uint32_t DAILY_HEALTH_FALLBACK_MS = 86400000UL;

// Segurança animal
constexpr uint8_t MAX_PULSES_PER_10_MIN = 3;
constexpr uint32_t PULSE_WINDOW_MS = 600000;
constexpr uint32_t MIN_PULSE_GAP_MS = 120000;
constexpr uint32_t PULSE_DURATION_MS = 250;
constexpr float MAX_HDOP = 2.0f;
constexpr float MAX_HDOP_FOR_PULSE = MAX_HDOP;
constexpr uint32_t VIOLATION_PERSIST_MS = 45000;

// Sensores
constexpr uint32_t NO_MOTION_MS = 90000;
constexpr float MOTION_THRESHOLD_G = 0.20f;
constexpr uint8_t MIN_SATS = 7;
constexpr float OUTLIER_MAX_SPEED = 15.0f;  // m/s
constexpr uint8_t MEDIAN_WINDOW = 5;
constexpr float EMA_ALPHA_STOP = 0.2f;
constexpr float EMA_ALPHA_MOVE = 0.6f;
constexpr uint32_t STOP_DETECT_MS = 30000;
constexpr float LOCK_RADIUS_M = 5.0f;
constexpr float GPS_SPEED_MOVE_THRESHOLD_KMPH = 1.2f;
constexpr bool SMART_GPS_TEST_MODE = false;

// Persistência
constexpr uint16_t EEPROM_SIZE = 2048;
constexpr uint16_t EEPROM_EVENT_START = 64;
constexpr uint8_t EEPROM_EVENT_SLOTS = 11;
constexpr uint16_t EEPROM_LAST_GOOD_FIX_ADDR = 1792;

// Geofence e condução
constexpr uint8_t MAX_POLYGON_POINTS = 32;
constexpr uint8_t MAX_HERD_PHASES = 8;
constexpr uint8_t OPERATION_ID_MAX_LEN = 40;
constexpr uint8_t EVENT_COMMAND_ID_MAX_LEN = 68;
constexpr uint8_t EVENT_ORIGIN_DOC_ID_MAX_LEN = 24;
constexpr uint8_t EVENT_ERROR_CODE_MAX_LEN = 32;
constexpr float FENCE_WARNING_METERS = 20.0f;

// Criptografia (MVP: chave estática por device; em produção provisionar seguro)
constexpr uint8_t AES_KEY[16] = {0x31,0x62,0x13,0x44,0x75,0x26,0x57,0x98,0xA9,0xBA,0xCB,0xDC,0xED,0x0F,0x11,0x22};
constexpr uint8_t HMAC_KEY[32] = {
  0x21,0x43,0x65,0x87,0x09,0xAB,0xCD,0xEF,0x10,0x32,0x54,0x76,0x98,0xBA,0xDC,0xFE,
  0x55,0x44,0x33,0x22,0x11,0x00,0x99,0x88,0x77,0x66,0xAA,0xBB,0xCC,0xDD,0xEE,0xFF
};
}
