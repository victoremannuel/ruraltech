/**
 * @file manual_settings.h
 * @brief Configuracoes manuais do gateway matriz.
 *
 * Segredos de producao nao devem ficar versionados.
 * Use gateway-matriz/manual_settings.local.h (nao versionado) para overrides.
 */
#pragma once

// Opcional e nao versionado:
//   gateway-matriz/manual_settings.local.h
// Exemplo: gateway-matriz/manual_settings.local.example.h
#if __has_include("manual_settings.local.h")
#include "manual_settings.local.h"
#endif

// AP local (onboarding OTA app <-> gateway matriz)
#ifndef RT_CFG_AP_SSID
#define RT_CFG_AP_SSID "RuralTech-Matriz"
#endif
#ifndef RT_CFG_AP_PASS
#define RT_CFG_AP_PASS "ruraltechota"
#endif

// OTA local
#ifndef RT_CFG_OTA_HOSTNAME
#define RT_CFG_OTA_HOSTNAME "ruraltech-matriz"
#endif
#ifndef RT_CFG_OTA_PASSWORD
#define RT_CFG_OTA_PASSWORD "ruraltechota"
#endif

// Backhaul com internet (telemetria para Firebase RTDB)
// Valores "SET_*" sao placeholders e desativam cloud telemetry ate override local.
#ifndef RT_CFG_BACKHAUL_WIFI_SSID
#define RT_CFG_BACKHAUL_WIFI_SSID "SET_BACKHAUL_WIFI_SSID"
#endif
#ifndef RT_CFG_BACKHAUL_WIFI_PASS
#define RT_CFG_BACKHAUL_WIFI_PASS "SET_BACKHAUL_WIFI_PASS"
#endif

// Firebase RTDB (writer do gateway matriz para telemetria cloud)
#ifndef RT_CFG_FIREBASE_RTDB_HOST
#define RT_CFG_FIREBASE_RTDB_HOST "ruraltech10-default-rtdb.firebaseio.com"
#endif
#ifndef RT_CFG_RTDB_MATRIX_ID
#define RT_CFG_RTDB_MATRIX_ID "SET_RTDB_MATRIX_ID"
#endif
#ifndef RT_CFG_RTDB_WRITER_KEY
#define RT_CFG_RTDB_WRITER_KEY "SET_RTDB_WRITER_KEY"
#endif

namespace cfg_manual {
constexpr char AP_SSID[] = RT_CFG_AP_SSID;
constexpr char AP_PASS[] = RT_CFG_AP_PASS;
constexpr char OTA_HOSTNAME[] = RT_CFG_OTA_HOSTNAME;
constexpr char OTA_PASSWORD[] = RT_CFG_OTA_PASSWORD;
constexpr char BACKHAUL_WIFI_SSID[] = RT_CFG_BACKHAUL_WIFI_SSID;
constexpr char BACKHAUL_WIFI_PASS[] = RT_CFG_BACKHAUL_WIFI_PASS;
constexpr char FIREBASE_RTDB_HOST[] = RT_CFG_FIREBASE_RTDB_HOST;
constexpr char RTDB_MATRIX_ID[] = RT_CFG_RTDB_MATRIX_ID;
constexpr char RTDB_WRITER_KEY[] = RT_CFG_RTDB_WRITER_KEY;
}
