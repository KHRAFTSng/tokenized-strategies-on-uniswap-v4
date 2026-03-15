// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {BaseScript} from "./base/BaseScript.sol";
import {IStrategyVaultHookReceiver} from "src/interfaces/IStrategyVaultHookReceiver.sol";
import {StrategyHook} from "src/StrategyHook.sol";

/// @notice Mines the address and deploys StrategyHook with hook permission bits.
contract DeployHookScript is BaseScript {
    function run() public {
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address vaultAddress = vm.envAddress("STRATEGY_VAULT");

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs =
            abi.encode(IPoolManager(address(poolManager)), initialOwner, IStrategyVaultHookReceiver(vaultAddress));

        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(StrategyHook).creationCode, constructorArgs);

        vm.startBroadcast();
        StrategyHook hook = new StrategyHook{salt: salt}(poolManager, initialOwner, IStrategyVaultHookReceiver(vaultAddress));
        vm.stopBroadcast();

        require(address(hook) == hookAddress, "DeployHookScript: Hook Address Mismatch");
    }
}
