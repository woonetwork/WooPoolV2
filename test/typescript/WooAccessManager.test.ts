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

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { WooAccessManager } from "../../typechain";
import { ethers } from "hardhat";
import { deployContract, solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import WooAccessManagerArtifact from "../../artifacts/contracts/WooAccessManager.sol/WooAccessManager.json";

use(solidity);

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("WooAccessManager Accuracy & Access Control & Require Check", () => {
  let owner: SignerWithAddress;
  let user: SignerWithAddress;
  let feeAdmin: SignerWithAddress;
  let secondFeeAdmin: SignerWithAddress;
  let vaultAdmin: SignerWithAddress;
  let rebateAdmin: SignerWithAddress;
  let secondRebateAdmin: SignerWithAddress;
  let vault: SignerWithAddress;

  let wooAccessManager: WooAccessManager;

  let onlyOwnerRevertedMessage: string;
  let feeAdminZeroAddressMessage: string;
  let vaultAdminZeroAddressMessage: string;
  let rebateAdminZeroAddressMessage: string;
  let zeroFeeVaultZeroAddressMessage: string;
  let whenNotPausedRevertedMessage: string;

  before(async () => {
    [
      owner,
      user,
      feeAdmin,
      secondFeeAdmin,
      vaultAdmin,
      rebateAdmin,
      secondRebateAdmin,
      vault,
    ] = await ethers.getSigners();

    wooAccessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager;

    onlyOwnerRevertedMessage = "Ownable: caller is not the owner";
    feeAdminZeroAddressMessage = "WooAccessManager: feeAdmin_ZERO_ADDR";
    vaultAdminZeroAddressMessage = "WooAccessManager: vaultAdmin_ZERO_ADDR";
    rebateAdminZeroAddressMessage = "WooAccessManager: rebateAdmin_ZERO_ADDR";
    zeroFeeVaultZeroAddressMessage = "WooAccessManager: vault_ZERO_ADDR";
    whenNotPausedRevertedMessage = "Pausable: paused";
  });

  it("Check state variables after contract initialized", async () => {
    expect(await wooAccessManager.owner()).to.eq(owner.address);
    expect(await wooAccessManager.isFeeAdmin(feeAdmin.address)).to.eq(false);
    expect(await wooAccessManager.isVaultAdmin(vaultAdmin.address)).to.eq(false);
    expect(await wooAccessManager.isRebateAdmin(rebateAdmin.address)).to.eq(false);
    expect(await wooAccessManager.isZeroFeeVault(vault.address)).to.eq(false);
  });

  it("Only owner able to setFeeAdmin", async () => {
    expect(await wooAccessManager.isFeeAdmin(feeAdmin.address)).to.eq(false);
    await expect(wooAccessManager.connect(user).setFeeAdmin(feeAdmin.address, true)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    );

    await expect(wooAccessManager.connect(owner).setFeeAdmin(feeAdmin.address, true))
      .to.emit(wooAccessManager, "FeeAdminUpdated")
      .withArgs(feeAdmin.address, true);
    expect(await wooAccessManager.isFeeAdmin(feeAdmin.address)).to.eq(true);
  });

  it("SetFeeAdmin from zero address will be reverted", async () => {
    expect(await wooAccessManager.isFeeAdmin(ZERO_ADDRESS)).to.eq(false);
    await expect(wooAccessManager.connect(owner).setFeeAdmin(ZERO_ADDRESS, true)).to.be.revertedWith(
      feeAdminZeroAddressMessage
    );
    expect(await wooAccessManager.isFeeAdmin(ZERO_ADDRESS)).to.eq(false);
  });

  it("Only owner able to setVaultAdmin", async () => {
    expect(await wooAccessManager.isVaultAdmin(vaultAdmin.address)).to.eq(false);
    await expect(wooAccessManager.connect(user).setVaultAdmin(vaultAdmin.address, true)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    );

    await expect(wooAccessManager.connect(owner).setVaultAdmin(vaultAdmin.address, true))
      .to.emit(wooAccessManager, "VaultAdminUpdated")
      .withArgs(vaultAdmin.address, true);
    expect(await wooAccessManager.isVaultAdmin(vaultAdmin.address)).to.eq(true);
  });

  it("SetVaultAdmin from zero address will be reverted", async () => {
    expect(await wooAccessManager.isVaultAdmin(ZERO_ADDRESS)).to.eq(false);
    await expect(wooAccessManager.connect(owner).setVaultAdmin(ZERO_ADDRESS, true)).to.be.revertedWith(
      vaultAdminZeroAddressMessage
    );
    expect(await wooAccessManager.isVaultAdmin(ZERO_ADDRESS)).to.eq(false);
  });

  it("Only owner able to setRebateAdmin", async () => {
    expect(await wooAccessManager.isRebateAdmin(rebateAdmin.address)).to.eq(false);
    await expect(wooAccessManager.connect(user).setRebateAdmin(rebateAdmin.address, true)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    );

    await expect(wooAccessManager.connect(owner).setRebateAdmin(rebateAdmin.address, true))
      .to.emit(wooAccessManager, "RebateAdminUpdated")
      .withArgs(rebateAdmin.address, true);
    expect(await wooAccessManager.isRebateAdmin(rebateAdmin.address)).to.eq(true);
  });

  it("SetRebateAdmin from zero address will be reverted", async () => {
    expect(await wooAccessManager.isRebateAdmin(ZERO_ADDRESS)).to.eq(false);
    await expect(wooAccessManager.connect(owner).setRebateAdmin(ZERO_ADDRESS, true)).to.be.revertedWith(
      rebateAdminZeroAddressMessage
    );
    expect(await wooAccessManager.isRebateAdmin(ZERO_ADDRESS)).to.eq(false);
  });

  it("Only owner able to setZeroFeeVault", async () => {
    expect(await wooAccessManager.isZeroFeeVault(vault.address)).to.eq(false);
    await expect(wooAccessManager.connect(user).setZeroFeeVault(vault.address, true)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    );

    await expect(wooAccessManager.connect(owner).setZeroFeeVault(vault.address, true))
      .to.emit(wooAccessManager, "ZeroFeeVaultUpdated")
      .withArgs(vault.address, true);
    expect(await wooAccessManager.isZeroFeeVault(vault.address)).to.eq(true);
  });

  it("SetZeroFeeVault from zero address will be reverted", async () => {
    expect(await wooAccessManager.isZeroFeeVault(ZERO_ADDRESS)).to.eq(false);
    await expect(wooAccessManager.connect(owner).setZeroFeeVault(ZERO_ADDRESS, true)).to.be.revertedWith(
      zeroFeeVaultZeroAddressMessage
    );
    expect(await wooAccessManager.isZeroFeeVault(ZERO_ADDRESS)).to.eq(false);
  });

  it("Only owner able to pause", async () => {
    // pre check
    if (await wooAccessManager.isRebateAdmin(rebateAdmin.address)) {
      await wooAccessManager.connect(owner).setRebateAdmin(rebateAdmin.address, false);
    }
    expect(await wooAccessManager.isRebateAdmin(rebateAdmin.address)).to.eq(false);

    if (await wooAccessManager.isZeroFeeVault(vault.address)) {
      await wooAccessManager.connect(owner).setZeroFeeVault(vault.address, false);
    }
    expect(await wooAccessManager.isZeroFeeVault(vault.address)).to.eq(false);

    await expect(wooAccessManager.connect(user).pause()).to.be.revertedWith(onlyOwnerRevertedMessage);
    await wooAccessManager.connect(owner).pause();

    await expect(wooAccessManager.setRebateAdmin(rebateAdmin.address, true)).to.be.revertedWith(
      whenNotPausedRevertedMessage
    );
    await expect(wooAccessManager.setZeroFeeVault(vault.address, true)).to.be.revertedWith(
      whenNotPausedRevertedMessage
    );
  });

  it("Only owner able to unpause", async () => {
    expect(await wooAccessManager.paused()).to.eq(true);
    await expect(wooAccessManager.connect(user).unpause()).to.be.revertedWith(onlyOwnerRevertedMessage);
    await wooAccessManager.connect(owner).unpause();

    expect(await wooAccessManager.paused()).to.eq(false);
    await wooAccessManager.setRebateAdmin(rebateAdmin.address, true);
    await wooAccessManager.setZeroFeeVault(vault.address, true);
    expect(await wooAccessManager.isRebateAdmin(rebateAdmin.address)).to.eq(true);
    expect(await wooAccessManager.isZeroFeeVault(vault.address)).to.eq(true);
  });
});
