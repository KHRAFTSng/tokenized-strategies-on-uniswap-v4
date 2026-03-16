// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {StrategyRegistry} from "src/StrategyRegistry.sol";

contract StrategyRegistryTest is Test {
    StrategyRegistry internal registry;

    address internal owner = makeAddr("owner");
    address internal creator = makeAddr("creator");
    address internal outsider = makeAddr("outsider");

    bytes32 internal strategyId = keccak256("strategy-1");

    function setUp() public {
        registry = new StrategyRegistry(owner);
    }

    function test_SetAllowedCreator() external {
        vm.prank(owner);
        registry.setAllowedCreator(creator, true);
        assertTrue(registry.allowedCreators(creator));
    }

    function test_RevertWhen_RegisterByUnauthorizedSender() external {
        vm.prank(outsider);
        vm.expectRevert(StrategyRegistry.StrategyRegistry__NotAllowedCreator.selector);
        registry.registerStrategy(strategyId, address(1), address(2), address(3), address(4), 3000, "meta");
    }

    function test_RegisterAndUpdateStrategy() external {
        vm.prank(owner);
        registry.setAllowedCreator(creator, true);

        vm.prank(creator);
        registry.registerStrategy(strategyId, address(11), address(12), address(13), address(14), 3000, "meta");

        StrategyRegistry.StrategyConfig memory cfg = registry.getStrategy(strategyId);
        assertEq(cfg.vault, address(11));
        assertEq(cfg.hook, address(12));
        assertEq(cfg.underlying, address(13));
        assertEq(cfg.yieldToken, address(14));
        assertTrue(cfg.active);

        vm.prank(owner);
        registry.updateStrategy(strategyId, false, "meta-v2");

        cfg = registry.getStrategy(strategyId);
        assertFalse(cfg.active);
        assertEq(cfg.metadataURI, "meta-v2");
    }

    function test_RevertWhen_RegisterWithZeroAddress() external {
        vm.prank(owner);
        vm.expectRevert(StrategyRegistry.StrategyRegistry__ZeroAddress.selector);
        registry.registerStrategy(strategyId, address(0), address(12), address(13), address(14), 3000, "meta");
    }

    function test_RevertWhen_RegisterExistingStrategy() external {
        vm.prank(owner);
        registry.registerStrategy(strategyId, address(11), address(12), address(13), address(14), 3000, "meta");

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(StrategyRegistry.StrategyRegistry__AlreadyExists.selector, strategyId));
        registry.registerStrategy(strategyId, address(11), address(12), address(13), address(14), 3000, "meta");
    }

    function test_RevertWhen_UpdateMissingStrategy() external {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(StrategyRegistry.StrategyRegistry__NotFound.selector, strategyId));
        registry.updateStrategy(strategyId, true, "meta");
    }
}
