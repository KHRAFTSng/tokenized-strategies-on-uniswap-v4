// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import {EasyPosm} from "test/utils/libraries/EasyPosm.sol";
import {BaseTest} from "test/utils/BaseTest.sol";

import {StrategyHook} from "src/StrategyHook.sol";
import {StrategyVault} from "src/StrategyVault.sol";
import {LendingAdapterMock} from "src/mocks/LendingAdapterMock.sol";
import {SecondaryMarketMock} from "src/mocks/SecondaryMarketMock.sol";
import {IStrategyVaultViews} from "src/interfaces/IStrategyVaultViews.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StrategyIntegrationTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    StrategyHook internal hook;
    StrategyVault internal vault;
    LendingAdapterMock internal lending;
    SecondaryMarketMock internal secondaryMarket;

    Currency internal currency0;
    Currency internal currency1;
    PoolKey internal poolKey;
    PoolId internal poolId;

    MockERC20 internal token0;
    MockERC20 internal token1;

    function setUp() public {
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();
        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        vault = new StrategyVault(address(this), IERC20(address(token0)), "Yield Token", "yTOKEN", 100);

        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (uint160(0x9999) << 144)
        );
        bytes memory constructorArgs = abi.encode(poolManager, address(this), vault);
        deployCodeTo("StrategyHook.sol:StrategyHook", constructorArgs, flags);
        hook = StrategyHook(flags);

        vault.setHook(address(hook));

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);
        hook.setPoolPolicy(poolKey, type(uint128).max, false, true);

        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);
        uint128 liquidityAmount = 500e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );

        token0.transfer(alice, 2_000e18);
        token0.transfer(bob, 2_000e18);
        vm.prank(alice);
        token0.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token0.approve(address(vault), type(uint256).max);

        token0.approve(address(vault), type(uint256).max);
        lending = new LendingAdapterMock(vault.yieldToken(), IStrategyVaultViews(address(vault)), 7_000);
        secondaryMarket = new SecondaryMarketMock(vault.yieldToken(), IERC20(address(token0)));
    }

    function test_EndToEndYieldLifecycle() external {
        vm.startPrank(alice);
        uint256 mintedShares = vault.deposit(1_000e18, alice);
        vm.stopPrank();

        uint256 sharePriceBefore = vault.sharePrice();
        emit log_named_uint("deposit_amount", 1_000e18);
        emit log_named_uint("shares_minted", mintedShares);
        emit log_named_uint("share_price_before", sharePriceBefore);

        vault.fundRebateReserve(100e18);

        swapRouter.swapExactTokensForTokens({
            amountIn: 200e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        vault.reportAmmFeeYield(50e18);
        vault.applyDeterministicYield(type(uint256).max);

        uint256 sharePriceAfter = vault.sharePrice();
        assertGt(sharePriceAfter, sharePriceBefore);
        emit log_named_uint("share_price_after", sharePriceAfter);

        vm.startPrank(alice);
        uint256 redeemedAssets = vault.redeem(mintedShares, alice);
        vm.stopPrank();

        emit log_named_uint("redeem_amount", redeemedAssets);
        assertGt(redeemedAssets, 1_000e18);
    }

    function test_SecondaryMarketPoolTrade() external {
        vm.startPrank(alice);
        uint256 mintedShares = vault.deposit(1_000e18, alice);
        vault.yieldToken().approve(address(secondaryMarket), type(uint256).max);
        token0.approve(address(secondaryMarket), type(uint256).max);
        secondaryMarket.addLiquidity(mintedShares / 2, 500e18);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 bobShares = vault.deposit(200e18, bob);
        vault.yieldToken().approve(address(secondaryMarket), type(uint256).max);
        uint256 out = secondaryMarket.swapExactIn(address(vault.yieldToken()), bobShares / 2, 1);
        vm.stopPrank();

        emit log_string("secondary pool trade executed");
        emit log_named_uint("secondary_swap_output", out);

        assertGt(out, 0);
    }

    function test_OptionalLendingAdapterFlow() external {
        vm.startPrank(alice);
        uint256 mintedShares = vault.deposit(500e18, alice);
        vault.yieldToken().approve(address(lending), type(uint256).max);

        lending.depositCollateral(mintedShares);
        lending.borrow(200e18);
        uint256 debt = lending.userDebt(alice);
        assertEq(debt, 200e18);

        lending.debtToken().approve(address(lending), type(uint256).max);
        lending.repay(200e18);
        lending.withdrawCollateral(mintedShares);
        vm.stopPrank();

        assertEq(lending.userDebt(alice), 0);
        assertEq(lending.collateralShares(alice), 0);
    }
}
