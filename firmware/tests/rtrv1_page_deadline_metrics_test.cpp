#include <assert.h>

#include "../../gateway-matriz/RtrWakeOrchestrator.h"

int main() {
  rtrwake::SessionCore core{};
  core.deviceId = 88;
  core.lastUplinkAtMs = 1000;
  core.lastPageSentAtMs = 1180;

  const rtrwake::FastPathMetric metric =
      rtrwake::computeFastPathMetric(core, rtrv1::FAST_PAGE_DEADLINE_MS);
  assert(metric.valid);
  assert(metric.deltaMs == 180);
  assert(metric.deadlineMet);
  assert(metric.deltaMs <= rtrv1::FAST_PAGE_DEADLINE_MS);

  core.lastPageSentAtMs = 1405;
  const rtrwake::FastPathMetric lateMetric =
      rtrwake::computeFastPathMetric(core, rtrv1::FAST_PAGE_DEADLINE_MS);
  assert(lateMetric.valid);
  assert(lateMetric.deltaMs == 405);
  assert(!lateMetric.deadlineMet);
  assert(lateMetric.deltaMs < rtrv1::PAGE_ACK_TIMEOUT_MS);
  return 0;
}
