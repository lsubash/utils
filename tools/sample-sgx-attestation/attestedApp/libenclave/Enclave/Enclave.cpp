/*
 * Copyright (C) 2021 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */


#include <stdarg.h>
#include <stdio.h>
#include <string.h>

// Needed for report generation.
#include "sgx_trts.h"
#include "sgx_error.h"
#include "sgx_report.h"
#include "sgx_utils.h"
#include "sgx_tcrypto.h"
#include "tsgxsslio.h"

// SGXSSL's openssl
#include "openssl/bn.h"
#include "openssl/aes.h"
#include "openssl/evp.h"
#include "openssl/err.h"
#include "openssl/bn.h"
#include "openssl/rsa.h"

#include "pthread.h"

#include "user_types.h"
#include "Enclave.h"
#include "Enclave_t.h"

#include <iostream>
using namespace std;

/*Global copy of RSA key pair */
static ref_rsa_params_t g_rsa_key;

/*Global copy of SWK */
static uint8_t *enclave_swk = NULL;
static size_t enclave_swk_size = 0;

/* Have we generated RSA key pair already? */
static bool key_pair_created = false;

/* Have we received SWK already? */
static bool swk_received = false;


int formatted_info_print(const char* fmt, ...)
{
    char buf[BUFSIZ] = { '\0' };

    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, BUFSIZ, fmt, ap);
    va_end(ap);

    ocall_print_info_string(buf);

    return (int)strnlen(buf, BUFSIZ - 1) + 1;
}

sgx_status_t enclave_pubkey(ref_rsa_params_t* key) {
    sgx_status_t ret_code;
    key->e[0] = 0x10001;
    g_rsa_key.e[0] = 0x10001;
    
    if (!key_pair_created) {

        ret_code = sgx_create_rsa_key_pair(REF_N_SIZE_IN_BYTES,
                                           REF_E_SIZE_IN_BYTES,
                                           (unsigned char*)g_rsa_key.n,
                                           (unsigned char*)g_rsa_key.d,
                                           (unsigned char*)g_rsa_key.e,
                                           (unsigned char*)g_rsa_key.p,
                                           (unsigned char*)g_rsa_key.q,
                                           (unsigned char*)g_rsa_key.dmp1,
                                           (unsigned char*)g_rsa_key.dmq1,
                                           (unsigned char*)g_rsa_key.iqmp);

        if (ret_code != SGX_SUCCESS) {
            ocall_print_error_string("RSA key pair creation failed.");
            return ret_code;
        }
        key_pair_created = true;
    }
    
    for(int i=0; i<REF_N_SIZE_IN_BYTES; i++) {
        key->n[i] = g_rsa_key.n[i];
    }
    for(int i=0; i<REF_E_SIZE_IN_BYTES; i++) {
        key->e[i] = g_rsa_key.e[i];
    }

    return SGX_SUCCESS;
}

