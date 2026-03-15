// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {AccountingLibrary} from "src/libraries/AccountingLibrary.sol";
import {MockStable} from "src/mocks/MockStable.sol";
import {IStrategyVaultViews} from "src/interfaces/IStrategyVaultViews.sol";

/**
 * @title LendingAdapterMock
 * @notice Demo-only collateral adapter showing yToken composability.
 * @custom:security-contact security@tokenized-strategies.local
 */
contract LendingAdapterMock is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable collateralToken;
    IStrategyVaultViews public immutable vault;
    MockStable public immutable debtToken;

    uint16 public immutable collateralFactorBps;

    mapping(address user => uint256 shares) public collateralShares;
    mapping(address user => uint256 debt) public userDebt;

    error LendingAdapterMock__AmountZero();
    error LendingAdapterMock__BorrowTooHigh(uint256 requested, uint256 maxBorrow);

    event CollateralDeposited(address indexed user, uint256 shares);
    event CollateralWithdrawn(address indexed user, uint256 shares);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);

    constructor(IERC20 collateralToken_, IStrategyVaultViews vault_, uint16 collateralFactorBps_) {
        collateralToken = collateralToken_;
        vault = vault_;
        collateralFactorBps = collateralFactorBps_;
        debtToken = new MockStable("Mock USD", "mUSD", address(this));
    }

    /*//////////////////////////////////////////////////////////////
                     USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function depositCollateral(uint256 shares) external nonReentrant {
        if (shares == 0) {
            revert LendingAdapterMock__AmountZero();
        }

        collateralToken.safeTransferFrom(msg.sender, address(this), shares);
        collateralShares[msg.sender] += shares;

        emit CollateralDeposited(msg.sender, shares);
    }

    function withdrawCollateral(uint256 shares) external nonReentrant {
        if (shares == 0) {
            revert LendingAdapterMock__AmountZero();
        }

        collateralShares[msg.sender] -= shares;
        _enforceLtv(msg.sender, userDebt[msg.sender]);
        collateralToken.safeTransfer(msg.sender, shares);

        emit CollateralWithdrawn(msg.sender, shares);
    }

    function borrow(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert LendingAdapterMock__AmountZero();
        }

        uint256 newDebt = userDebt[msg.sender] + amount;
        _enforceLtv(msg.sender, newDebt);

        userDebt[msg.sender] = newDebt;
        debtToken.mint(msg.sender, amount);

        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert LendingAdapterMock__AmountZero();
        }

        debtToken.transferFrom(msg.sender, address(this), amount);
        debtToken.burn(address(this), amount);

        uint256 debt = userDebt[msg.sender];
        if (amount >= debt) {
            userDebt[msg.sender] = 0;
        } else {
            userDebt[msg.sender] = debt - amount;
        }

        emit Repaid(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                     USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function maxBorrow(address user) external view returns (uint256 borrowCapacity) {
        uint256 collateralAssets = vault.previewRedeem(collateralShares[user]);
        uint256 maxDebt = AccountingLibrary.applyBps(collateralAssets, collateralFactorBps);
        uint256 debt = userDebt[user];
        borrowCapacity = maxDebt > debt ? maxDebt - debt : 0;
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _enforceLtv(address user, uint256 targetDebt) internal view {
        uint256 collateralAssets = vault.previewRedeem(collateralShares[user]);
        uint256 maxDebt = AccountingLibrary.applyBps(collateralAssets, collateralFactorBps);
        if (targetDebt > maxDebt) {
            revert LendingAdapterMock__BorrowTooHigh(targetDebt, maxDebt);
        }
    }
}
