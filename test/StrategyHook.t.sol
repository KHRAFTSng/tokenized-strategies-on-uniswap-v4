// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

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
import {IStrategyVaultHookReceiver} from "src/interfaces/IStrategyVaultHookReceiver.sol";
import {StrategyHook} from "src/StrategyHook.sol";

contract MockVaultReceiver is IStrategyVaultHookReceiver {
    bytes32 public lastPoolId;
    uint256 public lastNotional;
    address public lastSender;

    function notifySwapVolume(bytes32 poolId, uint256 notionalAmount, address sender) external {
        lastPoolId = poolId;
        lastNotional = notionalAmount;
        lastSender = sender;
    }
}

contract StrategyHookTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency internal currency0;
    Currency internal currency1;

    PoolKey internal poolKey;
    PoolId internal poolId;

    StrategyHook internal hook;
    MockVaultReceiver internal receiver;

    uint256 internal tokenId;

    function setUp() public {
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        receiver = new MockVaultReceiver();

        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (uint160(0x8888) << 144)
        );

        bytes memory constructorArgs = abi.encode(poolManager, address(this), receiver);
        deployCodeTo("StrategyHook.sol:StrategyHook", constructorArgs, flags);
        hook = StrategyHook(flags);

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        hook.setPoolPolicy(poolKey, type(uint128).max, false, true);

        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);
        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
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

        assertGt(tokenId, 0);
    }

    function test_SwapAppliesPolicyAndNotifiesVault() external {
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        assertEq(hook.observedNotionalByPool(poolId), 1e18);
        assertEq(receiver.lastPoolId(), PoolId.unwrap(poolId));
        assertEq(receiver.lastNotional(), 1e18);
        assertEq(receiver.lastSender(), address(swapRouter));
    }

    function test_RevertWhen_PoolPolicyDisabled() external {
        hook.setPoolPolicy(poolKey, type(uint128).max, false, false);

        vm.expectRevert();
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }

    function test_RevertWhen_AllowlistEnabledAndSenderNotAllowed() external {
        hook.setPoolPolicy(poolKey, type(uint128).max, true, true);

        vm.expectRevert();
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        hook.setSenderAllowlist(address(swapRouter), true);

        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }

    function test_RevertWhen_MaxSwapExceeded() external {
        hook.setPoolPolicy(poolKey, 1e16, false, true);

        vm.expectRevert();
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }

    function test_RevertWhen_PermissionBitsMismatch() external {
        vm.expectRevert();
        new StrategyHook(poolManager, address(this), receiver);
    }
}
