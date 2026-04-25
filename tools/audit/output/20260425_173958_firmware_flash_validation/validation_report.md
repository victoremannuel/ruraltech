# Firmware Flash Validation Report

## Target commit
8f12088ed3184941220170ec7732a870641327d2

## Git status
dirty
M brain/tarefas/reaproveitamento-area-sync-queue-downlink-cloud-2026-04-18.md
 M tools/audit/check_firmware_provenance.py
 M tools/audit/generate_build_info.py
?? app/devtools_options.yaml
?? tools/audit/__pycache__/check_firmware_provenance.cpython-314.pyc
?? tools/audit/__pycache__/flash_and_validate_firmware.cpython-314.pyc
?? tools/audit/__pycache__/generate_build_info.cpython-314.pyc
?? tools/audit/flash_and_validate_firmware.py

## Build info validation
PASS
SHA alvo presente (8f12088)

## Host tests
PASS
rtrv1_stale_wake_hint_test.cpp, rtrv1_wake_scheduler_test.cpp, rtrv1_fast_path_priority_test.cpp, rtrv1_terminal_failure_status_test.cpp

## Matrix compile
NOT_RUN
compile pulado

## Collar compile
NOT_RUN
compile pulado

## Matrix upload
NOT_RUN
upload pulado

## Collar upload
NOT_RUN
upload pulado

## Matrix runtime provenance
NOT_RUN
Observed SHA: -
Observed build UTC: -
Observed dirty flag: -
Observed line: serial nao capturado

## Collar runtime provenance
NOT_RUN
Observed SHA: -
Observed build UTC: -
Observed dirty flag: -
Observed line: serial nao capturado

## Matrix /status validation
NOT_RUN
status pulado

## Collar /status validation
NOT_RUN
status pulado

## SET_FENCE wake validation
NOT_RUN
bench pulado

## Final result
PASS

## Blocking issues
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
