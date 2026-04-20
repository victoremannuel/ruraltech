#include <assert.h>
#include <string.h>

#include "../shared/radio_transport_v1_reason_codes.h"

int main() {
  assert(strcmp(
      rtrv1::rawDropReasonLabel(rtrv1::RawDropReason::DECRYPT_FAILED),
      "decrypt_failed") == 0);
  assert(strcmp(
      rtrv1::rawDropReasonLabel(rtrv1::RawDropReason::SCOPE_MISMATCH),
      "scope_mismatch") == 0);
  assert(strcmp(
      rtrv1::rawDropReasonLabel(rtrv1::RawDropReason::REPLAY_BLOCKED),
      "replay_blocked") == 0);
  assert(strcmp(
      rtrv1::reasonCodeLabel(rtrv1::REASON_PAGE_TIMEOUT_FINAL),
      "page_timeout_final") == 0);
  return 0;
}
