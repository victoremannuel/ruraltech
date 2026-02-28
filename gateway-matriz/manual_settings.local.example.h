/**
 * @file manual_settings.local.example.h
 * @brief Exemplo de overrides locais NAO versionados para segredos.
 *
 * Copie para manual_settings.local.h e preencha com dados reais:
 *   cp gateway-matriz/manual_settings.local.example.h gateway-matriz/manual_settings.local.h
 */
#pragma once

// AP local (opcional)
// #define RT_CFG_AP_SSID "RuralTech-Matriz"
// #define RT_CFG_AP_PASS "ruraltechota"

// OTA local (opcional)
// #define RT_CFG_OTA_HOSTNAME "ruraltech-matriz"
// #define RT_CFG_OTA_PASSWORD "ruraltechota"

// Backhaul com internet (sensivel)
#define RT_CFG_BACKHAUL_WIFI_SSID "SET_BACKHAUL_WIFI_SSID"
#define RT_CFG_BACKHAUL_WIFI_PASS "SET_BACKHAUL_WIFI_PASS"

// Firebase RTDB writer (sensivel)
#define RT_CFG_FIREBASE_RTDB_HOST "ruraltech10-default-rtdb.firebaseio.com"
#define RT_CFG_RTDB_MATRIX_ID "SET_RTDB_MATRIX_ID"
#define RT_CFG_RTDB_WRITER_KEY "SET_RTDB_WRITER_KEY"
