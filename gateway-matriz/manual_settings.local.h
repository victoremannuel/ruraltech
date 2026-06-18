/**
 * @file manual_settings.local.h
 * @brief Overrides locais NAO versionados para manter a matriz funcional.
 */
#pragma once

#define RT_MATRIX_DIAG_STAGE 4
#define RT_MATRIX_LOG_LEVEL 3
#define RT_MATRIX_DISABLE_LORA_REPLAY_FOR_TESTS 0 //desativa o replay 1(modo teste) 0(modo produção)
#define RT_CFG_GATEWAY_RELAY_ENABLED 0

#define RT_CFG_BACKHAUL_WIFI_SSID "VEST"
#define RT_CFG_BACKHAUL_WIFI_PASS "naoteinteressa"

#define RT_CFG_SUPABASE_EDGE_HOST "nhoewnfuyjbtpklrotbf.supabase.co"
#define RT_CFG_RTDB_MATRIX_ID "matriz_fazenda_01"
#define RT_CFG_RTDB_WRITER_KEY "HXz3wo8uWQWIeHmZ5QLbgyw7QiOHvF3xHvVH56WKjEWsrzbZ5aBPCbHPKPgiNuYG"
#define RT_CFG_RTDB_QUEUE_KEY "HcTWH2NTTwED761QDPfuTtTOMA9inllJYO9WqmgOXJh6LQmuGjG5DqT3OPl8tHrk"
