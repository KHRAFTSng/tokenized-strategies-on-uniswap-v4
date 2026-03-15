// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {IStrategyVaultHookReceiver} from "src/interfaces/IStrategyVaultHookReceiver.sol";

/**
 * @title StrategyHook
 * @notice Swap policy hook for tokenized strategy execution constraints.
 * @custom:security-contact security@tokenized-strategies.local
 */
contract StrategyHook is BaseHook, Ownable2Step {
    using PoolIdLibrary for PoolKey;

    struct PoolPolicy {
        uint128 maxSwapAmount;
        bool enforceSenderAllowlist;
        bool enabled;
    }

    IStrategyVaultHookReceiver public vault;

    mapping(PoolId poolId => PoolPolicy policy) public poolPolicies;
    mapping(address sender => bool allowed) public senderAllowlist;
    mapping(PoolId poolId => uint256 observedNotional) public observedNotionalByPool;

    error StrategyHook__ZeroAddress();
    error StrategyHook__PolicyDisabled();
    error StrategyHook__SenderNotAllowed(address sender);
    error StrategyHook__SwapAboveLimit(uint256 amount, uint256 limit);

    event VaultSet(address indexed vault);
    event SenderAllowlistSet(address indexed sender, bool allowed);
    event PoolPolicySet(bytes32 indexed poolId, uint128 maxSwapAmount, bool enforceSenderAllowlist, bool enabled);
    event PolicyApplied(bytes32 indexed poolId, address indexed sender, uint256 notionalAmount, uint128 maxSwapAmount);

    constructor(IPoolManager poolManager_, address initialOwner, IStrategyVaultHookReceiver vault_)
        BaseHook(poolManager_)
        Ownable(initialOwner)
    {
        if (address(vault_) == address(0)) {
            revert StrategyHook__ZeroAddress();
        }
        vault = vault_;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions = Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                     USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setVault(IStrategyVaultHookReceiver newVault) external onlyOwner {
        if (address(newVault) == address(0)) {
            revert StrategyHook__ZeroAddress();
        }
        vault = newVault;
        emit VaultSet(address(newVault));
    }

    function setSenderAllowlist(address sender, bool allowed) external onlyOwner {
        senderAllowlist[sender] = allowed;
        emit SenderAllowlistSet(sender, allowed);
    }

    function setPoolPolicy(PoolKey calldata key, uint128 maxSwapAmount, bool enforceSenderAllowlist, bool enabled)
        external
        onlyOwner
    {
        PoolId poolId = key.toId();
        poolPolicies[poolId] = PoolPolicy({
            maxSwapAmount: maxSwapAmount,
            enforceSenderAllowlist: enforceSenderAllowlist,
            enabled: enabled
        });

        emit PoolPolicySet(PoolId.unwrap(poolId), maxSwapAmount, enforceSenderAllowlist, enabled);
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        PoolPolicy memory policy = poolPolicies[poolId];

        if (!policy.enabled) {
            revert StrategyHook__PolicyDisabled();
        }

        if (policy.enforceSenderAllowlist && !senderAllowlist[sender]) {
            revert StrategyHook__SenderNotAllowed(sender);
        }

        uint256 notionalAmount = _abs(params.amountSpecified);
        if (policy.maxSwapAmount != 0 && notionalAmount > policy.maxSwapAmount) {
            revert StrategyHook__SwapAboveLimit(notionalAmount, policy.maxSwapAmount);
        }

        emit PolicyApplied(PoolId.unwrap(poolId), sender, notionalAmount, policy.maxSwapAmount);
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        PoolId poolId = key.toId();
        uint256 notionalAmount = _abs(params.amountSpecified);

        observedNotionalByPool[poolId] += notionalAmount;
        vault.notifySwapVolume(PoolId.unwrap(poolId), notionalAmount, sender);

        return (BaseHook.afterSwap.selector, 0);
    }

    function _abs(int256 amount) internal pure returns (uint256) {
        return amount >= 0 ? uint256(amount) : uint256(-amount);
    }
}