uint32_t enclave_create_report(const sgx_target_info_t* p_qe3_target,
			       char *nonceStr, sgx_report_t* p_report) {

     sgx_report_data_t reportData{};
     // Convert Nonce string to Bignum.
     BIGNUM *p = BN_new();
     BN_dec2bn(&p, nonceStr);

     int nonce_len = BN_num_bytes (p);
     if ( !(nonce_len > 0 && nonce_len <= NONCE_MAX_BYTES) ) {
	  ocall_print_error_string("Nonce is not in expected range.");
	  return SGX_ERROR_UNEXPECTED;
     }

     unsigned char *nonce_buffer = (unsigned char *) malloc (nonce_len);
     if (!nonce_buffer) {
	  ocall_print_error_string("Nonce buffer memory allocation failed.");
	  return SGX_ERROR_UNEXPECTED;
     }

     BN_bn2bin(p, nonce_buffer);

    const uint32_t size = REF_N_SIZE_IN_BYTES + REF_E_SIZE_IN_BYTES + nonce_len;

    uint8_t* pdata = (uint8_t *) malloc (REF_N_SIZE_IN_BYTES + REF_E_SIZE_IN_BYTES + nonce_len);
    if (!pdata) {
        ocall_print_error_string("Userdata memory allocation failed.");
        return SGX_ERROR_UNEXPECTED;
    }

    ref_rsa_params_t key;
    key.e[0] = 0x10001;

    for(int i=0; i<REF_N_SIZE_IN_BYTES; i++) {
        key.n[i] = g_rsa_key.n[i];
    }
    for(int i=0; i<REF_E_SIZE_IN_BYTES; i++) {
        key.e[i] = g_rsa_key.e[i];
    }
    unsigned char* e1 = ((unsigned char *)key.e);
    unsigned char* m1 = ((unsigned char *)key.n);

    errno_t err = 0;
    err = memcpy_s(pdata, REF_E_SIZE_IN_BYTES, e1, REF_E_SIZE_IN_BYTES);
    if (err != 0) {
	 ocall_print_error_string("memcpy of exponent failed.");
	 free(pdata);
	 return SGX_ERROR_UNEXPECTED;
    }

    err = memcpy_s(pdata + REF_E_SIZE_IN_BYTES, REF_N_SIZE_IN_BYTES, m1, REF_N_SIZE_IN_BYTES);
    if (err != 0) {
	 ocall_print_error_string("memcpy of modulus failed.");
	 free(pdata);
	 return SGX_ERROR_UNEXPECTED;
    }

    err = memcpy_s(pdata + REF_E_SIZE_IN_BYTES + REF_N_SIZE_IN_BYTES, nonce_len,
		   nonce_buffer, nonce_len);
    if (err != 0) {
	 ocall_print_error_string("memcpy of nonce failed.");
	 free(pdata);
	 return SGX_ERROR_UNEXPECTED;
    }


    /* 
     * UserData in SGX Quote : The enclave can add any payload, not just the hash
     * of the publickey. In this example, userData field is used to verify
     * whether the public key received by the attestedApp is indeed
     * generated by the enclave.
     *
     * Refer attestedApp/controllers/external_verifier.go VerifyQuote
     * function.
     */
    uint8_t msg_hash[64] = {0};
    sgx_status_t status = sgx_sha256_msg(pdata, size, (sgx_sha256_hash_t *)msg_hash);
    if (SGX_SUCCESS != status) {
        ocall_print_error_string("Hash of userdata failed!");
	free(pdata);
        return status;
    }

    err = memcpy_s(reportData.d, sizeof(msg_hash), msg_hash, sizeof(msg_hash));
    if (err != 0) {
	 ocall_print_error_string("memcpy of userdata hash failed.");
	 free(pdata);
	 return SGX_ERROR_UNEXPECTED;
    }

    free(pdata);
    // Generate the report for the app_enclave
    sgx_status_t  sgx_error = sgx_create_report(p_qe3_target, &reportData, p_report);

    return sgx_error;
}

