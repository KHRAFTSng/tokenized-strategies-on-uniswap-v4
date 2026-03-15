// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IStrategyVaultViews {
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
}
