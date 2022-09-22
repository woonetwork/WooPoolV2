/*

░██╗░░░░░░░██╗░█████╗░░█████╗░░░░░░░███████╗██╗
░██║░░██╗░░██║██╔══██╗██╔══██╗░░░░░░██╔════╝██║
░╚██╗████╗██╔╝██║░░██║██║░░██║█████╗█████╗░░██║
░░████╔═████║░██║░░██║██║░░██║╚════╝██╔══╝░░██║
░░╚██╔╝░╚██╔╝░╚█████╔╝╚█████╔╝░░░░░░██║░░░░░██║
░░░╚═╝░░░╚═╝░░░╚════╝░░╚════╝░░░░░░░╚═╝░░░░░╚═╝

*
* MIT License
* ===========
*
* Copyright (c) 2020 WooTrade
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

import { expect, use } from 'chai';
import { Contract, utils } from 'ethers';
import { ethers } from 'hardhat';
import { deployContract, deployMockContract, solidity } from 'ethereum-waffle';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { MasterChefWoo, WooSimpleRewarder } from '../../typechain';
import TestERC20TokenArtifact from '../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json';
import MasterChefWooArtifact from '../../artifacts/contracts/MasterChefWoo.sol/MasterChefWoo.json';
import WooSimpleRewarderArtifact from '../../artifacts/contracts/WooSimpleRewarder.sol/WooSimpleRewarder.json';

use(solidity);

const { BigNumber } = ethers;

const ONE = BigNumber.from(10).pow(18);
const TOKEN_100 = ONE.mul(100);
const PRICE_DEC = BigNumber.from(10).pow(8);

describe('WooPPV2 Integration tests', () => {
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  let masterCW: MasterChefWoo;
  let wooSR: WooSimpleRewarder;
  let xWooToken: Contract;
  let weToken: Contract;
  let rewardToken: Contract;

  let ownerAddr: string;

  before('Deploy contracts', async () => {
    [owner, user1, user2] = await ethers.getSigners();
    ownerAddr = owner.address;

    xWooToken = await deployContract(owner, TestERC20TokenArtifact, []);
    weToken = await deployContract(owner, TestERC20TokenArtifact, []);
    rewardToken = await deployContract(owner, TestERC20TokenArtifact, []);

    masterCW = (await deployContract(owner, MasterChefWooArtifact, [xWooToken.address, 10])) as MasterChefWoo;
    wooSR = (await deployContract(owner, WooSimpleRewarderArtifact, [rewardToken.address, weToken.address, masterCW.address, 20])) as WooSimpleRewarder;

    await xWooToken.mint(ownerAddr, TOKEN_100);
    await weToken.mint(ownerAddr, TOKEN_100);
    await rewardToken.mint(ownerAddr, TOKEN_100);
  })

  describe('MasterChefWoo', () => {
    beforeEach('Deploy MasterChefWoo', async () => {
      console.log('Deploy')
    })

    it('test MasterChefWoo', async () => {
      console.log('MasterChefWoo tests')
    })

    it('test WooSimpleRewarder', async () => {
      console.log('WooSimpleRewarder tests')
    })
  })
})
