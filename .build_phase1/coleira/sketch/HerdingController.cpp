#line 1 "/Users/victor/Downloads/code/ruraltech/coleira/HerdingController.cpp"
/**
 * @file HerdingController.cpp
 * @brief Lógica local: troca de fase e finalização de condução.
 */
#include "HerdingController.h"

bool HerdingController::updateWithGps(const GpsData& gps, EventRecord* outEvent) {
  if (!plan_.active || plan_.phaseCount == 0 || !gps.valid) return false;

  Geofence g;
  g.setFence(plan_.phases[plan_.currentPhase]);
  if (g.isInside(gps)) {
    if (plan_.currentPhase + 1 < plan_.phaseCount) {
      plan_.currentPhase++;
      if (outEvent) {
        outEvent->type = EventType::HERD_PHASE_CHANGE;
        outEvent->d1 = plan_.currentPhase;
      }
      return true;
    }
    plan_.active = false;
    if (outEvent) outEvent->type = EventType::HERD_DONE;
    return true;
  }
  return false;
}
