/**
 * @file CryptoEngine.cpp
 * @brief Implementação usando mbedTLS nativo do ESP32.
 */
#include "CryptoEngine.h"
#include "config.h"
#include <mbedtls/aes.h>
#include <mbedtls/md.h>
#include <string.h>

static void calcHmac16(const uint8_t* nonce12, const uint8_t* data, size_t len, uint8_t* out16) {
  const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  mbedtls_md_context_t ctx;
  mbedtls_md_init(&ctx);
  mbedtls_md_setup(&ctx, info, 1);
  mbedtls_md_hmac_starts(&ctx, cfg::HMAC_KEY, sizeof(cfg::HMAC_KEY));
  mbedtls_md_hmac_update(&ctx, nonce12, 12);
  mbedtls_md_hmac_update(&ctx, data, len);
  uint8_t full[32];
  mbedtls_md_hmac_finish(&ctx, full);
  memcpy(out16, full, 16);
  mbedtls_md_free(&ctx);
}

bool CryptoEngine::encryptAndSign(const uint8_t* plain, size_t len, uint8_t* outCipher, uint8_t* outTag, const uint8_t* nonce12) {
  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);
  uint8_t iv[16] = {0};
  memcpy(iv, nonce12, 12);
  size_t nc_off = 0;
  uint8_t stream_block[16] = {0};
  mbedtls_aes_setkey_enc(&aes, cfg::AES_KEY, 128);
  mbedtls_aes_crypt_ctr(&aes, len, &nc_off, iv, stream_block, plain, outCipher);
  mbedtls_aes_free(&aes);
  calcHmac16(nonce12, outCipher, len, outTag);
  return true;
}

bool CryptoEngine::verifyAndDecrypt(const uint8_t* cipher, size_t len, const uint8_t* tag, uint8_t* outPlain, const uint8_t* nonce12) {
  uint8_t calc[16];
  calcHmac16(nonce12, cipher, len, calc);
  if (memcmp(calc, tag, 16) != 0) return false;

  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);
  uint8_t iv[16] = {0};
  memcpy(iv, nonce12, 12);
  size_t nc_off = 0;
  uint8_t stream_block[16] = {0};
  mbedtls_aes_setkey_enc(&aes, cfg::AES_KEY, 128);
  mbedtls_aes_crypt_ctr(&aes, len, &nc_off, iv, stream_block, cipher, outPlain);
  mbedtls_aes_free(&aes);
  return true;
}
