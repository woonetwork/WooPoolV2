// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseSetup} from "@chimera/BaseSetup.sol";

import "../../contracts/WooPPV2.sol";
// import "../../contracts/wooracle/WooracleV2_2.sol";

import "../../contracts/WooRouterV2.sol";
import "../mocks/TestChainLink.sol";
import {TestChainLink2} from "../mocks/TestChainLink2.sol";
import {TestChainLink3} from "../mocks/TestChainLink3.sol";
import "test/mocks/UsdtMock.sol";
import "test/mocks/ERC20Mock.sol";
import "test/mocks/WETHMock.sol";
import "test/mocks/MockOracle.sol";
import "forge-std/console.sol";
import {vm} from "@chimera/Hevm.sol";

abstract contract Setup is BaseSetup {
    UsdtMock quoteToken;
    ERC20Mock baseToken1;
    ERC20Mock baseToken2;
    ERC20Mock baseToken3;
    WETHMock weth;

    WooPPV2 pool;
    WooRouterV2 router;
    // WooracleV2_2 oracle;
    MockOracle oracle;
    TestQuoteChainLink quoteChainlinkOracle;
    TestChainLink chainlinkOracle;
    TestChainLink2 chainlinkOracle2;
    TestChainLink3 chainlinkOracle3;

    // owner is the same for all system contracts
    address owner;
    address testSender;
    // chainlink oracle, might need to use a mock implementation for this
    // address clOracle = address(0x5678);

    // used for setting tokenInfo
    // @audit using one of the values from deployed for all
    uint16 feeRate = 25;
    // uint128 maxGamma = 0.0005 * 1e18;
    uint128 maxGamma = 1e6 * 1e18;
    uint128 maxNotionalSwap = 500_000 * 1e6;

    uint256 baseMintAmount = 1e5 * 1e18;
    uint256 quoteMintAmount = 1000 * 1e5 * 1e6;
    address[4] internal tokensInSystem;

    // initial token pirices
    uint128 baseToken1StartPrice = 800e8;
    uint128 baseToken2StartPrice = 700e8;
    uint128 baseToken3StartPrice = 600e8;

    // CryticTester is the user of the pool that calls it through Router
    function setup() internal virtual override {
        quoteToken = new UsdtMock();
        baseToken1 = new ERC20Mock("Base Mock 1", "BM1");
        baseToken2 = new ERC20Mock("Base Mock 2", "BM2");
        baseToken3 = new ERC20Mock("Base Mock 3", "BM3");
        weth = new WETHMock();

        testSender = address(0x0000000000000000000000000000000000010000);
        owner = address(0x1234);

        // @audit excluding weth for now because minting doesn't work
        // used for bounding input values to only relevant tokens
        tokensInSystem = [address(quoteToken), address(baseToken1), address(baseToken2), address(baseToken3)];

        // deploy system contracts
        _deploySystemContracts();

        // mints tokens to this address and owner
        _mintAndApproveTokens(owner);

        // owner has admin role and adds liquidity to the pool
        _setPoolTokenInfoAndDeposit();
    }

    function _deploySystemContracts() internal {
        address deployer = address(0x00a329c0648769A73afAc7F9381E08FB43dBEA72);

        pool = new WooPPV2(address(quoteToken));
        router = new WooRouterV2(address(weth), address(pool));
        // oracle = new WooracleV2_2();
        oracle = new MockOracle();

        // transfer ownership to owner address needs to be pranked to deployer for Echidna to compile
        // vm.prank(deployer);
        pool.transferOwnership(owner);
        // vm.prank(deployer);
        router.transferOwnership(owner);
        // vm.prank(deployer);
        oracle.transferOwnership(owner);

        vm.prank(owner);
        oracle.setStaleDuration(1e8);

        // deploy chainlink test oracles
        vm.prank(owner);
        quoteChainlinkOracle = new TestQuoteChainLink();
        vm.prank(owner);
        chainlinkOracle = new TestChainLink();
        vm.prank(owner);
        chainlinkOracle2 = new TestChainLink2();
        vm.prank(owner);
        chainlinkOracle3 = new TestChainLink3();

        // set the quote token in the oracle contract
        vm.prank(owner);
        oracle.setQuoteToken(address(quoteToken), address(quoteChainlinkOracle));

        // set chainlink oracles for base tokens
        vm.prank(owner);
        oracle.setCLOracle(address(baseToken1), address(chainlinkOracle), true); // setting baseToken1 to use same chainlink oracle as quoteToken
        vm.prank(owner);
        oracle.setCLOracle(address(baseToken2), address(chainlinkOracle2), true); // setting baseToken2 to use chainlinkOracle2
        vm.prank(owner);
        oracle.setCLOracle(address(baseToken3), address(chainlinkOracle3), true); // setting baseToken2 to use chainlinkOracle2

        // make pool an admin on oracle so it can update price
        vm.prank(owner);
        oracle.setAdmin(address(pool), true);

        // make CryticTester an admin on oracle so it can change the quoteToken
        vm.prank(owner);
        oracle.setAdmin(address(this), true);

        vm.prank(owner);
        oracle.setGuardian(address(this), true);

        // initialize pool with owner receiving fees
        vm.prank(owner);
        pool.init(address(oracle), owner);

        // make CryticTester an admin on pool so it can add/remove liquidity
        vm.prank(owner);
        pool.setAdmin(address(this), true);

        vm.prank(owner);
        pool.setAdmin(testSender, true);

        // setting the initial price state of the tokens for the oracle
        vm.prank(owner);
        oracle.postState(address(quoteToken), 1e6, .001 ether, .000000001 ether);
        vm.prank(owner);
        oracle.postState(address(baseToken1), baseToken1StartPrice, .001 ether, .000000001 ether);
        oracle.setRange(address(baseToken1), baseToken1StartPrice * 5 / 10, baseToken1StartPrice * 15 / 10);
        vm.prank(owner);
        oracle.postState(address(baseToken2), baseToken2StartPrice, .001 ether, .000000001 ether);
        oracle.setRange(address(baseToken2), baseToken2StartPrice * 5 / 10, baseToken2StartPrice * 15 / 10);
        vm.prank(owner);
        oracle.postState(address(baseToken3), baseToken3StartPrice, .001 ether, .000000001 ether);
        oracle.setRange(address(baseToken3), baseToken3StartPrice * 5 / 10, baseToken3StartPrice * 15 / 10);
    }

    // approves Router for tokens, not WooPPV2
    function _mintAndApproveTokens(address _owner) internal {
        // @audit baseToken3 is minted but not deposited so it can be used for testing
        // mint tokens to this address
        // quoteToken.mint(address(this), _mintAmount);
        // baseToken1.mint(address(this), _mintAmount);
        // baseToken2.mint(address(this), _mintAmount);
        // baseToken3.mint(address(this), _mintAmount);
        // deployer (0x30000) and senders are preloaded with 4294967295 ether
        // vm.prank(address(0x30000));
        // address(weth).call{value: 10 ether}(abi.encodeWithSignature("deposit()"));
        // transfer to CryticTester
        // vm.prank(address(0x30000));
        // weth.transfer(address(this), 10 ether);

        quoteToken.mint(testSender, quoteMintAmount);
        baseToken1.mint(testSender, baseMintAmount);
        baseToken2.mint(testSender, baseMintAmount);
        baseToken3.mint(testSender, baseMintAmount);

        // approve test sender to spend CryticTester's tokens
        vm.prank(testSender);
        quoteToken.approve(testSender, type(uint256).max);
        vm.prank(testSender);
        baseToken1.approve(testSender, type(uint256).max);
        vm.prank(testSender);
        baseToken2.approve(testSender, type(uint256).max);
        vm.prank(testSender);
        baseToken3.approve(testSender, type(uint256).max);
        
        // approve the router to spend CryticTester's tokens
        quoteToken.approve(address(router), type(uint256).max);
        baseToken1.approve(address(router), type(uint256).max);
        baseToken2.approve(address(router), type(uint256).max);
        baseToken3.approve(address(router), type(uint256).max);
        // approve the pool to spend CryticTester's tokens
        quoteToken.approve(address(pool), type(uint256).max);
        baseToken1.approve(address(pool), type(uint256).max);
        baseToken2.approve(address(pool), type(uint256).max);
        baseToken3.approve(address(pool), type(uint256).max);

        // mint tokens to owner address
        quoteToken.mint(_owner, quoteMintAmount);
        baseToken1.mint(_owner, baseMintAmount);
        baseToken2.mint(_owner, baseMintAmount);
        baseToken3.mint(_owner, baseMintAmount);

        // vm.prank(address(0x30000));
        // address(weth).call{value: 10 ether}(abi.encodeWithSignature("deposit()"));
        // transfer to owner
        // vm.prank(address(0x30000));
        // weth.transfer(_owner, 10 ether);

        // approve Pool to use them
        vm.prank(owner);
        quoteToken.approve(address(pool), type(uint256).max);
        vm.prank(owner);
        baseToken1.approve(address(pool), type(uint256).max);
        vm.prank(owner);
        baseToken2.approve(address(pool), type(uint256).max);
        vm.prank(owner);
        baseToken3.approve(address(pool), type(uint256).max);
    }

    function _setPoolTokenInfoAndDeposit() internal {
        // set tokenInfo for tokens in the pool
        vm.prank(owner);
        pool.setTokenInfo(address(quoteToken), feeRate, maxGamma, maxNotionalSwap);
        vm.prank(owner);
        pool.setTokenInfo(address(baseToken1), feeRate, maxGamma, maxNotionalSwap);
        vm.prank(owner);
        pool.setTokenInfo(address(baseToken2), feeRate, maxGamma, maxNotionalSwap);
        vm.prank(owner);
        pool.setTokenInfo(address(baseToken3), feeRate, maxGamma, maxNotionalSwap);

        // add liquidity to pool
        // @audit owner doesn't deposit baseToken3 so fuzzer can call transfer for them
        vm.prank(owner);
        pool.deposit(address(quoteToken), quoteMintAmount);
        vm.prank(owner);
        pool.deposit(address(baseToken1), baseMintAmount);
        vm.prank(owner);
        pool.deposit(address(baseToken2), baseMintAmount);
        vm.prank(owner);
        pool.deposit(address(baseToken3), baseMintAmount);
    }
}
