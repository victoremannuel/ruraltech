/**
 * @file Geofence.cpp
 * @brief Algoritmos geométricos compactos sem STL para ESP32.
 */
#include "Geofence.h"
#include <math.h>

static double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  constexpr double R = 6371000.0;
  const double dLat = (lat2 - lat1) * DEG_TO_RAD;
  const double dLon = (lon2 - lon1) * DEG_TO_RAD;
  const double a = sin(dLat/2)*sin(dLat/2) + cos(lat1*DEG_TO_RAD)*cos(lat2*DEG_TO_RAD)*sin(dLon/2)*sin(dLon/2);
  return 2*R*atan2(sqrt(a), sqrt(1-a));
}

bool Geofence::isInside(const GpsData& gps) const {
  if (!gps.valid || fence_.count < 3) return false;
  bool c = false;
  for (uint8_t i = 0, j = fence_.count - 1; i < fence_.count; j = i++) {
    const auto& pi = fence_.points[i];
    const auto& pj = fence_.points[j];
    if (((pi.lon > gps.lon) != (pj.lon > gps.lon)) &&
        (gps.lat < (pj.lat - pi.lat) * (gps.lon - pi.lon) / (pj.lon - pi.lon + 1e-12) + pi.lat)) {
      c = !c;
    }
  }
  return c;
}

double Geofence::distanceToSegmentMeters(double lat, double lon, const GeoPoint& a, const GeoPoint& b) const {
  const double da = haversineMeters(lat, lon, a.lat, a.lon);
  const double db = haversineMeters(lat, lon, b.lat, b.lon);
  return da < db ? da : db;
}

bool Geofence::isNearBoundary(const GpsData& gps, float warningMeters) const {
  if (!gps.valid || fence_.count < 3) return false;
  double best = 1e9;
  for (uint8_t i = 0; i < fence_.count; ++i) {
    const GeoPoint& a = fence_.points[i];
    const GeoPoint& b = fence_.points[(i + 1) % fence_.count];
    const double d = distanceToSegmentMeters(gps.lat, gps.lon, a, b);
    if (d < best) best = d;
  }
  return best <= warningMeters;
}
