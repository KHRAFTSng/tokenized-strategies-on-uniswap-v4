// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {StrategyVault} from "src/StrategyVault.sol";
import {LendingAdapterMock} from "src/mocks/LendingAdapterMock.sol";
import {SecondaryMarketMock} from "src/mocks/SecondaryMarketMock.sol";
import {YieldToken} from "src/YieldToken.sol";
import {MockStable} from "src/mocks/MockStable.sol";
import {IStrategyVaultViews} from "src/interfaces/IStrategyVaultViews.sol";

contract MockAsset2 is ERC20 {
    constructor() ERC20("Mock Asset", "mAST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract StrategyMocksTest is Test {
    MockAsset2 internal asset;
    StrategyVault internal vault;
    LendingAdapterMock internal lending;
    SecondaryMarketMock internal secondary;
    YieldToken internal yToken;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        asset = new MockAsset2();
        vault = new StrategyVault(owner, asset, "Yield Asset", "yAST", 100);
        yToken = vault.yieldToken();
        lending = new LendingAdapterMock(yToken, IStrategyVaultViews(address(vault)), 7_000);
        secondary = new SecondaryMarketMock(yToken, asset);

        asset.mint(owner, 1_000_000e18);
        asset.mint(alice, 1_000_000e18);
        asset.mint(bob, 1_000_000e18);

        vm.prank(owner);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(alice);
        vault.deposit(10_000e18, alice);
        vm.prank(bob);
        vault.deposit(10_000e18, bob);
    }

    function test_RevertWhen_LendingAmountsAreZero() external {
        vm.expectRevert(LendingAdapterMock.LendingAdapterMock__AmountZero.selector);
        lending.depositCollateral(0);

        vm.expectRevert(LendingAdapterMock.LendingAdapterMock__AmountZero.selector);
        lending.borrow(0);

        vm.expectRevert(LendingAdapterMock.LendingAdapterMock__AmountZero.selector);
        lending.repay(0);

        vm.expectRevert(LendingAdapterMock.LendingAdapterMock__AmountZero.selector);
        lending.withdrawCollateral(0);
    }

    function test_RevertWhen_LendingBorrowTooHigh() external {
        vm.startPrank(alice);
        yToken.approve(address(lending), type(uint256).max);
        lending.depositCollateral(1_000e18);
        vm.expectRevert();
        lending.borrow(1_000e18);
        vm.stopPrank();
    }

    function test_MaxBorrowAndRepayPartial() external {
        vm.startPrank(alice);
        yToken.approve(address(lending), type(uint256).max);
        lending.depositCollateral(1_000e18);

        uint256 maxB = lending.maxBorrow(alice);
        lending.borrow(maxB / 2);

        MockStable debtToken = lending.debtToken();
        debtToken.approve(address(lending), type(uint256).max);
        lending.repay(maxB / 4);

        assertGt(lending.userDebt(alice), 0);
        vm.stopPrank();
    }

    function test_RevertWhen_MockStableMintByNonMinter() external {
        MockStable stable = lending.debtToken();
        vm.prank(alice);
        vm.expectRevert(MockStable.MockStable__OnlyMinter.selector);
        stable.mint(alice, 1e18);
    }

    function test_RevertWhen_SecondaryLiquidityOrSwapInvalid() external {
        vm.expectRevert(SecondaryMarketMock.SecondaryMarketMock__AmountZero.selector);
        secondary.addLiquidity(0, 1);

        vm.prank(alice);
        yToken.approve(address(secondary), type(uint256).max);
        vm.prank(alice);
        asset.approve(address(secondary), type(uint256).max);

        vm.prank(alice);
        secondary.addLiquidity(1_000e18, 1_000e18);

        vm.expectRevert(SecondaryMarketMock.SecondaryMarketMock__AmountZero.selector);
        secondary.swapExactIn(address(yToken), 0, 0);

        vm.expectRevert(SecondaryMarketMock.SecondaryMarketMock__InvalidToken.selector);
        secondary.swapExactIn(address(0xdead), 1e18, 0);

        vm.prank(alice);
        vm.expectRevert();
        secondary.swapExactIn(address(yToken), 1e18, type(uint256).max);
    }

    function test_SecondarySwapFromUnderlyingSide() external {
        vm.prank(alice);
        yToken.approve(address(secondary), type(uint256).max);
        vm.prank(alice);
        asset.approve(address(secondary), type(uint256).max);
        vm.prank(alice);
        secondary.addLiquidity(1_000e18, 1_000e18);

        vm.prank(bob);
        asset.approve(address(secondary), type(uint256).max);
        vm.prank(bob);
        uint256 out = secondary.swapExactIn(address(asset), 10e18, 1);

        assertGt(out, 0);
    }
}
