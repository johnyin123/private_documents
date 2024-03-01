#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# pip install cryptography
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives import hashes
import base64, sys, os

def main():
    message = b"Hello world"
    if (len(sys.argv)>1):
        message=str(sys.argv[1]).encode()
    print("Message: ",message)

    with open("srv.key", "rb") as key_file:
        private_key = serialization.load_pem_private_key(key_file.read(), password=None,)

    # public_key = private_key.public_key()
    with open("srv.pem", "rb") as key_file:
        public_key = serialization.load_pem_public_key(key_file.read())
    
    ciphertext = public_key.encrypt(message, padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()),algorithm=hashes.SHA256(), label=None))
    msg=base64.b64encode(ciphertext)
    print("\nEncrypt b64 Message: ", msg.decode())
    newmsg=base64.b64decode(msg)
    plaintext = private_key.decrypt(newmsg,padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()),algorithm=hashes.SHA256(),label=None))
    print("\nDecrypted b64 Message: ",plaintext.decode())
    return 0

if __name__ == '__main__':
    exit(main())
