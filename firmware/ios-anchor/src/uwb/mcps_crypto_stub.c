/* mcps_crypto implementation using nrf_oberon (AES) + SoftDevice (TRNG). */

#include "qerr.h"
#include "qmalloc.h"
#include "nrf_soc.h"

#include "ocrypto_aes_cmac.h"
#include "ocrypto_aes_ccm.h"
#include "ocrypto_aes_cbc.h"
#include "ocrypto_aes_key.h"

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <string.h>

#define CCM_STAR_NONCE_LEN 13
#define KEY_SIZE           16

struct ccm_ctx {
    uint8_t key[KEY_SIZE];
};

struct ecb_ctx {
    uint8_t key[KEY_SIZE];
    bool    encrypt;
};

enum qerr mcps_crypto_init(void)
{
    return QERR_SUCCESS;
}

void mcps_crypto_deinit(void)
{
}

enum qerr mcps_crypto_reinit(void)
{
    return QERR_SUCCESS;
}

uint32_t mcps_crypto_get_random(void)
{
    uint32_t val;
    uint8_t  avail = 0;

    while (avail < 4) {
        sd_rand_application_bytes_available_get(&avail);
    }
    sd_rand_application_vector_get((uint8_t *)&val, 4);
    return val;
}

enum qerr mcps_crypto_cmac_aes_128_digest(
    const uint8_t *key, const uint8_t *data,
    unsigned int data_len, uint8_t *out)
{
    ocrypto_aes_cmac_authenticate(out, KEY_SIZE, data, data_len, key, KEY_SIZE);
    return QERR_SUCCESS;
}

enum qerr mcps_crypto_cmac_aes_256_digest(
    const uint8_t *key, const uint8_t *data,
    unsigned int data_len, uint8_t *out)
{
    ocrypto_aes_cmac_authenticate(out, KEY_SIZE, data, data_len, key, 32);
    return QERR_SUCCESS;
}

int mcps_crypto_aead_aes_ccm_star_128_create(void **ctx, const uint8_t *key)
{
    struct ccm_ctx *c = qmalloc(sizeof(*c));
    if (!c) return -1;
    memcpy(c->key, key, KEY_SIZE);
    *ctx = c;
    return 0;
}

void mcps_crypto_aead_aes_ccm_star_128_destroy(void *ctx)
{
    (void)ctx;
}

int mcps_crypto_aead_aes_ccm_star_128_encrypt(
    void *ctx, const uint8_t *nonce, const uint8_t *header,
    unsigned int header_len, uint8_t *data, unsigned int data_len,
    uint8_t *mac, unsigned int mac_len)
{
    struct ccm_ctx *c = ctx;
    ocrypto_aes_ccm_encrypt(
        data, mac, mac_len,
        data, data_len,
        c->key, KEY_SIZE,
        nonce, CCM_STAR_NONCE_LEN,
        header, header_len);
    return 0;
}

int mcps_crypto_aead_aes_ccm_star_128_decrypt(
    void *ctx, const uint8_t *nonce, const uint8_t *header,
    unsigned int header_len, uint8_t *data, unsigned int data_len,
    uint8_t *mac, unsigned int mac_len)
{
    struct ccm_ctx *c = ctx;
    return ocrypto_aes_ccm_decrypt(
        data, mac, mac_len,
        data, data_len,
        c->key, KEY_SIZE,
        nonce, CCM_STAR_NONCE_LEN,
        header, header_len);
}

int mcps_crypto_aes_ecb_128_create_encrypt(void **ctx, const uint8_t *key)
{
    struct ecb_ctx *c = qmalloc(sizeof(*c));
    if (!c) return -1;
    memcpy(c->key, key, KEY_SIZE);
    c->encrypt = true;
    *ctx = c;
    return 0;
}

int mcps_crypto_aes_ecb_128_create_decrypt(void **ctx, const uint8_t *key)
{
    struct ecb_ctx *c = qmalloc(sizeof(*c));
    if (!c) return -1;
    memcpy(c->key, key, KEY_SIZE);
    c->encrypt = false;
    *ctx = c;
    return 0;
}

void mcps_crypto_aes_ecb_128_destroy(void *ctx)
{
    (void)ctx;
}

int mcps_crypto_aes_ecb_128_encrypt_decrypt(
    void *ctx, const uint8_t *data, unsigned int data_len, uint8_t *out)
{
    struct ecb_ctx *c = ctx;
    static const uint8_t zero_iv[16] = {0};

    for (unsigned int off = 0; off < data_len; off += KEY_SIZE) {
        unsigned int blk = data_len - off;
        if (blk > KEY_SIZE) blk = KEY_SIZE;
        if (c->encrypt) {
            ocrypto_aes_cbc_encrypt(out + off, data + off, blk,
                                    c->key, KEY_SIZE, zero_iv);
        } else {
            ocrypto_aes_cbc_decrypt(out + off, data + off, blk,
                                    c->key, KEY_SIZE, zero_iv);
        }
    }
    return 0;
}
