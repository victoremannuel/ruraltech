# RuralTech Firmware Provenance Path Validation Report

## Target Commit
c2ae156ab4fb6a42c9296794dd05a0ce5dce3a46

## Repository State
- HEAD: c2ae156ab4fb6a42c9296794dd05a0ce5dce3a46
- Short HEAD: c2ae156
- Dirty files:
M tools/audit/flash_and_validate_firmware.py
?? tools/audit/__pycache__/check_firmware_provenance.cpython-314.pyc
?? tools/audit/__pycache__/flash_and_validate_firmware.cpython-314.pyc
?? tools/audit/__pycache__/generate_build_info.cpython-314.pyc

## Generated Build Info
- Header locations audit: PASS (somente o header primario foi encontrado)
- Contains target full SHA: PASS
- Contains target short SHA: PASS
- Contains stale SHA: PASS
- Validation summary: PASS (SHA alvo presente (c2ae156))

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
- matrix compile: SKIPPED (compile pulado)
- collar compile: SKIPPED (compile pulado)
- matrix binary SHA: SKIPPED (binario nao inspecionado)
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
- PASS (rtrv1_stale_wake_hint_test.cpp, rtrv1_wake_scheduler_test.cpp, rtrv1_fast_path_priority_test.cpp, rtrv1_terminal_failure_status_test.cpp)

## Final Result
PASS

## Blocking Issues
- none

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
