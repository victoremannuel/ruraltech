/**
 * @file LoRaProtocol.cpp
 * @brief Serialização binária compacta sem alocação dinâmica.
 */
#include "LoRaProtocol.h"

static void wr32(uint8_t* b, uint32_t v) { b[0]=v>>24; b[1]=v>>16; b[2]=v>>8; b[3]=v; }
static uint32_t rd32(const uint8_t* b) { return ((uint32_t)b[0]<<24)|((uint32_t)b[1]<<16)|((uint32_t)b[2]<<8)|b[3]; }
static void wr64(uint8_t* b, uint64_t v) {
  for (int i = 0; i < 8; ++i) b[i] = (uint8_t)(v >> (56 - (i * 8)));
}
static uint64_t rd64(const uint8_t* b) {
  uint64_t v = 0;
  for (int i = 0; i < 8; ++i) v = (v << 8) | (uint64_t)b[i];
  return v;
}

size_t LoRaProtocol::encodePlain(const LoRaFrame& f, uint8_t* out, size_t outMax) {
  const size_t need = 4+8+1+4+4+12+1+f.payloadLen+16;
  if (outMax < need) return 0;
  size_t i = 0;
  wr32(out+i, f.deviceId); i+=4;
  wr64(out+i, f.scopeId); i+=8;
  out[i++] = static_cast<uint8_t>(f.msgType);
  wr32(out+i, f.seq); i+=4;
  wr32(out+i, f.timestamp); i+=4;
  memcpy(out+i, f.nonce, 12); i+=12;
  out[i++] = f.payloadLen;
  memcpy(out+i, f.payload, f.payloadLen); i+=f.payloadLen;
  memcpy(out+i, f.tag, 16); i+=16;
  return i;
}

bool LoRaProtocol::decodePlain(const uint8_t* in, size_t len, LoRaFrame& f) {
  if (len < 50) return false;
  size_t i = 0;
  f.deviceId = rd32(in+i); i+=4;
  f.scopeId = rd64(in+i); i+=8;
  f.msgType = static_cast<MsgType>(in[i++]);
  f.seq = rd32(in+i); i+=4;
  f.timestamp = rd32(in+i); i+=4;
  memcpy(f.nonce, in+i, 12); i+=12;
  f.payloadLen = in[i++];
  if (f.payloadLen > sizeof(f.payload) || i + f.payloadLen + 16 > len) return false;
  memcpy(f.payload, in+i, f.payloadLen); i+=f.payloadLen;
  memcpy(f.tag, in+i, 16);
  return true;
}
