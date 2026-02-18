/**
 * @file config.h
 * @brief Configurações do gateway RuralTech ESP32.
 */
#pragma once
#include <Arduino.h>

namespace cfg {
constexpr char FW_VERSION[] = "gateway-1.0.0";
constexpr uint8_t LOG_LEVEL = 3;
constexpr uint32_t SERIAL_BAUD = 115200;

constexpr int PIN_LORA_CS = 5;
constexpr int PIN_LORA_RST = 14;
constexpr int PIN_LORA_DIO0 = 27;
constexpr int PIN_LORA_DIO1 = 33;
constexpr int PIN_SD_CS = 13;
constexpr int PIN_I2C_SDA = 21;
constexpr int PIN_I2C_SCL = 22;

constexpr float LORA_FREQ_MHZ = 915.0;
constexpr uint16_t WS_PORT = 81;
constexpr char AP_SSID[] = "RuralTech-Gateway";
constexpr char AP_PASS[] = "ruraltech123";
}