sgx_status_t aes_256gcm_decrypt(const aes_gcm_256bit_key_t *p_key, const uint8_t *p_src,
				uint32_t src_len, uint8_t *p_dst, const uint8_t *p_iv, uint32_t iv_len,
				const uint8_t *p_aad, uint32_t aad_len, const sgx_aes_gcm_128bit_tag_t *p_in_mac)
{
     uint8_t l_tag[SGX_AESGCM_MAC_SIZE];

     if ((src_len >= INT_MAX) || (aad_len >= INT_MAX) || (p_key == NULL) || ((src_len > 0) && (p_dst == NULL)) || ((src_len > 0) && (p_src == NULL))
	 || (p_in_mac == NULL) || (iv_len != SGX_AESGCM_IV_SIZE) || ((aad_len > 0) && (p_aad == NULL))
	 || (p_iv == NULL) || ((p_src == NULL) && (p_aad == NULL)))
     {
	  return SGX_ERROR_INVALID_PARAMETER;
     }
     int len = 0;
     sgx_status_t ret = SGX_ERROR_UNEXPECTED;
     EVP_CIPHER_CTX * pState = NULL;

     // Autenthication Tag returned by Decrypt to be compared with Tag created during seal
     errno_t err;
     err = memset_s(&l_tag, SGX_AESGCM_MAC_SIZE, 0, SGX_AESGCM_MAC_SIZE);
     if (err != 0) {
	  ocall_print_error_string("memset of MAC failed.");
	  return SGX_ERROR_UNEXPECTED;
     }


     err = memcpy_s(l_tag, SGX_AESGCM_MAC_SIZE, p_in_mac, SGX_AESGCM_MAC_SIZE);
     if (err != 0) {
	  ocall_print_error_string("memcpy of MAC failed.");
	  return SGX_ERROR_UNEXPECTED;
     }

     do {
	  // Create and initialise the context
	  if (!(pState = EVP_CIPHER_CTX_new())) {
	       ret = SGX_ERROR_OUT_OF_MEMORY;
	       break;
	  }

	  // Initialise decrypt, key and IV
	  if (!EVP_DecryptInit_ex(pState, EVP_aes_256_gcm(), NULL, (unsigned char*)p_key, p_iv)) {
	       break;
	  }

	  // Provide AAD data if exist
	  if (NULL != p_aad) {
	       if (!EVP_DecryptUpdate(pState, NULL, &len, p_aad, aad_len)) {
		    break;
	       }
	  }

	  // Decrypt message, obtain the plaintext output
	  if (!EVP_DecryptUpdate(pState, p_dst, &len, p_src, src_len)) {
	       break;
	  }

	  // Update expected tag value
	  //
	  if (!EVP_CIPHER_CTX_ctrl(pState, EVP_CTRL_GCM_SET_TAG, SGX_AESGCM_MAC_SIZE, l_tag)) {
	       break;
	  }

	  // Finalise the decryption. A positive return value indicates success,
	  // anything else is a failure - the plaintext is not trustworthy.
	  if (EVP_DecryptFinal_ex(pState, p_dst + len, &len) <= 0) {
	       ret = SGX_ERROR_MAC_MISMATCH;
	       break;
	  }
	  ret = SGX_SUCCESS;
     } while (0);

     // Clean up and return
     if (pState != NULL) {
	  EVP_CIPHER_CTX_free(pState);
     }

     err = memset_s(&l_tag, SGX_AESGCM_MAC_SIZE, 0, SGX_AESGCM_MAC_SIZE);
     if (err != 0) {
	  ocall_print_error_string("memset of MAC failed.");
	  return SGX_ERROR_UNEXPECTED;
     }

     return ret;
}

