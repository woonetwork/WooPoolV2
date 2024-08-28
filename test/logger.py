#from eth_abi import encode
#import secrets
#from web3 import Web3
import argparse
import logging
import sys

logger = logging.getLogger()
logger.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s | %(levelname)s | %(message)s')

stdout_handler = logging.StreamHandler(sys.stdout)
stdout_handler.setLevel(logging.DEBUG)
stdout_handler.setFormatter(formatter)

file_handler = logging.FileHandler('logs.log')
file_handler.setLevel(logging.DEBUG)
file_handler.setFormatter(formatter)


logger.addHandler(file_handler)
# logger.addHandler(stdout_handler)

def main(args):

    # Generate a 10-byte random number
    #random = int(secrets.token_hex(10), 16)

    # Generate the keccak hash of the input value
    #hashed = Web3.solidity_keccak(['uint256'], [0])
    #hashed = b')\r\xec\xd9T\x8bb\xa8\xd6\x03E\xa9\x888o\xc8K\xa6\xbc\x95H@\x08\xf66/\x93\x16\x0e\xf3\xe5c'

    # ABI-encode the output
    #abi_encoded = encode(['bytes32'], [hashed]).hex()
    abi_encoded = "290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563"

    # Make sure that it doesn't print a newline character
    print("0x" + abi_encoded, end="")

    text = args.text + " " + args.total + " " + args.p0 + " " + args.p1 + " " + args.p2 + " " + args.p3
    logger.info(text)

def parse_args(): 
    """
    Add more input values here by:
    ```parser.add_argument("--new_var", type=int)```
    Note: the order of these variables must match the order they are placed in in the solidity test
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--text", type=str)
    parser.add_argument("--total", type=str)
    parser.add_argument("--p0", type=str)
    parser.add_argument("--p1", type=str)
    parser.add_argument("--p2", type=str)
    parser.add_argument("--p3", type=str)
    parser.add_argument("--i", type=int)
    return parser.parse_args()

if __name__ == '__main__':
    args = parse_args() 
    main(args)