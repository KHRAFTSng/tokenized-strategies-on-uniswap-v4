// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {YieldToken} from "src/YieldToken.sol";
import {AccountingLibrary} from "src/libraries/AccountingLibrary.sol";
import {IStrategyVaultHookReceiver} from "src/interfaces/IStrategyVaultHookReceiver.sol";

/**
 * @title StrategyVault
 * @notice Custodies strategy assets and mints yield-bearing shares.
 * @custom:security-contact security@tokenized-strategies.local
 */
contract StrategyVault is Ownable2Step, ReentrancyGuard, IStrategyVaultHookReceiver {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    YieldToken public immutable yieldToken;

    address public hook;
    uint16 public immutable strategyRebateBps;

    uint256 public totalManagedAssets;
    uint256 public lockedLiquidityAssets;
    uint256 public rebateReserveAssets;
    uint256 public pendingStrategyYield;

    error StrategyVault__ZeroAddress();
    error StrategyVault__AmountZero();
    error StrategyVault__InsufficientShares();
    error StrategyVault__InsufficientLiquidAssets();
    error StrategyVault__OnlyHook();
    error StrategyVault__InvalidHook();
    error StrategyVault__InvalidRebateBps();

    event HookSet(address indexed hook);
    event Deposit(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
    event Redeem(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
    event AmmFeeYieldReported(address indexed caller, uint256 assetsAdded);
    event RebateReserveFunded(address indexed caller, uint256 assetsAdded);
    event StrategyYieldAccrued(bytes32 indexed poolId, address indexed sender, uint256 notionalAmount, uint256 yieldAmount);
    event StrategyYieldApplied(address indexed caller, uint256 yieldAmount);
    event LockedLiquidityUpdated(uint256 lockedLiquidityAssets);

    constructor(
        address initialOwner,
        IERC20 asset_,
        string memory shareName,
        string memory shareSymbol,
        uint16 strategyRebateBps_
    ) Ownable(initialOwner) {
        if (address(asset_) == address(0)) {
            revert StrategyVault__ZeroAddress();
        }
        if (strategyRebateBps_ > 2_000) {
            revert StrategyVault__InvalidRebateBps();
        }

        asset = asset_;
        strategyRebateBps = strategyRebateBps_;
        yieldToken = new YieldToken(shareName, shareSymbol, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                     USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        if (assets == 0) {
            revert StrategyVault__AmountZero();
        }

        shares = previewDeposit(assets);
        if (shares == 0) {
            revert StrategyVault__InsufficientShares();
        }

        asset.safeTransferFrom(msg.sender, address(this), assets);
        totalManagedAssets += assets;
        yieldToken.mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function redeem(uint256 shares, address receiver) external nonReentrant returns (uint256 assets) {
        if (shares == 0) {
            revert StrategyVault__AmountZero();
        }

        assets = previewRedeem(shares);

        uint256 liquidAssets = maxWithdrawableAssets();
        if (assets > liquidAssets || assets > asset.balanceOf(address(this))) {
            revert StrategyVault__InsufficientLiquidAssets();
        }

        yieldToken.burn(msg.sender, shares);
        totalManagedAssets -= assets;
        asset.safeTransfer(receiver, assets);

        emit Redeem(msg.sender, receiver, assets, shares);
    }

    function reportAmmFeeYield(uint256 assetsAdded) external nonReentrant {
        if (assetsAdded == 0) {
            revert StrategyVault__AmountZero();
        }

        asset.safeTransferFrom(msg.sender, address(this), assetsAdded);
        totalManagedAssets += assetsAdded;

        emit AmmFeeYieldReported(msg.sender, assetsAdded);
    }

    function fundRebateReserve(uint256 assetsAdded) external nonReentrant onlyOwner {
        if (assetsAdded == 0) {
            revert StrategyVault__AmountZero();
        }

        asset.safeTransferFrom(msg.sender, address(this), assetsAdded);
        rebateReserveAssets += assetsAdded;

        emit RebateReserveFunded(msg.sender, assetsAdded);
    }

    function applyDeterministicYield(uint256 maxAmount) external nonReentrant returns (uint256 applied) {
        uint256 pending = pendingStrategyYield;
        uint256 reserve = rebateReserveAssets;

        if (pending == 0 || reserve == 0) {
            return 0;
        }

        applied = pending;
        if (applied > reserve) {
            applied = reserve;
        }
        if (maxAmount != 0 && applied > maxAmount) {
            applied = maxAmount;
        }

        pendingStrategyYield = pending - applied;
        rebateReserveAssets = reserve - applied;
        totalManagedAssets += applied;

        emit StrategyYieldApplied(msg.sender, applied);
    }

    /*//////////////////////////////////////////////////////////////
                     USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        shares = AccountingLibrary.toSharesDown(assets, totalManagedAssets, yieldToken.totalSupply());
    }

    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        assets = AccountingLibrary.toAssetsDown(shares, totalManagedAssets, yieldToken.totalSupply());
    }

    function sharePrice() public view returns (uint256) {
        return AccountingLibrary.sharePrice(totalManagedAssets, yieldToken.totalSupply());
    }

    function maxWithdrawableAssets() public view returns (uint256 assets) {
        assets = totalManagedAssets - lockedLiquidityAssets;
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setHook(address newHook) external onlyOwner {
        if (newHook == address(0)) {
            revert StrategyVault__ZeroAddress();
        }
        hook = newHook;
        emit HookSet(newHook);
    }

    function setLockedLiquidityAssets(uint256 lockedAssets) external onlyOwner {
        if (lockedAssets > totalManagedAssets) {
            revert StrategyVault__InsufficientLiquidAssets();
        }
        lockedLiquidityAssets = lockedAssets;
        emit LockedLiquidityUpdated(lockedAssets);
    }

    function notifySwapVolume(bytes32 poolId, uint256 notionalAmount, address sender) external {
        if (msg.sender != hook) {
            revert StrategyVault__OnlyHook();
        }
        uint256 yieldAmount = AccountingLibrary.applyBps(notionalAmount, strategyRebateBps);
        pendingStrategyYield += yieldAmount;
        emit StrategyYieldAccrued(poolId, sender, notionalAmount, yieldAmount);
    }
}
