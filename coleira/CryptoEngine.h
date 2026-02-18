/**
 * @file CryptoEngine.h
 * @brief AES-CTR + HMAC-SHA256 para LoRa com anti-replay por nonce.
 */
#pragma once
#include <Arduino.h>

class CryptoEngine {
 public:
  bool encryptAndSign(const uint8_t* plain, size_t len, uint8_t* outCipher, uint8_t* outTag, const uint8_t* nonce12);
  bool verifyAndDecrypt(const uint8_t* cipher, size_t len, const uint8_t* tag, uint8_t* outPlain, const uint8_t* nonce12);
};
