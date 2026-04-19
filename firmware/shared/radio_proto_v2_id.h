#pragma once

#include <Arduino.h>

namespace rpv2 {

static inline uint64_t fnv1a64(const char* text) {
  const uint8_t* p = reinterpret_cast<const uint8_t*>(text ? text : "");
  uint64_t hash = 14695981039346656037ULL;
  while (*p) {
    hash ^= static_cast<uint64_t>(*p++);
    hash *= 1099511628211ULL;
  }
  return hash;
}

}  // namespace rpv2