sgx_status_t provision_swk_wrapped_secret(uint8_t* wrappedSecret, uint32_t wrappedSecretSize)
{
    /*
      wrappedSecret format :
      <IV:SGX_AESGCM_IV_SIZE><CipherText:n><MAC:SGX_AESGCM_MAC_SIZE>
    */

    sgx_status_t ret_code= SGX_SUCCESS;

    formatted_info_print ("Received wrappedSecret of size : %d", wrappedSecretSize);

    // We don't have the SWK yet!
    if (!swk_received) {
        ocall_print_error_string("We don't have the SWK yet!");
        return SGX_ERROR_UNEXPECTED;
    }

    // Plaintext Output Buffer.
    int plaintext_len = wrappedSecretSize - (SGX_AESGCM_IV_SIZE + SGX_AESGCM_MAC_SIZE);
    uint8_t *plaintext = (uint8_t *) malloc (plaintext_len);
    if (!plaintext) {
        ocall_print_error_string("Plaintext buffer memory allocation failed.");
        return SGX_ERROR_UNEXPECTED;
    }

    // Cipher text
    uint32_t cipher_text_len = wrappedSecretSize - (SGX_AESGCM_IV_SIZE + SGX_AESGCM_MAC_SIZE);
    formatted_info_print ("Cipher Text Length : %d", cipher_text_len);

    // Copy of SWK
    aes_gcm_256bit_key_t *sk_key = (aes_gcm_256bit_key_t *)malloc (sizeof(aes_gcm_256bit_key_t));
    if (!sk_key) {
        ocall_print_error_string("SWK buffer memory allocation failed.");
        return SGX_ERROR_UNEXPECTED;
    }

    errno_t err;
    err = memcpy_s (sk_key, AESGCM_256_KEY_SIZE, enclave_swk, AESGCM_256_KEY_SIZE);
    if (err != 0) {
	 ocall_print_error_string("memcpy of SWK failed.");
	 return SGX_ERROR_UNEXPECTED;
    }

    // Extract the MAC from the transmitted cipher text
    sgx_aes_gcm_128bit_tag_t mac;
    err = memcpy_s (mac, SGX_AESGCM_MAC_SIZE, wrappedSecret + SGX_AESGCM_IV_SIZE+ plaintext_len, SGX_AESGCM_MAC_SIZE);
    if (err != 0) {
	 ocall_print_error_string("memcpy of MAC failed.");
	 return SGX_ERROR_UNEXPECTED;
    }

    // IV initialisation
    uint8_t iv_length = SGX_AESGCM_IV_SIZE;
    unsigned char iv[SGX_AESGCM_IV_SIZE];
    err = memcpy_s (iv, SGX_AESGCM_IV_SIZE, wrappedSecret, SGX_AESGCM_IV_SIZE);
    if (err != 0) {
	 ocall_print_error_string("memcpy of wrapped secret failed.");
	 return SGX_ERROR_UNEXPECTED;
    }

    ret_code = aes_256gcm_decrypt(sk_key, // Key
				  wrappedSecret + SGX_AESGCM_IV_SIZE, // Cipher text
				  cipher_text_len, //Cipher len
				  plaintext, // Plaintext
				  iv, // Initialisation vector
				  iv_length, // IV Length
				  NULL, // AAD Buffer
				  0, // AAD Length
				  &mac); // MAC


    if (SGX_SUCCESS != ret_code) {
        ocall_print_error_string("Secret decryption failed!");
        return ret_code;
    }

    uint8_t *plaintext_printable = (uint8_t *)malloc (plaintext_len);
    if (!plaintext_printable) {
	 ocall_print_error_string("Plaintext Printable buffer memory allocation failed.");
	 return SGX_ERROR_UNEXPECTED;
    }

    err = memcpy_s (plaintext_printable, plaintext_len, plaintext, plaintext_len);
    if (err != 0) {
	 ocall_print_error_string("memcpy of SWK failed.");
	 return SGX_ERROR_UNEXPECTED;
    }

    plaintext_printable[plaintext_len] = '\0';

    formatted_info_print ("Secret in plain text : |%s|", plaintext_printable);

    ocall_print_info_string("Secret unwrapped successfully...");

    return SGX_SUCCESS;
}

