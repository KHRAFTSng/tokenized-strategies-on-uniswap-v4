// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SecondaryMarketMock
 * @notice Demo-only constant-product pool for yToken secondary market flows.
 * @custom:security-contact security@tokenized-strategies.local
 */
contract SecondaryMarketMock {
    using SafeERC20 for IERC20;

    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

    error SecondaryMarketMock__InvalidToken();
    error SecondaryMarketMock__AmountZero();
    error SecondaryMarketMock__SlippageExceeded(uint256 expectedMin, uint256 actualOut);

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB);
    event SwapExecuted(address indexed trader, address indexed tokenIn, uint256 amountIn, uint256 amountOut);

    constructor(IERC20 tokenA_, IERC20 tokenB_) {
        tokenA = tokenA_;
        tokenB = tokenB_;
    }

    function addLiquidity(uint256 amountA, uint256 amountB) external {
        if (amountA == 0 || amountB == 0) {
            revert SecondaryMarketMock__AmountZero();
        }

        tokenA.safeTransferFrom(msg.sender, address(this), amountA);
        tokenB.safeTransferFrom(msg.sender, address(this), amountB);

        reserveA += amountA;
        reserveB += amountB;

        emit LiquidityAdded(msg.sender, amountA, amountB);
    }

    function swapExactIn(address tokenIn, uint256 amountIn, uint256 minAmountOut) external returns (uint256 amountOut) {
        if (amountIn == 0) {
            revert SecondaryMarketMock__AmountZero();
        }

        bool aToB;
        if (tokenIn == address(tokenA)) {
            aToB = true;
        } else if (tokenIn == address(tokenB)) {
            aToB = false;
        } else {
            revert SecondaryMarketMock__InvalidToken();
        }

        IERC20 inToken = aToB ? tokenA : tokenB;
        IERC20 outToken = aToB ? tokenB : tokenA;

        (uint256 reserveIn, uint256 reserveOut) = aToB ? (reserveA, reserveB) : (reserveB, reserveA);

        inToken.safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);

        if (amountOut < minAmountOut) {
            revert SecondaryMarketMock__SlippageExceeded(minAmountOut, amountOut);
        }

        if (aToB) {
            reserveA += amountIn;
            reserveB -= amountOut;
        } else {
            reserveB += amountIn;
            reserveA -= amountOut;
        }

        outToken.safeTransfer(msg.sender, amountOut);

        emit SwapExecuted(msg.sender, tokenIn, amountIn, amountOut);
    }
}
