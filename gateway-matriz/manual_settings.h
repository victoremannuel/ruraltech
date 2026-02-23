/**
 * @file manual_settings.h
 * @brief Configuracoes manuais do gateway matriz (edite aqui para novo ambiente).
 */
#pragma once

namespace cfg_manual {
// AP local (onboarding OTA app <-> gateway matriz)
constexpr char AP_SSID[] = "RuralTech-Matriz";
constexpr char AP_PASS[] = "ruraltechota";

// OTA local
constexpr char OTA_HOSTNAME[] = "ruraltech-matriz";
constexpr char OTA_PASSWORD[] = "ruraltechota";

// Backhaul com internet (telemetria para Firebase RTDB)
constexpr char BACKHAUL_WIFI_SSID[] = "VICTOR_E_CAROL";
constexpr char BACKHAUL_WIFI_PASS[] = "15101510";

// Firebase RTDB (writer do gateway matriz em modo LoRa-only)
constexpr char FIREBASE_RTDB_HOST[] = "ruraltech10-default-rtdb.firebaseio.com";
constexpr char RTDB_MATRIX_ID[] = "matriz_fazenda_01";
constexpr char RTDB_WRITER_KEY[] = "HXz3wo8uWQWIeHmZ5QLbgyw7QiOHvF3xHvVH56WKjEWsrzbZ5aBPCbHPKPgiNuYG";
}
