# RuralTech Firmware Provenance Path Validation Report

## Target Commit
56b2b40c6ea2a68262fb680ff62b4502941222e8

## Repository State
- HEAD: 56b2b40c6ea2a68262fb680ff62b4502941222e8
- Short HEAD: 56b2b40
- Dirty files:
?? tools/audit/output/20260425_183334_provenance_path_validation/

## Generated Build Info
- Header locations audit: PASS (somente o header primario foi encontrado)
- Contains target full SHA: PASS
- Contains target short SHA: PASS
- Contains stale SHA: PASS
- Validation summary: PASS (SHA alvo presente (56b2b40))

## Include Chain
- build_info.h includes generated metadata: PASS
- collar uses build_info: PASS
- matrix uses build_info: PASS

## Matrix Runtime Provenance
- FW_PROVENANCE role=matrix present: SKIPPED
- gitSha target: SKIPPED
- gitShort target: SKIPPED
- stale SHA absent: SKIPPED
- detail: serial nao capturado

## Collar Runtime Provenance
- FW_PROVENANCE role=collar present: SKIPPED
- gitSha target: SKIPPED
- gitShort target: SKIPPED
- stale SHA absent: SKIPPED
- detail: serial nao capturado

## Compile and Upload
- matrix compile: PASS (artefatos em /tmp/ruraltech-build-matriz)
- collar compile: PASS (artefatos em /tmp/ruraltech-build-coleira)
- matrix binary SHA: PASS (binario em /tmp/ruraltech-build-matriz contem SHA alvo completo e curto)
- collar binary SHA: PASS (binario em /tmp/ruraltech-build-coleira contem SHA alvo completo e curto)
- matrix upload: FAIL (upload falhou via /dev/tty.usbserial-59470049741)
- collar upload: SKIPPED (upload pulado)

## Optional /status Validation
- matrix /status: SKIPPED (status pulado)
- collar /status: SKIPPED (status pulado)

## Optional SET_FENCE Smoke
- skipped
- observed key logs: bench pulado

## Host Tests
- PASS (rtrv1_stale_wake_hint_test.cpp, rtrv1_wake_scheduler_test.cpp, rtrv1_fast_path_priority_test.cpp, rtrv1_terminal_failure_status_test.cpp)

## Final Result
FAIL

## Blocking Issues
- upload falhou via /dev/tty.usbserial-59470049741

## Commands executed
- git status --short
- git rev-parse HEAD
- git rev-parse --short=7 HEAD
- python3 tools/audit/generate_build_info.py
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_stale_wake_hint_test.cpp -o /tmp/rtrv1_stale_wake_hint_test
- /tmp/rtrv1_stale_wake_hint_test
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_wake_scheduler_test.cpp -o /tmp/rtrv1_wake_scheduler_test
- /tmp/rtrv1_wake_scheduler_test
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_fast_path_priority_test.cpp -o /tmp/rtrv1_fast_path_priority_test
- /tmp/rtrv1_fast_path_priority_test
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_terminal_failure_status_test.cpp -o /tmp/rtrv1_terminal_failure_status_test
- /tmp/rtrv1_terminal_failure_status_test
- arduino-cli cache clean
- arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs --build-path /tmp/ruraltech-build-matriz gateway-matriz
- arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs --build-path /tmp/ruraltech-build-coleira coleira
- arduino-cli upload -p /dev/tty.usbserial-59470049741 --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs --input-dir /tmp/ruraltech-build-matriz gateway-matriz
