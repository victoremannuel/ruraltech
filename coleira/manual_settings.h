/**
 * @file manual_settings.h
 * @brief Configuracoes manuais da coleira (edite aqui para novo ambiente).
 */
#pragma once

namespace cfg_manual {
// Wi-Fi de manutencao OTA (modo station)
constexpr char WIFI_SSID[] = "RuralTech-Gateway";
constexpr char WIFI_PASS[] = "ruraltechota";

// OTA da coleira
constexpr char OTA_HOSTNAME[] = "ruraltech-coleira";
constexpr char OTA_PASSWORD[] = "ruraltechota";

// AP fallback para onboarding/OTA local
constexpr char OTA_AP_SSID[] = "RuralTech-Coleira-OTA";
constexpr char OTA_AP_PASS[] = "ruraltechota";
}