sgx_status_t create_rsa_priv2_key(int mod_size, int exp_size, const unsigned char *p_rsa_key_e, const unsigned char *p_rsa_key_p, const unsigned char *p_rsa_key_q,
				  const unsigned char *p_rsa_key_dmp1, const unsigned char *p_rsa_key_dmq1, const unsigned char *p_rsa_key_iqmp,
				  void **new_pri_key2)
{
     if (mod_size <= 0 || exp_size <= 0 || new_pri_key2 == NULL ||
	 p_rsa_key_e == NULL || p_rsa_key_p == NULL || p_rsa_key_q == NULL || p_rsa_key_dmp1 == NULL ||
	 p_rsa_key_dmq1 == NULL || p_rsa_key_iqmp == NULL) {
	  return SGX_ERROR_INVALID_PARAMETER;
     }

     bool rsa_memory_manager = 0;
     EVP_PKEY *rsa_key = NULL;
     RSA *rsa_ctx = NULL;
     sgx_status_t ret_code = SGX_ERROR_UNEXPECTED;
     BIGNUM* n = NULL;
     BIGNUM* e = NULL;
     BIGNUM* d = NULL;
     BIGNUM* dmp1 = NULL;
     BIGNUM* dmq1 = NULL;
     BIGNUM* iqmp = NULL;
     BIGNUM* q = NULL;
     BIGNUM* p = NULL;
     BN_CTX* tmp_ctx = NULL;

     do {
	  tmp_ctx = BN_CTX_new();
	  NULL_BREAK(tmp_ctx);
	  n = BN_new();
	  NULL_BREAK(n);

	  // Convert RSA params to BNs
	  p = BN_lebin2bn(p_rsa_key_p, (mod_size / 2), p);
	  BN_CHECK_BREAK(p);
	  q = BN_lebin2bn(p_rsa_key_q, (mod_size / 2), q);
	  BN_CHECK_BREAK(q);
	  dmp1 = BN_lebin2bn(p_rsa_key_dmp1, (mod_size / 2), dmp1);
	  BN_CHECK_BREAK(dmp1);
	  dmq1 = BN_lebin2bn(p_rsa_key_dmq1, (mod_size / 2), dmq1);
	  BN_CHECK_BREAK(dmq1);
	  iqmp = BN_lebin2bn(p_rsa_key_iqmp, (mod_size / 2), iqmp);
	  BN_CHECK_BREAK(iqmp);
	  e = BN_lebin2bn(p_rsa_key_e, (exp_size), e);
	  BN_CHECK_BREAK(e);

	  if (!BN_mul(n, p, q, tmp_ctx)) {
	       break;
	  }

	  d = BN_dup(n);
	  NULL_BREAK(d);

	  BN_set_flags(d, BN_FLG_CONSTTIME);
	  BN_set_flags(e, BN_FLG_CONSTTIME);

	  if (!BN_sub(d, d, p) || !BN_sub(d, d, q) || !BN_add_word(d, 1) || !BN_mod_inverse(d, e, d, tmp_ctx)) {
	       break;
	  }

	  // Allocates and initializes an RSA key structure
	  rsa_ctx = RSA_new();
	  rsa_key = EVP_PKEY_new();
	  if (rsa_ctx == NULL || rsa_key == NULL || !EVP_PKEY_assign_RSA(rsa_key, rsa_ctx)) {
	       RSA_free(rsa_ctx);
	       rsa_key = NULL;
	       break;
	  }

	  if (!RSA_set0_factors(rsa_ctx, p, q)) {
	       break;
	  }
	  rsa_memory_manager = 1;
	  if (!RSA_set0_crt_params(rsa_ctx, dmp1, dmq1, iqmp)) {
	       BN_clear_free(n);
	       BN_clear_free(e);
	       BN_clear_free(d);
	       BN_clear_free(dmp1);
	       BN_clear_free(dmq1);
	       BN_clear_free(iqmp);
	       break;
	  }

	  if (!RSA_set0_key(rsa_ctx, n, e, d)) {
	       BN_clear_free(n);
	       BN_clear_free(e);
	       BN_clear_free(d);
	       break;
	  }

	  *new_pri_key2 = rsa_key;
	  ret_code = SGX_SUCCESS;
     } while (0);

     BN_CTX_free(tmp_ctx);

     // In case of failure, free allocated BNs and RSA struct
     if (ret_code != SGX_SUCCESS) {
	  // BNs were not assigned to rsa ctx yet, user code must free allocated BNs
	  if (!rsa_memory_manager) {
	       BN_clear_free(n);
	       BN_clear_free(e);
	       BN_clear_free(d);
	       BN_clear_free(dmp1);
	       BN_clear_free(dmq1);
	       BN_clear_free(iqmp);
	       BN_clear_free(q);
	       BN_clear_free(p);
	  }
	  EVP_PKEY_free(rsa_key);
     }

     return ret_code;
}

sgx_status_t rsa_priv_decrypt_sha256(const void* rsa_key, unsigned char* pout_data, size_t* pout_len, const unsigned char* pin_data,
				     const size_t pin_len)
{
     if (rsa_key == NULL || pout_len == NULL || pin_data == NULL || pin_len < 1 || pin_len >= INT_MAX) {
	  return SGX_ERROR_INVALID_PARAMETER;
     }

     EVP_PKEY_CTX *ctx = NULL;
     size_t data_len = 0;
     sgx_status_t ret_code = SGX_ERROR_UNEXPECTED;

     do {
	  // Allocate and init PKEY_CTX
	  ctx = EVP_PKEY_CTX_new((EVP_PKEY*)rsa_key, NULL);
	  if ((ctx == NULL) || (EVP_PKEY_decrypt_init(ctx) < 1)) {
	       break;
	  }

	  //set the RSA padding mode, init it to use SHA256
	  EVP_PKEY_CTX_set_rsa_padding(ctx, RSA_PKCS1_OAEP_PADDING);
	  EVP_PKEY_CTX_set_rsa_oaep_md(ctx, EVP_sha256());
	  EVP_PKEY_CTX_set_rsa_mgf1_md(ctx, EVP_sha256());

	  if (EVP_PKEY_decrypt(ctx, NULL, &data_len, pin_data, pin_len) <= 0) {
	       break;
	  }

	  if(pout_data == NULL) {
	       *pout_len = data_len;
	       ret_code = SGX_SUCCESS;
	       break;
	  }
	  else if(*pout_len < data_len) {
	       ret_code = SGX_ERROR_INVALID_PARAMETER;
	       break;
	  }

	  if (EVP_PKEY_decrypt(ctx, pout_data, pout_len, pin_data, pin_len) <= 0) {
	       break;
	  }
	  ret_code = SGX_SUCCESS;
     }
     while (0);

     EVP_PKEY_CTX_free(ctx);

     return ret_code;
}

