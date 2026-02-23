/**
 * @file manual_settings.h
 * @brief Configuracoes manuais do gateway comum (edite aqui para novo ambiente).
 */
#pragma once

namespace cfg_manual {
// AP local (onboarding OTA app <-> gateway)
constexpr char AP_SSID[] = "RuralTech-Gateway";
constexpr char AP_PASS[] = "ruraltechota";

// OTA local
constexpr char OTA_HOSTNAME[] = "ruraltech-gateway";
constexpr char OTA_PASSWORD[] = "ruraltechota";
}
