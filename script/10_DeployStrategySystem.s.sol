// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {StrategyHook} from "src/StrategyHook.sol";
import {StrategyVault} from "src/StrategyVault.sol";
import {StrategyRegistry} from "src/StrategyRegistry.sol";
import {LendingAdapterMock} from "src/mocks/LendingAdapterMock.sol";
import {IStrategyVaultHookReceiver} from "src/interfaces/IStrategyVaultHookReceiver.sol";
import {IStrategyVaultViews} from "src/interfaces/IStrategyVaultViews.sol";

contract DeployStrategySystemScript is Script {
    uint160 internal constant HOOK_FLAGS = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

    function run() external {
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address underlyingAsset = vm.envAddress("UNDERLYING_ASSET");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER");

        vm.startBroadcast();

        StrategyVault vault = new StrategyVault(initialOwner, IERC20(underlyingAsset), "Yield Strategy Token", "yTOKEN", 100);

        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManagerAddress),
            initialOwner,
            IStrategyVaultHookReceiver(address(vault))
        );
        (address expectedHookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, HOOK_FLAGS, type(StrategyHook).creationCode, constructorArgs);

        StrategyHook hook =
            new StrategyHook{salt: salt}(IPoolManager(poolManagerAddress), initialOwner, IStrategyVaultHookReceiver(address(vault)));
        require(address(hook) == expectedHookAddress, "DeployStrategySystemScript: Hook address mismatch");

        StrategyRegistry registry = new StrategyRegistry(initialOwner);
        LendingAdapterMock lending = new LendingAdapterMock(vault.yieldToken(), IStrategyVaultViews(address(vault)), 7000);

        if (initialOwner == msg.sender) {
            vault.setHook(address(hook));

            bytes32 strategyId = keccak256(abi.encode(address(vault), address(hook), underlyingAsset, block.chainid));
            registry.setAllowedCreator(initialOwner, true);
            registry.registerStrategy(
                strategyId,
                address(vault),
                address(hook),
                underlyingAsset,
                address(vault.yieldToken()),
                3000,
                "ipfs://tokenized-strategy-spec"
            );
        }

        vm.stopBroadcast();

        console2.log("StrategyVault", address(vault));
        console2.log("YieldToken", address(vault.yieldToken()));
        console2.log("StrategyHook", address(hook));
        console2.log("StrategyRegistry", address(registry));
        console2.log("LendingAdapterMock", address(lending));
    }
}
