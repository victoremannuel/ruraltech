# RuralTech Canonical Planner Physical Validation Report

## Target Commit
c8db702f0069dbf22d72c481fd46a772c8290af1

## Repository State
- HEAD: c8db702f0069dbf22d72c481fd46a772c8290af1
- Short HEAD: c8db702
- Dirty files:
M tools/audit/flash_and_validate_firmware.py
?? tools/audit/output/20260425_213456_canonical_planner_physical_validation/

## Cleanup
- Transient cleanup: PASS (transientes removidos: 1)

## Source Marker Audit
- Source markers: PASS (todos os markers obrigatorios encontrados no source)
- Legacy reject emitters: PASS (emitters produtivos restritos ao planner canonico/callback)

## Generated Build Info
- Header locations audit: PASS (somente o header primario foi encontrado)
- Contains target full SHA: PASS
- Contains target short SHA: PASS
- Contains stale SHA: PASS
- Validation summary: PASS (SHA alvo presente (c8db702))

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
- PASS (rpv2_fence_planner_test.cpp, matrix_cloud_set_fence_dispatch_integration_test.cpp, rtrv1_stale_wake_hint_test.cpp, rtrv1_wake_scheduler_test.cpp, rtrv1_fast_path_priority_test.cpp, rtrv1_terminal_failure_status_test.cpp)

## Final Result
INCONCLUSIVE

## Blocking Issues
- workspace ainda suja apos validacao: M tools/audit/flash_and_validate_firmware.py

## Commands executed
- cleanup transient __pycache__/pyc
- git branch --show-current
- git status --short
- git log --oneline -10
- git rev-parse HEAD
- git rev-parse --short=7 HEAD
- marker search via rg/grep
- audit RPV2_PLAN_CHUNK_REJECT emitters
- python3 tools/audit/generate_build_info.py
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rpv2_fence_planner_test.cpp -o /tmp/rpv2_fence_planner_test
- /tmp/rpv2_fence_planner_test
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/matrix_cloud_set_fence_dispatch_integration_test.cpp -o /tmp/matrix_cloud_set_fence_dispatch_integration_test
- /tmp/matrix_cloud_set_fence_dispatch_integration_test
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_stale_wake_hint_test.cpp -o /tmp/rtrv1_stale_wake_hint_test
- /tmp/rtrv1_stale_wake_hint_test
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_wake_scheduler_test.cpp -o /tmp/rtrv1_wake_scheduler_test
- /tmp/rtrv1_wake_scheduler_test
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_fast_path_priority_test.cpp -o /tmp/rtrv1_fast_path_priority_test
- /tmp/rtrv1_fast_path_priority_test
- c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_terminal_failure_status_test.cpp -o /tmp/rtrv1_terminal_failure_status_test
- /tmp/rtrv1_terminal_failure_status_test
