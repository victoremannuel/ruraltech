#ruraltech

## 1. relay (retransmissão lora entre gateways) está dando erro quando ligado com apenas um gateway e uma coleira, é preciso montar uma estratégia para que o relay não atrapalhe a chegada de uma comunicação da coleira em qualquer gateway.

### 1.1. coleira transmite normal

```
rst:0x5 (DEEPSLEEP_RESET),boot:0x13 (SPI_FAST_FLASH_BOOT)
configsip: 0, SPIWP:0xee
clk_drv:0x00,q_drv:0x00,d_drv:0x00,cs0_drv:0x00,hd_drv:0x00,wp_drv:0x00
mode:DIO, clock div:2
load:0x3fff0030,len:4640
load:0x40078000,len:15660
load:0x40080400,len:3164
entry 0x4008059c
[I] Boot reset_reason=8
[I] BOOT stage=serial free_heap=225380 min_heap=222432 heap_ok=1
[I] BOOT stage=wdt free_heap=225412 min_heap=222432 heap_ok=1
[I] BOOT stage=prefs_counter free_heap=225340 min_heap=222432 heap_ok=1
[W] Seq uplink restaurado next=384000001 hi=0 reboot=384 (persistencia write-through desabilitada)
[I] Binding coleira: ready=1 property=T0xeG8WQHwJRI6H3t7vr scope=9FFFC95AA1624895 matrix=192.168.4.1 ver=1
[I] BOOT stage=load_config free_heap=225340 min_heap=222432 heap_ok=1
[I] BOOT stage=wifi_event free_heap=225292 min_heap=222432 heap_ok=1
[I] BOOT stage=status_routes free_heap=225028 min_heap=222432 heap_ok=1
[I] BOOT stage=wifi_ota free_heap=225028 min_heap=222432 heap_ok=1
[I] BOOT stage=status_server free_heap=225028 min_heap=222432 heap_ok=1
[I] BOOT stage=sensors_begin free_heap=225028 min_heap=222432 heap_ok=1

========================================
Calculating gyro offsets
DO NOT MOVE MPU6050...
Done!
X : 0.28
Y : -0.39
Z : 1.08
Program will start after 3 seconds
========================================[I] BOOT stage=safety_begin free_heap=220440 min_heap=220388 heap_ok=1
[I] BOOT stage=storage_begin free_heap=220440 min_heap=220300 heap_ok=1
[W] StorageQueue: persistencia EEPROM desabilitada; usando fila em RAM
[I] BOOT stage=smart_gps_begin free_heap=220440 min_heap=220296 heap_ok=1
[W] SmartGps: persistencia last_good_fix desabilitada por configuracao
[I] BOOT stage=lora_begin free_heap=220440 min_heap=220296 heap_ok=1
[I] Anti-replay downlink restaurado last_seq=0
[I] BOOT stage=checklist free_heap=220120 min_heap=220068 heap_ok=1
==== HW CHECKLIST | COLEIRA ====
[CHECK] NVS_CONFIG               : OK
[CHECK] SEQ_UPLINK_NVS           : OFF
[W] CHECKLIST SEQ_UPLINK_NVS OFF: Seq uplink sem persistencia; revisar NVS.
[CHECK] WIFI_OTA_SERVICE         : OK
[MODE ] WIFI_OTA_ENABLED         : false
[MODE ] PROTO_VERSION            : 1
[MODE ] KEY_ID                   : 1
[MODE ] RADIO_PROFILE            : 9151
[MODE ] BINDING_READY            : true
[CHECK] STATUS_HTTP_80           : OK (/status habilitado)
[CHECK] BLE_PRESENCE             : OK (desabilitado em config)
[CHECK] GPS_UART                 : OK
[CHECK] GPS_BOOT_RX              : OK (baud=9600 bytes=75 nmea=$2 sample=$GPRMC,035516.00,A,1640.)
[CHECK] GPS_NMEA                 : OK (lat=-16.675412 lon=-49.485098 sats=0 hdop=99.90)
[CHECK] I2C_BUS_SCAN             : OK (found=2 [0x5A,0x68])
[CHECK] MPU6050_I2C              : OK (addr=0x68)
[CHECK] MPU6050_DRIVER           : OK
[CHECK] MLX90614_I2C             : OK
[CHECK] MLX90614_DRIVER          : OK
[CHECK] EEPROM_QUEUE             : OK (RAM-only; persistencia off)
[CHECK] LORA_RFM95               : OK
================================
[I] BOOT stage=ready free_heap=219856 min_heap=219696 heap_ok=1
[I] Coleira boot fw=coleira-1.0.0 device_id=3222380545 proto_version=1 key_id=1 radio_profile=9151 bindingReady=1 wifi_ota_enabled=0
[I] Coleira inicializada: id=3222380545 fw=coleira-1.0.0
[I] LOOP checkpoint=before_sensors_read free_heap=219856 min_heap=219648
[I] LOOP checkpoint=after_smart_gps free_heap=219784 min_heap=219648
[I] LOOP checkpoint=before_geofence free_heap=219784 min_heap=219644
[I] LOOP checkpoint=before_herding free_heap=219784 min_heap=219644
[I] LOOP checkpoint=before_uplink_build free_heap=219784 min_heap=219644
[I] LOOP checkpoint=before_lora_send free_heap=219784 min_heap=218596
[I] LoRa TX detail type=1 seq=384000001 payload=97 packed=147 cipher=131 nonce=A501E17300526A6BA4CD270A tag=5845B823DA805A16 head=DA20E90DE7C101B1
[I] LoRa TX ok type=1 seq=384000001 target=3222380545 scope=9FFFC95AA1624895 bytes=159
[I] LOOP checkpoint=after_lora_send free_heap=219676 min_heap=218596
[I] LOOP checkpoint=before_send_daily_health free_heap=219676 min_heap=218596
[I] LOOP checkpoint=after_send_daily_health free_heap=219676 min_heap=218596
[I] LOOP checkpoint=before_lora_receive free_heap=219676 min_heap=218596
[I] LOOP checkpoint=before_pending_events free_heap=219676 min_heap=218596
[I] LoRa TX detail type=2 seq=384000002 payload=104 packed=154 cipher=138 nonce=02B3FB95E52ECB23C9FF0F86 tag=46E820C7F6F11B59 head=F16642BBE5B3D56C
[I] LoRa TX ok type=2 seq=384000002 target=3222380545 scope=9FFFC95AA1624895 bytes=166
[I] LOOP checkpoint=after_pending_event_send event=violation type=2 d1=0 d2=0 payload=104 msg=2 seq=384000002 free_heap=218504 min_heap=218076
[I] LOOP checkpoint=after_pending_events_loop free_heap=219676 min_heap=218076
[I] LOOP checkpoint=before_deep_sleep_prepare free_heap=219676 min_heap=218076
[I] LoRa prepare_for_sleep begin
[I] LoRa prepare_for_sleep finish_transmit ok
[I] LoRa prepare_for_sleep radio_sleep ok
[I] LoRa prepare_for_sleep done
[I] LOOP checkpoint=after_deep_sleep_prepare free_heap=219676 min_heap=218076
[I] LOOP checkpoint=before_deep_sleep_arm free_heap=219676 min_heap=218076
[I] LOOP checkpoint=before_deep_sleep_start free_heap=219676 min_heap=218076
ets Jul 29 2019 12:21:46
```

### 1.2. gateway descarta (nao acontece todas as vezes, mas em algumas transmissões da coleira acontece)

```
[I] LoRa RX raw len=166 rssi=-50 snr=9.8
[W] LoRa RX decrypt_failed len=166 cipher_len=138 irq=0x0050 state=rx_decrypt_failed rssi=-50 snr=9.8 nonce=A18AC2C9EF494C78FD71A80B tag=CE7DAEAB1F99658B head=15279756AB5BACAD fail_count=1
[W] LoRa RX descartado: decrypt_or_hmac_failed len=166
```

## 2. Validar queue/downlink cloud = provar que a matriz também funciona no sentido nuvem → matriz, não só escrevendo telemetria para a nuvem.

## 3. Subir para stage 5 com SD = adicionar a camada de persistência local em SD ao cenário já validado de cloud/backhaul.