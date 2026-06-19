# RuralTech Matrix Planner Runtime Marker Validation Report

## Target Commit
5ff9bf5b0cc1bfebebdf16ceeb01f56813284181

## Repository State
- HEAD: 5ff9bf5b0cc1bfebebdf16ceeb01f56813284181
- Short HEAD: 5ff9bf5
- Dirty files:
M firmware/shared/AreaSyncLogger.h
 M gateway-matriz/gateway-matriz.ino
 M tools/audit/__pycache__/flash_and_validate_firmware.cpython-314.pyc
 M tools/audit/flash_and_validate_firmware.py

## Source Marker Audit
- Source markers: PASS (todos os markers obrigatorios encontrados no source)

## Generated Build Info
- Header locations audit: PASS (somente o header primario foi encontrado)
- Contains target full SHA: PASS
- Contains target short SHA: PASS
- Contains stale SHA: PASS
- Validation summary: PASS (SHA alvo presente (5ff9bf5))

## Include Chain
- build_info.h includes generated metadata: PASS
- collar uses build_info: PASS
- matrix uses build_info: PASS

## Matrix Runtime Provenance
- FW_PROVENANCE role=matrix present: SKIPPED
- gitSha target: SKIPPED
- gitShort target: SKIPPED
- stale SHA absent: SKIPPED
- boot markers: SKIPPED (serial nao capturado)
- detail: serial nao capturado

## Collar Runtime Provenance
- FW_PROVENANCE role=collar present: SKIPPED
- gitSha target: SKIPPED
- gitShort target: SKIPPED
- stale SHA absent: SKIPPED
- detail: serial nao capturado

## Compile and Upload
- matrix compile: SKIPPED (compile pulado)
- collar compile: SKIPPED (compile pulado)
- matrix binary SHA: SKIPPED (binario nao inspecionado)
- matrix binary markers: SKIPPED (binario nao inspecionado)
- collar binary SHA: SKIPPED (binario nao inspecionado)
- matrix upload: SKIPPED (upload pulado)
- collar upload: SKIPPED (upload pulado)

## Optional /status Validation
- matrix /status: SKIPPED (status pulado)
- collar /status: SKIPPED (status pulado)

## Optional SET_FENCE Smoke
- skipped
- observed key logs: bench pulado

## Host Tests
- PASS (rpv2_fence_planner_test.cpp, rtrv1_stale_wake_hint_test.cpp, rtrv1_wake_scheduler_test.cpp, rtrv1_fast_path_priority_test.cpp, rtrv1_terminal_failure_status_test.cpp)

## Final Result
PASS

## Blocking Issues
- none

## Commands executed
- git branch --show-current
- git status --short
- git log --oneline -10
- git rev-parse HEAD
- git rev-parse --short=7 HEAD
- marker search via rg/grep
- python3 tools/audit/generate_build_info.py
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rpv2_fence_planner_test.cpp -o /tmp/rpv2_fence_planner_test
- /tmp/rpv2_fence_planner_test
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_stale_wake_hint_test.cpp -o /tmp/rtrv1_stale_wake_hint_test
- /tmp/rtrv1_stale_wake_hint_test
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_wake_scheduler_test.cpp -o /tmp/rtrv1_wake_scheduler_test
- /tmp/rtrv1_wake_scheduler_test
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_fast_path_priority_test.cpp -o /tmp/rtrv1_fast_path_priority_test
- /tmp/rtrv1_fast_path_priority_test
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_terminal_failure_status_test.cpp -o /tmp/rtrv1_terminal_failure_status_test
- /tmp/rtrv1_terminal_failure_status_test
