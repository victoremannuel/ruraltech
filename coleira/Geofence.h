/**
 * @file Geofence.h
 * @brief Cerca virtual e verificação de fases de condução offline.
 */
#pragma once
#include "Types.h"

class Geofence {
 public:
  void setFence(const Polygon& p) { fence_ = p; }
  const Polygon& fence() const { return fence_; }
  bool isInside(const GpsData& gps) const;
  bool isNearBoundary(const GpsData& gps, float warningMeters) const;

 private:
  Polygon fence_{};
  double distanceToSegmentMeters(double lat, double lon, const GeoPoint& a, const GeoPoint& b) const;
};
