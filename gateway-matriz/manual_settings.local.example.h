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

// Perfil de diagnostico da matriz (opcional):
//   0 = operacional completo
//   1 = LoRa puro
//   2 = LoRa + AP + HTTP
//   3 = stage 2 + WS + OTA + BLE
//   4 = stage 3 + backhaul/cloud
//   5 = stage 4 + SD
// #define RT_MATRIX_DIAG_STAGE 2

// Relay LoRa entre gateways (opcional)
// #define RT_CFG_GATEWAY_RELAY_ENABLED 1

// OTA local (opcional)
// #define RT_CFG_OTA_HOSTNAME "ruraltech-matriz"
// #define RT_CFG_OTA_PASSWORD "ruraltechota"

// Backhaul com internet (sensivel)
#define RT_CFG_BACKHAUL_WIFI_SSID "SET_BACKHAUL_WIFI_SSID"
#define RT_CFG_BACKHAUL_WIFI_PASS "SET_BACKHAUL_WIFI_PASS"

// Supabase cloud writer (sensivel)
#define RT_CFG_SUPABASE_EDGE_HOST "SET_SUPABASE_PROJECT_HOST"
#define RT_CFG_RTDB_MATRIX_ID "SET_RTDB_MATRIX_ID"
#define RT_CFG_RTDB_WRITER_KEY "SET_RTDB_WRITER_KEY"
#define RT_CFG_RTDB_QUEUE_KEY "SET_RTDB_QUEUE_KEY"
