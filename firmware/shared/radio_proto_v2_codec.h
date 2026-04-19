#pragma once

#include <Arduino.h>
#include <string.h>
#include "radio_proto_v2_constants.h"
#include "radio_proto_v2_types.h"

namespace rpv2 {

template <typename T>
static inline bool encodeStruct(const T& value, uint8_t* out, size_t outSize, size_t* written = nullptr) {
  if (!out || outSize < sizeof(T)) return false;
  memcpy(out, &value, sizeof(T));
  if (written) *written = sizeof(T);
  return true;
}

template <typename T>
static inline bool decodeStruct(const uint8_t* data, size_t len, T* out) {
  if (!data || !out || len < sizeof(T)) return false;
  memcpy(out, data, sizeof(T));
  return true;
}

static inline bool encodeHeader(const Header& header, uint8_t* out, size_t outSize) {
  return encodeStruct(header, out, outSize, nullptr);
}

static inline bool decodeHeader(const uint8_t* data, size_t len, Header* out) {
  if (!decodeStruct(data, len, out)) return false;
  return out->protocolVersion == PROTOCOL_VERSION &&
      out->headerLen == sizeof(Header);
}

template <typename T>
static inline size_t encodeFrame(
    const Header& header,
    const T& body,
    uint8_t* out,
    size_t outSize) {
  if (!out || outSize < sizeof(Header) + sizeof(T)) return 0;
  memcpy(out, &header, sizeof(Header));
  memcpy(out + sizeof(Header), &body, sizeof(T));
  return sizeof(Header) + sizeof(T);
}

static inline size_t encodePointsFrame(
    const Header& header,
    const FencePointsPrefix& prefix,
    const PointLatLonE7* points,
    uint8_t pointCount,
    uint8_t* out,
    size_t outSize) {
  const size_t need = sizeof(Header) + sizeof(FencePointsPrefix) +
      static_cast<size_t>(pointCount) * sizeof(PointLatLonE7);
  if (!out || outSize < need) return 0;
  memcpy(out, &header, sizeof(Header));
  memcpy(out + sizeof(Header), &prefix, sizeof(FencePointsPrefix));
  if (pointCount > 0 && points) {
    memcpy(
        out + sizeof(Header) + sizeof(FencePointsPrefix),
        points,
        static_cast<size_t>(pointCount) * sizeof(PointLatLonE7));
  }
  return need;
}

static inline bool decodeFenceBegin(
    const uint8_t* data,
    size_t len,
    Header* header,
    FenceBeginBody* body) {
  if (!decodeHeader(data, len, header)) return false;
  if (header->msgType != FENCE_BEGIN || len != sizeof(Header) + sizeof(FenceBeginBody)) return false;
  return decodeStruct(data + sizeof(Header), len - sizeof(Header), body);
}

static inline bool decodeFencePoints(
    const uint8_t* data,
    size_t len,
    Header* header,
    FencePointsPrefix* prefix,
    const PointLatLonE7** points) {
  if (!decodeHeader(data, len, header)) return false;
  if (header->msgType != FENCE_POINTS || len < sizeof(Header) + sizeof(FencePointsPrefix)) return false;
  if (!decodeStruct(data + sizeof(Header), len - sizeof(Header), prefix)) return false;
  const size_t expected = sizeof(Header) + sizeof(FencePointsPrefix) +
      static_cast<size_t>(prefix->pointCount) * sizeof(PointLatLonE7);
  if (len != expected) return false;
  if (points) {
    *points = reinterpret_cast<const PointLatLonE7*>(
        data + sizeof(Header) + sizeof(FencePointsPrefix));
  }
  return true;
}

template <typename T>
static inline bool decodeFixedBodyFrame(
    uint8_t expectedType,
    const uint8_t* data,
    size_t len,
    Header* header,
    T* body) {
  if (!decodeHeader(data, len, header)) return false;
  if (header->msgType != expectedType || len != sizeof(Header) + sizeof(T)) return false;
  return decodeStruct(data + sizeof(Header), len - sizeof(Header), body);
}

}  // namespace rpv2
