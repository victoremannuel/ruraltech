#pragma once

#include <Arduino.h>
#include <string.h>
#include "radio_transport_v1_constants.h"
#include "radio_transport_v1_types.h"

namespace rtrv1 {

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
  return out->version == PROTOCOL_VERSION &&
      out->ttl != 0;
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

template <typename T>
static inline bool decodeFixedBodyFrame(
    uint8_t expectedType,
    const uint8_t* data,
    size_t len,
    Header* header,
    T* body) {
  if (!decodeHeader(data, len, header)) return false;
  if (header->innerMsgType != expectedType || len != sizeof(Header) + sizeof(T)) return false;
  return decodeStruct(data + sizeof(Header), len - sizeof(Header), body);
}

static inline bool decodePage(
    const uint8_t* data,
    size_t len,
    Header* header,
    PageBody* body) {
  return decodeFixedBodyFrame(RTR_PAGE, data, len, header, body);
}

static inline bool decodePageAck(
    const uint8_t* data,
    size_t len,
    Header* header,
    PageAckBody* body) {
  return decodeFixedBodyFrame(RTR_PAGE_ACK, data, len, header, body);
}

}  // namespace rtrv1
