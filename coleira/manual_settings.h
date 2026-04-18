/**
 * @file manual_settings.h
 * @brief Configuracoes manuais da coleira (edite aqui para novo ambiente).
 */
#pragma once

// Opcional e nao versionado:
//   coleira/manual_settings.local.h
#if __has_include("manual_settings.local.h")
#include "manual_settings.local.h"
#endif

#ifndef RT_CFG_WIFI_SSID
#define RT_CFG_WIFI_SSID "RuralTech-Gateway"
#endif
#ifndef RT_CFG_WIFI_PASS
#define RT_CFG_WIFI_PASS "ruraltechota"
#endif

#ifndef RT_CFG_OTA_HOSTNAME
#define RT_CFG_OTA_HOSTNAME "ruraltech-coleira"
#endif
#ifndef RT_CFG_OTA_PASSWORD
#define RT_CFG_OTA_PASSWORD "ruraltechota"
#endif

#ifndef RT_CFG_OTA_AP_SSID
#define RT_CFG_OTA_AP_SSID "RuralTech-Coleira-OTA"
#endif
#ifndef RT_CFG_OTA_AP_PASS
#define RT_CFG_OTA_AP_PASS "ruraltechota"
#endif

#ifndef RT_CFG_WIFI_OTA_DEFAULT_ENABLED
#define RT_CFG_WIFI_OTA_DEFAULT_ENABLED true
#endif

#ifndef RT_CFG_SMART_GPS_PERSISTENCE_ENABLED
#define RT_CFG_SMART_GPS_PERSISTENCE_ENABLED false
#endif

#ifndef RT_CFG_STORAGE_QUEUE_PERSISTENCE_ENABLED
#define RT_CFG_STORAGE_QUEUE_PERSISTENCE_ENABLED false
#endif

#ifndef RT_CFG_DEEP_SLEEP_ENABLED
#define RT_CFG_DEEP_SLEEP_ENABLED true
#endif

#ifndef RT_CFG_DEFAULT_PROPERTY_ID
#define RT_CFG_DEFAULT_PROPERTY_ID ""
#endif
#ifndef RT_CFG_DEFAULT_PROPERTY_SCOPE_ID
#define RT_CFG_DEFAULT_PROPERTY_SCOPE_ID ""
#endif
#ifndef RT_CFG_DEFAULT_MATRIX_GATEWAY_ID
#define RT_CFG_DEFAULT_MATRIX_GATEWAY_ID ""
#endif
#ifndef RT_CFG_DEFAULT_BINDING_VERSION
#define RT_CFG_DEFAULT_BINDING_VERSION 1
#endif

namespace cfg_manual {
// Wi-Fi de manutencao OTA (modo station)
constexpr char WIFI_SSID[] = RT_CFG_WIFI_SSID;
constexpr char WIFI_PASS[] = RT_CFG_WIFI_PASS;

// OTA da coleira
constexpr char OTA_HOSTNAME[] = RT_CFG_OTA_HOSTNAME;
constexpr char OTA_PASSWORD[] = RT_CFG_OTA_PASSWORD;

// AP fallback para onboarding/OTA local
constexpr char OTA_AP_SSID[] = RT_CFG_OTA_AP_SSID;
constexpr char OTA_AP_PASS[] = RT_CFG_OTA_AP_PASS;
constexpr bool WIFI_OTA_DEFAULT_ENABLED = RT_CFG_WIFI_OTA_DEFAULT_ENABLED;
constexpr bool SMART_GPS_PERSISTENCE_ENABLED = RT_CFG_SMART_GPS_PERSISTENCE_ENABLED;
constexpr bool STORAGE_QUEUE_PERSISTENCE_ENABLED = RT_CFG_STORAGE_QUEUE_PERSISTENCE_ENABLED;
constexpr bool DEEP_SLEEP_ENABLED = RT_CFG_DEEP_SLEEP_ENABLED;
constexpr char DEFAULT_PROPERTY_ID[] = RT_CFG_DEFAULT_PROPERTY_ID;
constexpr char DEFAULT_PROPERTY_SCOPE_ID[] = RT_CFG_DEFAULT_PROPERTY_SCOPE_ID;
constexpr char DEFAULT_MATRIX_GATEWAY_ID[] = RT_CFG_DEFAULT_MATRIX_GATEWAY_ID;
constexpr uint32_t DEFAULT_BINDING_VERSION = RT_CFG_DEFAULT_BINDING_VERSION;
}