sgx_status_t provision_pubkey_wrapped_swk(uint8_t* wrappedSWK, uint32_t wrappedSWKSize) 
{
    sgx_status_t ret_code= SGX_SUCCESS;
    size_t swk_size;

    // Build the private key.
    void *priv_key = NULL;
    ret_code = create_rsa_priv2_key(REF_N_SIZE_IN_BYTES,
                                        REF_E_SIZE_IN_BYTES,
                                        (const unsigned char*)g_rsa_key.e,
                                        (const unsigned char*)g_rsa_key.p,
                                        (const unsigned char*)g_rsa_key.q,
                                        (const unsigned char*)g_rsa_key.dmp1,
                                        (const unsigned char*)g_rsa_key.dmq1,
                                        (const unsigned char*)g_rsa_key.iqmp,
                                        &priv_key);

    if (SGX_SUCCESS != ret_code) {
        ocall_print_error_string("create_rsa_priv2_key - Unable to create private key");
        return ret_code;
    }

    // Unwrap using Private Key
    // Pass NULL to calculate the length of the output buffer.
    ret_code = rsa_priv_decrypt_sha256(priv_key,
				       NULL, ///Pointer to the output decrypted data buffer.
				       &swk_size,///Length of the output decrypted data buffer.
				       wrappedSWK,///Pointer to the input data buffer to be decrypted.
				       wrappedSWKSize);

    if (SGX_SUCCESS != ret_code) {
        ocall_print_error_string("sgx_rsa_priv_decrypt_sha256 unable to calculate buffer size.");
        return ret_code;
    } 

    // Note : Somehow swk_size defaults to len (n) + len (p). We'll
    // snip the buffer when we get the right length. Bug ?
    unsigned char *decryptedBuffer = (unsigned char*)OPENSSL_malloc(swk_size);
    if (!decryptedBuffer) {
        ocall_print_error_string("malloc of decryptedBuffer failed!");
        return SGX_ERROR_UNEXPECTED;        
    }

    ret_code = rsa_priv_decrypt_sha256(priv_key,
				       decryptedBuffer,//Pointer to the output decrypted data buffer.
				       &swk_size, //Length of the output decrypted data buffer.
				       wrappedSWK, //Pointer to the input data buffer to be decrypted.
				       wrappedSWKSize); //size of input data buffer.

    if (ret_code != SGX_SUCCESS) {
        ocall_print_error_string("Decrypt failed. Check error code.");
        return ret_code;
    }

    // Global copy.
    enclave_swk = (uint8_t*) malloc (swk_size);
    if (!enclave_swk) {
        ocall_print_error_string("Enclave SWK buffer memory allocation failed.");
        return SGX_ERROR_UNEXPECTED;
    }

    errno_t err = 0;
    err = memcpy_s(enclave_swk, swk_size, decryptedBuffer, swk_size);
    if (err != 0) {
	 ocall_print_error_string("memcpy of exponent failed.");
	 return SGX_ERROR_UNEXPECTED;
    }

    enclave_swk_size = swk_size;

    swk_received = true;

    ocall_print_info_string("Successfully decrypted SWK.");

    return SGX_SUCCESS;
}
