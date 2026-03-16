// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {YieldToken} from "src/YieldToken.sol";

contract YieldTokenTest is Test {
    function test_RevertWhen_ConstructorVaultZero() external {
        vm.expectRevert(YieldToken.YieldToken__ZeroAddress.selector);
        new YieldToken("Yield Asset", "yAST", address(0));
    }
}
