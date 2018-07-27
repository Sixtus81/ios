//
//  NCPushNotification.m
//  Nextcloud
//
//  Created by Marino Faggiana on 25/07/18.
//  Copyright © 2018 TWS. All rights reserved.
//
//  Author Marino Faggiana <m.faggiana@twsweb.it>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "NCPushNotification.h"

#import <openssl/rsa.h>
#import <openssl/pem.h>
#import <openssl/bio.h>
#import <openssl/bn.h>
#import <openssl/sha.h>
#import <openssl/err.h>
#import <openssl/ssl.h>
#import <CommonCrypto/CommonDigest.h>

#import "NCEndToEndEncryption.h"
#import "CCUtility.h"

@implementation NCPushNotification

+ (NCPushNotification *)sharedInstance
{
    static dispatch_once_t once;
    static NCPushNotification *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
       
        self.ncPNPublicKey = [CCUtility getPushNotificationPublicKey];
        self.ncPNPrivateKey = [CCUtility getPushNotificationPrivateKey];
    }
    return self;
}

- (BOOL)generatePushNotificationsKeyPair
{
    EVP_PKEY *pkey;
    NSError *keyError;
    pkey = [[NCEndToEndEncryption sharedManager] generateRSAKey:&keyError];
    if (keyError) {
        return NO;
    }
    
    // Extract publicKey, privateKey
    int len;
    char *keyBytes;
    
    // PublicKey
    BIO *publicKeyBIO = BIO_new(BIO_s_mem());
    PEM_write_bio_PUBKEY(publicKeyBIO, pkey);
    
    len = BIO_pending(publicKeyBIO);
    keyBytes  = malloc(len);
    
    BIO_read(publicKeyBIO, keyBytes, len);
    _ncPNPublicKey = [NSData dataWithBytes:keyBytes length:len];
    [CCUtility setPushNotificationPublicKey:_ncPNPublicKey];
    NSLog(@"Push Notifications Key Pair generated: \n%@", [[NSString alloc] initWithData:_ncPNPublicKey encoding:NSUTF8StringEncoding]);
    
    // PrivateKey
    BIO *privateKeyBIO = BIO_new(BIO_s_mem());
    PEM_write_bio_PKCS8PrivateKey(privateKeyBIO, pkey, NULL, NULL, 0, NULL, NULL);
    
    len = BIO_pending(privateKeyBIO);
    keyBytes = malloc(len);
    
    BIO_read(privateKeyBIO, keyBytes, len);
    _ncPNPrivateKey = [NSData dataWithBytes:keyBytes length:len];
    [CCUtility setPushNotificationPrivateKey:_ncPNPrivateKey];
    
    EVP_PKEY_free(pkey);
    
    return YES;
}

- (NSString *)decryptPushNotification:(NSString *)message withDevicePrivateKey:(NSData *)privateKey
{
    NSString *privateKeyString = [[NSString alloc] initWithData:privateKey encoding:NSUTF8StringEncoding];
    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:message options:0];
    char *privKey = (char *)[privateKeyString UTF8String];
    
    // Get Device Private Key from PEM
    BIO *bio = BIO_new(BIO_s_mem());
    BIO_write(bio, privKey, (int)strlen(privKey));
    
    EVP_PKEY* pkey = 0;
    PEM_read_bio_PrivateKey(bio, &pkey, 0, 0);
    
    RSA* rsa = EVP_PKEY_get1_RSA(pkey);
    
    // Decrypt the message
    unsigned char *decrypted = (unsigned char *) malloc(4096);
    
    int decrypted_length = RSA_private_decrypt((int)[decodedData length], [decodedData bytes], decrypted, rsa, RSA_PKCS1_PADDING);
    if(decrypted_length == -1) {
        char buffer[500];
        ERR_error_string(ERR_get_error(), buffer);
        NSLog(@"%@",[NSString stringWithUTF8String:buffer]);
        return nil;
    }
    
    NSString *decryptString = [[NSString alloc] initWithBytes:decrypted length:decrypted_length encoding:NSUTF8StringEncoding];
    
    if (decrypted)
        free(decrypted);
    free(bio);
    free(rsa);
    
    return decryptString;
}


@end
