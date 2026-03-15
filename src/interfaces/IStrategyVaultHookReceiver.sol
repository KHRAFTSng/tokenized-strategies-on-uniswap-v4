// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IStrategyVaultHookReceiver {
    function notifySwapVolume(bytes32 poolId, uint256 notionalAmount, address sender) external;
}
