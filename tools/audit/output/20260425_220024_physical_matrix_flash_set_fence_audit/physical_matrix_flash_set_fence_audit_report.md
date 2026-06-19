# RuralTech Physical Matrix Flash and SET_FENCE Audit Report

## 1. Executive Result
PASS_WITH_TERMINAL_TIMEOUT

The matrix firmware was compiled, marker-checked, flashed to the physical ESP32 matrix, boot-proven against commit `9508a21ea62988025ec98d5f8310336465193e50`, and exercised through a real cloud/app area update path.

The canonical planner path passed: 6 points were rejected at 134 bytes, retried as 5+1 point chunks, emitted `RPV2_PLAN_FINAL planReady=1`, and created `RTR_WAKE_SESSION_CREATED`.

The LoRa/RTR page did not complete because collar uplinks were rejected as replay. The new bounded wait converted the prior indefinite `simple_command_active` state into `RTR_WAITING_UPLINK_TIMEOUT`, `RTR_WAKE_SESSION_CLEARED`, and `SIMPLE_COMMAND_CLEARED`; queue polling resumed with `simpleActive=0`.

## 2. Target Commit
- Full SHA: `9508a21ea62988025ec98d5f8310336465193e50`
- Short SHA: `9508a21`
- Dirty source accepted: no
- Commit created: `Bound SET_FENCE RTR waiting uplink timeout`

## 3. Repository State
- Branch: `fix/comandos/app-to-coleira`
- Allowed dirty/untracked: current evidence directory only
- Local ignored config: matrix `manual_settings.local.h` used for physical DIAG_STAGE=4 and INFO logs

## 4. Source Marker Audit
- FenceRpv2Planner: PASS
- buildFenceRpv2PlanStrict: PASS
- canonical_fence_planner_v1: PASS
- RPV2_PLAN_ENTER: PASS
- RPV2_PLAN_CANDIDATE_EVAL: PASS
- RPV2_PLAN_CHUNK_REJECT: PASS
- RPV2_PLAN_CHUNK_FIT: PASS
- RPV2_PLAN_FINAL: PASS
- RPV2_PLAN_FAILED_TERMINAL: PASS
- SIMPLE_COMMAND_CLEARED: PASS
- RTR_WAITING_UPLINK_TIMEOUT: PASS

## 5. Host Tests
- rpv2_fence_planner_test: PASS
- matrix_cloud_set_fence_dispatch_integration_test: PASS
- rtrv1_stale_wake_hint_test: PASS
- rtrv1_terminal_failure_status_test: PASS
- rtrv1_wake_scheduler_test: PASS
- rtrv1_fast_path_priority_test: PASS

## 6. Matrix Compile / Binary / Upload
- Compile: PASS
- Binary markers: PASS
- Upload: PASS via `/dev/cu.usbserial-59470049741` with `upload.speed=115200`
- Runtime boot provenance: PASS
- Runtime planner revision: PASS

## 7. SET_FENCE Physical Smoke
- New commandId: `AUTO_AREA_FENCE:kQSjWOVdkqTNDM9WBggT:28B44977244AA4D4:23A00185B336A70A`
- QUEUE_COMMAND_LOADED: PASS
- DISPATCH_BEGIN: PASS
- RPV2_PLAN_ENTER: PASS
- RPV2_PLAN_CANDIDATE_EVAL pointCount=6: PASS
- RPV2_PLAN_CHUNK_REJECT pointCount=6 wireLenFinal=134 limit=128: PASS
- Smaller candidate evaluated pointCount=5: PASS
- RPV2_PLAN_CHUNK_FIT wireLenFinal=126: PASS
- RPV2_PLAN_FINAL planReady=1: PASS
- RTR_WAKE_SESSION_CREATED: PASS
- RTR_PAGE_DEFERRED_WAITING_UPLINK: PASS
- Terminal cleanup when no fresh accepted uplink: PASS
- no indefinite simple_command_active deadlock: PASS after timeout cleanup

## 8. Final Diagnosis
- Current layer passed: App/cloud to matrix, canonical planner, RTR wake-session creation, bounded terminal cleanup.
- Current layer failed: Collar uplinks are being rejected by matrix anti-replay (`Replay bloqueado`), so no fresh RTR uplink is accepted and no page is sent.
- Next layer to debug: align/reset anti-replay sequence state between collar and matrix, then rerun RTR page/ACK and RPv2 apply.

## 9. Evidence Files
- `generated_build_info_final_commit.h`
- `host_tests_after_waiting_uplink_timeout.log`
- `matrix_compile_final_commit.log`
- `matrix_binary_markers_final_commit.txt`
- `matrix_upload_final_commit_115200.log`
- `matrix_boot_serial_final_commit.log`
- `matrix_set_fence_final_smoke_serial.log`
- `final_smoke_marker_extract.txt`
- `final_smoke_trigger_report.json`
