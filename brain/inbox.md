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

