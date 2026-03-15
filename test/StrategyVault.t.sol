// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {StrategyVault} from "src/StrategyVault.sol";
import {YieldToken} from "src/YieldToken.sol";

contract MockAsset is ERC20 {
    constructor() ERC20("Mock Asset", "mAST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract StrategyVaultTest is Test {
    StrategyVault internal vault;
    MockAsset internal asset;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        asset = new MockAsset();
        vault = new StrategyVault(owner, asset, "Yield Asset", "yAST", 100);

        asset.mint(owner, 10_000_000e18);
        asset.mint(alice, 10_000_000e18);
        asset.mint(bob, 10_000_000e18);
        asset.mint(attacker, 10_000_000e18);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(owner);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(attacker);
        asset.approve(address(vault), type(uint256).max);
    }

    function test_DepositRedeem() external {
        vm.startPrank(alice);
        uint256 shares = vault.deposit(1_000e18, alice);
        uint256 assets = vault.redeem(shares, alice);
        vm.stopPrank();

        assertEq(assets, 1_000e18);
        assertEq(vault.totalManagedAssets(), 0);
        assertEq(vault.sharePrice(), 1e18);
    }

    function test_RevertWhen_DepositZero() external {
        vm.prank(alice);
        vm.expectRevert(StrategyVault.StrategyVault__AmountZero.selector);
        vault.deposit(0, alice);
    }

    function test_DonationAttackDoesNotAffectShareMinting() external {
        vm.prank(alice);
        uint256 firstShares = vault.deposit(1_000e18, alice);

        vm.prank(attacker);
        asset.transfer(address(vault), 50_000e18);

        uint256 priceBefore = vault.sharePrice();

        vm.prank(bob);
        uint256 secondShares = vault.deposit(1_000e18, bob);

        uint256 priceAfter = vault.sharePrice();

        assertEq(firstShares, secondShares);
        assertEq(priceBefore, priceAfter);
        assertEq(vault.totalManagedAssets(), 2_000e18);
        assertEq(asset.balanceOf(address(vault)), 52_000e18);
    }

    function test_DustDepositBoundary() external {
        vm.prank(alice);
        uint256 shares = vault.deposit(1, alice);
        assertGt(shares, 0);
    }

    function test_RedeemWhenLiquidityConstrained() external {
        vm.prank(alice);
        uint256 shares = vault.deposit(1_000e18, alice);

        vm.prank(owner);
        vault.setLockedLiquidityAssets(900e18);

        vm.prank(alice);
        vm.expectRevert(StrategyVault.StrategyVault__InsufficientLiquidAssets.selector);
        vault.redeem(shares, alice);
    }

    function test_ReportAmmFeeYieldIncreasesSharePrice() external {
        vm.prank(alice);
        vault.deposit(1_000e18, alice);

        uint256 priceBefore = vault.sharePrice();

        vm.prank(owner);
        vault.reportAmmFeeYield(100e18);

        uint256 priceAfter = vault.sharePrice();
        assertGt(priceAfter, priceBefore);
        assertEq(vault.totalManagedAssets(), 1_100e18);
    }

    function test_DeterministicYieldFlow() external {
        vm.prank(owner);
        vault.setHook(owner);

        vm.prank(alice);
        vault.deposit(1_000e18, alice);

        vm.prank(owner);
        vault.fundRebateReserve(200e18);

        vm.prank(owner);
        vault.notifySwapVolume(bytes32(uint256(1)), 5_000e18, alice);

        uint256 pending = vault.pendingStrategyYield();
        assertEq(pending, 50e18);

        uint256 priceBefore = vault.sharePrice();
        uint256 applied = vault.applyDeterministicYield(type(uint256).max);
        uint256 priceAfter = vault.sharePrice();

        assertEq(applied, 50e18);
        assertGt(priceAfter, priceBefore);
    }

    function test_RevertWhen_UnauthorizedMintBurn() external {
        YieldToken token = vault.yieldToken();

        vm.prank(alice);
        vm.expectRevert(YieldToken.YieldToken__OnlyVault.selector);
        token.mint(alice, 1e18);

        vm.prank(alice);
        vm.expectRevert(YieldToken.YieldToken__OnlyVault.selector);
        token.burn(alice, 1e18);
    }

    function testFuzz_DepositRedeemRoundTrip(uint96 assetsIn) external {
        assetsIn = uint96(bound(uint256(assetsIn), 1e6, 1_000_000e18));

        vm.startPrank(alice);
        uint256 shares = vault.deposit(assetsIn, alice);
        uint256 assetsOut = vault.redeem(shares, alice);
        vm.stopPrank();

        assertLe(assetsOut, assetsIn);
        assertApproxEqAbs(assetsIn - assetsOut, 0, 1);
    }

    function testFuzz_AccountingConsistency(uint96 a0, uint96 a1, uint96 feeYield) external {
        uint256 aliceAssets = bound(uint256(a0), 1e6, 1_000_000e18);
        uint256 bobAssets = bound(uint256(a1), 1e6, 1_000_000e18);
        uint256 feeAssets = bound(uint256(feeYield), 1e6, 1_000_000e18);

        vm.prank(alice);
        vault.deposit(aliceAssets, alice);

        vm.prank(bob);
        vault.deposit(bobAssets, bob);

        vm.prank(owner);
        vault.reportAmmFeeYield(feeAssets);

        uint256 expectedAssets = aliceAssets + bobAssets + feeAssets;
        uint256 redeemable = vault.previewRedeem(vault.yieldToken().totalSupply());

        assertEq(vault.totalManagedAssets(), expectedAssets);
        assertLe(redeemable, expectedAssets);
        assertApproxEqAbs(redeemable, expectedAssets, 1e18);
    }
}
