/**
 * @file config.h
 * @brief Configurações do gateway matriz RuralTech ESP32.
 */
#pragma once
#include <Arduino.h>
#include "manual_settings.h"

// 0 = economiza flash removendo bibliotecas OLED do build da matriz.
// Defina 1 se precisar da tela local.
#ifndef RT_MATRIX_OLED_ENABLED
#define RT_MATRIX_OLED_ENABLED 0
#endif

#ifndef RT_MATRIX_LOG_LEVEL
#define RT_MATRIX_LOG_LEVEL 2
#endif

// BLE da matriz:
// - em partições maiores que min_spiffs, padrão = 1 (onboarding BLE ativo);
// - em min_spiffs, padrão = 0 para caber em flash sem trocar partição.
// Defina manualmente RT_MATRIX_BLE_ENABLED para sobrescrever.
#ifndef RT_MATRIX_BLE_ENABLED
#if defined(ARDUINO_PARTITION_min_spiffs)
#define RT_MATRIX_BLE_ENABLED 0
#else
#define RT_MATRIX_BLE_ENABLED 1
#endif
#endif

namespace cfg {
constexpr char FW_VERSION[] = "gateway-matriz-1.0.0";
constexpr uint8_t LOG_LEVEL = RT_MATRIX_LOG_LEVEL;
constexpr uint32_t SERIAL_BAUD = 115200;
constexpr uint16_t TASK_WDT_TIMEOUT_SEC = 30;

constexpr int PIN_LORA_CS = 5;
constexpr int PIN_LORA_RST = 14;
constexpr int PIN_LORA_DIO0 = 27;
constexpr int PIN_LORA_DIO1 = 33;
constexpr int PIN_SD_CS = 13;
constexpr int PIN_I2C_SDA = 21;
constexpr int PIN_I2C_SCL = 22;
constexpr bool OLED_ENABLED = RT_MATRIX_OLED_ENABLED;

constexpr float LORA_FREQ_MHZ = 915.0;
constexpr uint16_t WS_PORT = 81;
constexpr const char* AP_SSID = cfg_manual::AP_SSID;
constexpr const char* AP_PASS = cfg_manual::AP_PASS;
constexpr bool OTA_ENABLED = true;
constexpr bool WIFI_OTA_DEFAULT_ENABLED = true;
constexpr const char* OTA_HOSTNAME = cfg_manual::OTA_HOSTNAME;
constexpr const char* OTA_PASSWORD = cfg_manual::OTA_PASSWORD;
constexpr uint32_t OTA_HANDSHAKE_TIMEOUT_MS = 120000;

// Telemetria em nuvem (gateway matriz como escritor direto no RTDB)
// Configure antes de compilar para habilitar a escrita direta no RTDB.
constexpr bool CLOUD_TELEMETRY_ENABLED = true;
// Backhaul precisa ter acesso a internet para o gateway matriz escrever no Firebase.
constexpr const char* BACKHAUL_WIFI_SSID = cfg_manual::BACKHAUL_WIFI_SSID;
constexpr const char* BACKHAUL_WIFI_PASS = cfg_manual::BACKHAUL_WIFI_PASS;
constexpr const char* FIREBASE_RTDB_HOST = cfg_manual::FIREBASE_RTDB_HOST;
constexpr const char* RTDB_MATRIX_ID = cfg_manual::RTDB_MATRIX_ID;
constexpr const char* RTDB_WRITER_KEY = cfg_manual::RTDB_WRITER_KEY;
constexpr uint16_t CLOUD_HTTP_TIMEOUT_MS = 3500;
constexpr uint32_t CLOUD_BACKHAUL_RETRY_MS = 10000;
constexpr uint16_t TELEMETRY_RETENTION_DAYS = 365;

// BLE discovery for app onboarding
constexpr bool BLE_PRESENCE_ENABLED = RT_MATRIX_BLE_ENABLED;
constexpr char BLE_DEVICE_PREFIX[] = "RT-M";
constexpr uint16_t BLE_COMPANY_ID = 0x1234;
constexpr char BLE_SERVICE_UUID[] = "7f920001-0a26-4d09-a606-0cfef4f9a1f0";

// Limites de protocolo LoRa/app
constexpr uint8_t LORA_MAX_PAYLOAD_BYTES = 128;
constexpr uint8_t MAX_POLYGON_POINTS = 32;
constexpr uint8_t MAX_HERD_PHASES = 8;
constexpr uint8_t MAX_HERD_OPERATION_DEVICES = 16;
constexpr uint32_t HERD_OPERATION_RETRY_MS = 15000;
constexpr uint32_t HERD_OPERATION_TIMEOUT_MS = 600000;
constexpr uint32_t HERD_OPERATION_STATUS_PUBLISH_MS = 3000;

// Relay entre gateways (multi-hop best effort)
constexpr bool GATEWAY_RELAY_ENABLED = true;
constexpr uint8_t LORA_REPLAY_TRACKED_DEVICES = 32;

// Criptografia LoRa (deve casar com a coleira no MVP)
constexpr uint8_t AES_KEY[16] = {0x31,0x62,0x13,0x44,0x75,0x26,0x57,0x98,0xA9,0xBA,0xCB,0xDC,0xED,0x0F,0x11,0x22};
constexpr uint8_t HMAC_KEY[32] = {
  0x21,0x43,0x65,0x87,0x09,0xAB,0xCD,0xEF,0x10,0x32,0x54,0x76,0x98,0xBA,0xDC,0xFE,
  0x55,0x44,0x33,0x22,0x11,0x00,0x99,0x88,0x77,0x66,0xAA,0xBB,0xCC,0xDD,0xEE,0xFF
};
}
