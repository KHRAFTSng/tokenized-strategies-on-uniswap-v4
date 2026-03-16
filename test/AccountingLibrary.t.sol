// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {AccountingLibrary} from "src/libraries/AccountingLibrary.sol";

contract AccountingLibraryHarness {
    function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) external pure returns (uint256) {
        return AccountingLibrary.toSharesDown(assets, totalAssets, totalShares);
    }

    function toSharesUp(uint256 assets, uint256 totalAssets, uint256 totalShares) external pure returns (uint256) {
        return AccountingLibrary.toSharesUp(assets, totalAssets, totalShares);
    }

    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) external pure returns (uint256) {
        return AccountingLibrary.toAssetsDown(shares, totalAssets, totalShares);
    }

    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) external pure returns (uint256) {
        return AccountingLibrary.toAssetsUp(shares, totalAssets, totalShares);
    }

    function sharePrice(uint256 totalAssets, uint256 totalShares) external pure returns (uint256) {
        return AccountingLibrary.sharePrice(totalAssets, totalShares);
    }

    function applyBps(uint256 amount, uint256 bps) external pure returns (uint256) {
        return AccountingLibrary.applyBps(amount, bps);
    }
}

contract AccountingLibraryTest is Test {
    AccountingLibraryHarness internal harness;

    function setUp() public {
        harness = new AccountingLibraryHarness();
    }

    function test_ConversionsRoundAsExpected() external {
        uint256 sharesDown = harness.toSharesDown(100e18, 1_000e18, 1_000e18);
        uint256 sharesUp = harness.toSharesUp(100e18, 1_000e18, 1_000e18);

        uint256 assetsDown = harness.toAssetsDown(100e18, 1_000e18, 1_000e18);
        uint256 assetsUp = harness.toAssetsUp(100e18, 1_000e18, 1_000e18);

        assertEq(sharesDown, sharesUp);
        assertEq(assetsDown, assetsUp);
        assertEq(sharesDown, 100e18);
    }

    function test_SharePriceWhenNoSupply() external {
        assertEq(harness.sharePrice(0, 0), 1e18);
    }

    function test_SharePriceWhenSupplyExists() external {
        assertEq(harness.sharePrice(2_000e18, 1_000e18), 2e18);
    }

    function test_ApplyBps() external {
        assertEq(harness.applyBps(1_000e18, 100), 10e18);
    }

    function testFuzz_RoundTripBounds(uint96 assets, uint96 totalAssets, uint96 totalShares) external {
        uint256 a = bound(uint256(assets), 1, 1_000_000e18);
        uint256 ta = bound(uint256(totalAssets), 1, 1_000_000e18);
        uint256 ts = bound(uint256(totalShares), 1, 1_000_000e18);

        uint256 shares = harness.toSharesDown(a, ta, ts);
        uint256 roundTrip = harness.toAssetsDown(shares, ta, ts);
        assertLe(roundTrip, a);
    }
}
