#include <cassert>
#include <cstdint>
#include <cstring>

#include "../shared/command_id_policy.h"
#include "../shared/rpv2_transport_policy.h"

int main() {
  constexpr char kFullCommandId[] =
      "AUTO_AREA_FENCE:kQSjWOVdkqTNDM9WBggT:"
      "1F7B4BD263B6A8CD:23A00185B336A70A";
  char commandId[rtcmdid::COMMAND_ID_MAX_LEN]{};
  size_t sourceLength = 0;
  assert(
      rtcmdid::copyToBuffer(
          commandId, sizeof(commandId), kFullCommandId, &sourceLength) ==
      rtcmdid::CopyResult::kOk);
  assert(sourceLength == std::strlen(kFullCommandId));
  assert(std::strcmp(commandId, kFullCommandId) == 0);

  char tooLong[rtcmdid::COMMAND_ID_MAX_LEN + 1]{};
  std::memset(tooLong, 'X', rtcmdid::COMMAND_ID_MAX_LEN);
  tooLong[rtcmdid::COMMAND_ID_MAX_LEN] = '\0';
  assert(
      rtcmdid::copyToBuffer(
          commandId, sizeof(commandId), tooLong, &sourceLength) ==
      rtcmdid::CopyResult::kTooLong);
  assert(commandId[0] == '\0');
  assert(
      std::strcmp(
          rtcmdid::copyResultReason(rtcmdid::CopyResult::kTooLong),
          "command_id_too_long") == 0);

  assert(rpv2transport::isImmediatelyPreviousFragment(1, 2));
  assert(!rpv2transport::isImmediatelyPreviousFragment(2, 2));
  assert(!rpv2transport::isImmediatelyPreviousFragment(3, 2));

  assert(rpv2transport::acceptedRangeEndsAt(0, 5, 5));
  assert(rpv2transport::acceptedRangeEndsAt(5, 1, 6));
  assert(!rpv2transport::acceptedRangeEndsAt(0, 4, 5));

  assert(rpv2transport::shouldRetryFragment(1));
  assert(rpv2transport::shouldRetryFragment(2));
  assert(!rpv2transport::shouldRetryFragment(3));

  assert(!rpv2transport::deadlineReached(99, 100));
  assert(rpv2transport::deadlineReached(100, 100));
  assert(rpv2transport::deadlineReached(101, 100));
  assert(rpv2transport::deadlineReached(5, UINT32_MAX - 5));

  assert(rpv2transport::statusFlushBackoffMs(1) == 1000UL);
  assert(rpv2transport::statusFlushBackoffMs(2) == 3000UL);
  assert(rpv2transport::statusFlushBackoffMs(3) == 10000UL);
  assert(rpv2transport::statusFlushBackoffMs(4) == 30000UL);
  assert(rpv2transport::statusFlushBackoffMs(255) == 30000UL);
  assert(rpv2transport::statusFlushDue(100, 0));
  assert(!rpv2transport::statusFlushDue(99, 100));
  assert(rpv2transport::statusFlushDue(100, 100));
  assert(
      rpv2transport::clampStatusFlushBudget(1) ==
      rpv2transport::STATUS_FLUSH_NORMAL_BUDGET);
  assert(
      rpv2transport::clampStatusFlushBudget(15) ==
      rpv2transport::STATUS_FLUSH_MAX_BUDGET);
  assert(!rpv2transport::statusFlushSliceExpired(100, 849));
  assert(rpv2transport::statusFlushSliceExpired(100, 850));
  assert(rpv2transport::statusFlushGapElapsed(0, 1));
  assert(!rpv2transport::statusFlushGapElapsed(100, 349));
  assert(rpv2transport::statusFlushGapElapsed(100, 350));
  assert(rpv2transport::statusFlushPriority(true, true) <
         rpv2transport::statusFlushPriority(false, true));
  assert(rpv2transport::statusFlushPriority(false, true) <
         rpv2transport::statusFlushPriority(true, false));
  assert(rpv2transport::isCoalescableStatus("awaiting_points_ack"));
  assert(rpv2transport::isCoalescableStatus("rpv2_commit_sent"));
  assert(!rpv2transport::isCoalescableStatus("rpv2_points_ack"));
  assert(!rpv2transport::isCoalescableStatus("applied"));
  assert(rpv2transport::canReplaceQueuedStatus(true, false));
  assert(!rpv2transport::canReplaceQueuedStatus(false, false));
  assert(!rpv2transport::canReplaceQueuedStatus(false, true));
  assert(!rpv2transport::canReplaceQueuedStatus(true, true));

  assert(rpv2transport::shouldOpenCommitWindow(true, true, true, 2, 2));
  assert(!rpv2transport::shouldOpenCommitWindow(true, true, false, 1, 2));
  assert(!rpv2transport::shouldOpenCommitWindow(false, true, true, 2, 2));

  // shouldOpenFirstPointsWindow
  assert(rpv2transport::shouldOpenFirstPointsWindow(true, true, false, 1, 2));
  assert(rpv2transport::shouldOpenFirstPointsWindow(true, true, false, 1, 1));
  // ACK not sent
  assert(!rpv2transport::shouldOpenFirstPointsWindow(false, true, false, 1, 2));
  // session not active
  assert(!rpv2transport::shouldOpenFirstPointsWindow(true, false, false, 1, 2));
  // stage already complete
  assert(!rpv2transport::shouldOpenFirstPointsWindow(true, true, true, 1, 2));
  // not first fragment (expectedFragment != 1)
  assert(!rpv2transport::shouldOpenFirstPointsWindow(true, true, false, 2, 2));
  // totalChunks == 0
  assert(!rpv2transport::shouldOpenFirstPointsWindow(true, true, false, 1, 0));
  // no conflict: shouldOpenCommitWindow and shouldOpenFirstPointsWindow are mutually exclusive
  // (commit requires stageComplete=true; first-points requires stageComplete=false)
  assert(!(rpv2transport::shouldOpenCommitWindow(true, true, true, 2, 2) &&
           rpv2transport::shouldOpenFirstPointsWindow(true, true, true, 2, 2)));
  assert(rpv2transport::commitSessionMatches(10, 20, 10, 20));
  assert(!rpv2transport::commitSessionMatches(10, 20, 11, 20));
  assert(!rpv2transport::commitSessionMatches(10, 20, 10, 21));
  assert(
      !rpv2transport::commitWaitExpired(
          true, true, true, 14999, 15000));
  assert(
      rpv2transport::commitWaitExpired(
          true, true, true, 15000, 15000));
  assert(
      !rpv2transport::commitWaitExpired(
          true, true, false, 15000, 15000));

  assert(rpv2transport::statusFlushAllowed(false, true, true, true, 1));
  assert(!rpv2transport::statusFlushAllowed(true, true, true, true, 1));
  assert(!rpv2transport::statusFlushAllowed(false, true, true, true, 0));

  uint8_t attempts = 0;
  uint32_t nextAttemptAtMs = 0;
  assert(
      rpv2transport::scheduleStatusFlushRetry(
          attempts, nextAttemptAtMs, 500) == 1000UL);
  assert(attempts == 1);
  assert(nextAttemptAtMs == 1500);
  assert(!rpv2transport::statusFlushDue(501, nextAttemptAtMs));
  assert(rpv2transport::statusFlushDue(1500, nextAttemptAtMs));

  assert(
      rpv2transport::statusFlushContextMatches(
          kFullCommandId, kFullCommandId));
  assert(
      !rpv2transport::statusFlushContextMatches(
          kFullCommandId, "AUTO_AREA_FENCE:truncated"));
  return 0;
}
