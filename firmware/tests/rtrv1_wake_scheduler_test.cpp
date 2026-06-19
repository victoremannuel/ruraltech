#include <assert.h>

#include "../../gateway-matriz/RtrWakeOrchestrator.h"

int main() {
  rtrwake::SessionCore session{};
  session.active = true;
  session.deviceId = 1234;
  session.maxCampaigns = 2;
  session.state = rtrwake::State::PAGING_WAITING_UPLINK;

  session.state = rtrwake::State::PAGING_AWAITING_ACK;
  assert(!rtrwake::inFlightAttemptSoftTimedOut(session, 1000));
  assert(rtrwake::awaitingAckWithoutPageSent(session));

  session.state = rtrwake::State::PAGING_WAITING_UPLINK;
  assert(rtrwake::noteUplinkHint(&session, 1234, 1000));
  assert(session.state == rtrwake::State::PAGING_READY_TO_SEND);
  assert(session.lastUplinkAtMs == 1000);
  assert(session.nextPageAttemptAtMs == 1000);

  rtrwake::markPageAttempt(&session, 1100, 1500);
  session.state = rtrwake::State::PAGING_AWAITING_ACK;
  assert(session.campaignCount == 1);
  assert(session.pageAckDeadlineAtMs == 2600);
  assert(!rtrwake::awaitingAckWithoutPageSent(session));
  assert(rtrwake::inFlightAttemptSoftTimedOut(session, 2600));
  assert(!rtrwake::inFlightAttemptHardTimedOut(session, 2600));
  assert(rtrwake::canRetryAfterTimeout(session));

  rtrwake::scheduleRetryReadyToSend(&session, 2600, rtrv1::PAGE_RETRY_GRACE_MS);
  assert(session.state == rtrwake::State::PAGING_RETRY_GRACE);
  assert(session.pageSent);
  assert(session.scheduledRetry.pending);
  assert(session.scheduledRetry.retryAtMs == 2600 + rtrv1::PAGE_RETRY_GRACE_MS);
  assert(session.cloudTxDeferred);
  assert(!rtrwake::retryReadyToSend(session, 2600 + rtrv1::PAGE_RETRY_GRACE_MS));
  rtrwake::expireInFlightAttempt(&session);
  assert(rtrwake::retryReadyToSend(session, 2600 + rtrv1::PAGE_RETRY_GRACE_MS));

  rtrwake::markPageAttempt(&session, 5000, 1500);
  session.state = rtrwake::State::PAGING_AWAITING_ACK;
  assert(session.campaignCount == 2);
  assert(rtrwake::inFlightAttemptSoftTimedOut(session, 6500));
  assert(!rtrwake::canRetryAfterTimeout(session));
  assert(rtrwake::inFlightAttemptHardTimedOut(
      session,
      6500 + rtrv1::PAGE_RETRY_GRACE_MS));
  assert(!rtrwake::canRetryAfterTimeout(session));

  return 0;
}
