/***************************************************************
 *
 * Copyright (C) 2020, Condor Team, Computer Sciences Department,
 * University of Wisconsin-Madison, WI.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License"); you
 * may not use this file except in compliance with the License.  You may
 * obtain a copy of the License at
 * 
 *    http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 ***************************************************************/


#ifndef CONDOR_CRYPTO_AESGCM_H
#define CONDOR_CRYPTO_AESGCM_H

#include "condor_crypt.h"          // base class

class Condor_Crypt_AESGCM : public Condor_Crypt_Base {

 public:
//    Condor_Crypt_AESGCM();
//    ~Condor_Crypt_AESGCM();

    // ZKM TODO FIXME: Get rid of these, and any callers should call the
    // reset() method on their state object instead
//    void resetState();
//    static void resetState(ConnCryptoState *connState);
    static void resetState(std::shared_ptr<ConnCryptoState> connState);

    bool encrypt(Condor_Crypto_State *,
                 const unsigned char *,
                 int                  ,
                 unsigned char *&     ,
                 int&                 ) {ASSERT("ZKM: WRONG CALL.\n"); return false;}

    bool decrypt(Condor_Crypto_State *,
                       const unsigned char *,
                       int             ,
                       unsigned char *&,
                       int&            ) {ASSERT("ZKM: WRONG CALL.\n"); return false;}

    bool encrypt(Condor_Crypto_State * cs,
                 const unsigned char * aad_data,
                 int                   aad_data_len,
                 const unsigned char * input,
                 int                   input_len, 
                 unsigned char *       output, 
                 int                   output_len);

    bool decrypt(Condor_Crypto_State * cs,
                 const unsigned char * aad_data,
                 int                   aad_data_len,
                 const unsigned char * input,
                 int                   input_len, 
                 unsigned char *       output, 
                 int&                  output_len);

    virtual int ciphertext_size_with_cs(int plaintext_size, std::shared_ptr<ConnCryptoState> connState) const;

 private:
    // ZKM TODO FIXME: Move all this from m_state to the Condor_Crypto_State param
    //std::shared_ptr<ConnCryptoState> m_conn_state;
};

#endif
