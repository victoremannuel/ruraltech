/**
 * @file HerdingController.h
 * @brief Execução autônoma de condução por fases (polígonos intermediários).
 */
#pragma once
#include "Types.h"
#include "Geofence.h"

class HerdingController {
 public:
  void setPlan(const HerdingPlan& p) { plan_ = p; }
  const HerdingPlan& plan() const { return plan_; }
  bool active() const { return plan_.active; }
  bool updateWithGps(const GpsData& gps, EventRecord* outEvent);

 private:
  HerdingPlan plan_{};
};
