import { expect } from "chai";
import { BigNumber, utils } from "ethers";
import { ethers } from "hardhat";
import { deployContract } from "ethereum-waffle";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { WooracleV2ZKSync, WooracleV2, TestChainLink, TestQuoteChainLink } from "../../typechain";
import WooracleV2ZKSyncArtifact from "../../artifacts/contracts/wooracle/WooracleV2ZKSync.sol/WooracleV2ZKSync.json";
import TestChainLinkArtifact from "../../artifacts/contracts/test/TestChainLink.sol/TestChainLink.json";
import TestQuoteChainLinkArtifact from "../../artifacts/contracts/test/TestChainLink.sol/TestQuoteChainLink.json";
import TestERC20TokenArtifact from "../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json";


const BN_1E18 = BigNumber.from(10).pow(18);
const BN_2E18 = BN_1E18.mul(2);
const BN_1E8 = BigNumber.from(10).pow(8);

const BN_1E16 = BigNumber.from(10).pow(18);
const BN_2E16 = BN_1E16.mul(2);
const ZERO = 0;

async function getCurrentBlockTimestamp() {
    const blockNum = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNum);
    return block.timestamp;
}

async function checkWooracleTimestamp(wooracleV2Zip: WooracleV2) {
    const currentBlockTimestamp = await getCurrentBlockTimestamp();
    expect(await wooracleV2Zip.timestamp()).to.gte(currentBlockTimestamp);
}

describe("WooracleV2ZkSync", () => {
    let owner: SignerWithAddress;

    let wethToken: Contract;
    let wooToken: Contract;

    let wooracleV2Zip: WooracleV2ZKSyncArtifact;
    let chainlinkOne: TestChainLink;
    let chainlinkTwo: TestQuoteChainLink;

    beforeEach(async () => {
        const signers = await ethers.getSigners();
        owner = signers[0];

        wethToken = await deployContract(owner, TestERC20TokenArtifact, []);
        wooToken = await deployContract(owner, TestERC20TokenArtifact, []);

        wooracleV2Zip = (await deployContract(owner, WooracleV2ZKSyncArtifact, [])) as WooracleV2ZKSync;

        chainlinkOne = (await deployContract(owner, TestChainLinkArtifact, [])) as TestChainLink;
        chainlinkTwo = (await deployContract(owner, TestQuoteChainLinkArtifact, [])) as TestQuoteChainLink;

        await wooracleV2Zip.setBase(5, wethToken.address);
        await wooracleV2Zip.setBase(6, wooToken.address);
    });

    it("Init states", async () => {
        expect(await wooracleV2Zip.owner()).to.eq(owner.address);
        expect(await wooracleV2Zip.getBase(0)).to.eq("0x82aF49447D8a07e3bd95BD0d56f35241523fBab1");
        expect(await wooracleV2Zip.getBase(5)).to.eq(wethToken.address);
        expect(await wooracleV2Zip.getBase(6)).to.eq(wooToken.address);

        // console.log(await wooracleV2Zip.state(wooToken.address));
        // console.log(await wooracleV2Zip.price(wethToken.address));

        const wooState = await wooracleV2Zip.state(wooToken.address);
        expect(wooState.price).to.be.eq(0);
        expect(wooState.spread).to.be.eq(0);
        expect(wooState.coeff).to.be.eq(0);
        expect(wooState.woFeasible).to.be.eq(false);

        const price = await wooracleV2Zip.price(wethToken.address);
        expect(price.priceOut).to.be.eq(0);
        expect(price.feasible).to.be.eq(false);
    });

    it("Post prices", async () => {
        await owner.sendTransaction({
            to: wooracleV2Zip.address,
            data: _encode_woo_price_with_timestamp()
        })

        console.log(await wooracleV2Zip.state(wooToken.address));
        const p_ret = await wooracleV2Zip.price(wooToken.address)
        console.log("price ", p_ret.priceOut.toString(), p_ret.feasible);

        const ts = await wooracleV2Zip.timestamp();
        console.log("timestamp ", ts.toString(), p_ret.feasible);

        expect(ts).to.be.eq(BigNumber.from("1111111111"));
        expect(p_ret.priceOut).to.be.eq(0); // timestamp out of range
        expect(p_ret.feasible).to.be.eq(false);

        const wooInfo = await wooracleV2Zip.infos(wooToken.address);
        console.log("TokenInfo price: ", wooInfo.price.toString());
        expect(wooInfo.price).to.be.eq(BigNumber.from("22970000"));
    });

    function _encode_woo_price_with_timestamp() {
        /*
        op = 0
        len = 1
        (base, p)
        */
        let _calldata = new Uint8Array(1 + 5 + 4);

        // 0xC0 : 11000000
        // 0x3F : 00111111
        _calldata[0] = (2 << 6) + (1 & 0x3F);
        _calldata[1] = 6; // woo token

        // price: 0.22970
        // 22970000 (decimal = 8)
        let price = BigNumber.from(2297).shl(5).add(4);
        // console.log("woo price: ", price.toString());
        _calldata[2] = price.shr(24).mod(256).toNumber();
        _calldata[3] = price.shr(16).mod(256).toNumber();
        _calldata[4] = price.shr(8).mod(256).toNumber();
        _calldata[5] = price.shr(0).mod(256).toNumber();

        console.log("test woo calldata: ", _calldata);

        // 0x423A35C7 = 1111111111 (dec)
        _calldata[6] = 0x42;
        _calldata[7] = 0x3A;
        _calldata[8] = 0x35;
        _calldata[9] = 0xC7;

        return _calldata;
    }

    function _encode_woo_price() {
        /*
        op = 0
        len = 1
        (base, p)
        */
        let _calldata = new Uint8Array(1 + 5);

        // 0xC0 : 11000000
        // 0x3F : 00111111
        _calldata[0] = (2 << 6) + (1 & 0x3F);
        _calldata[1] = 6; // woo token

        // price: 0.22970
        // 22970000 (decimal = 8)
        let price = BigNumber.from(2297).shl(5).add(4);
        // console.log("woo price: ", price.toString());
        _calldata[2] = price.shr(24).mod(256).toNumber();
        _calldata[3] = price.shr(16).mod(256).toNumber();
        _calldata[4] = price.shr(8).mod(256).toNumber();
        _calldata[5] = price.shr(0).mod(256).toNumber();

        console.log("test woo calldata: ", _calldata);

        return _calldata;
    }

    async function _get_id(base:String) {
        for (let i = 0; i < 5 + 2; ++i) {
            if (base == await wooracleV2Zip.getBase(i))
                return i;
        }
        return 0;
    }
});
