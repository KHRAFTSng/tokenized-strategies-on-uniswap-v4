// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title StrategyRegistry
 * @notice Registry for strategy metadata and allowlists.
 * @custom:security-contact security@tokenized-strategies.local
 */
contract StrategyRegistry is Ownable2Step {
    struct StrategyConfig {
        address vault;
        address hook;
        address underlying;
        address yieldToken;
        uint24 poolFee;
        bool active;
        string metadataURI;
    }

    mapping(bytes32 strategyId => StrategyConfig config) private s_strategies;
    mapping(address account => bool allowed) public allowedCreators;

    error StrategyRegistry__ZeroAddress();
    error StrategyRegistry__AlreadyExists(bytes32 strategyId);
    error StrategyRegistry__NotFound(bytes32 strategyId);
    error StrategyRegistry__NotAllowedCreator();

    event AllowedCreatorSet(address indexed account, bool allowed);
    event StrategyRegistered(bytes32 indexed strategyId, address indexed vault, address indexed hook, address underlying);
    event StrategyUpdated(bytes32 indexed strategyId, bool active, string metadataURI);

    constructor(address initialOwner) Ownable(initialOwner) {}

    /*//////////////////////////////////////////////////////////////
                           USER-FACING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function registerStrategy(
        bytes32 strategyId,
        address vault,
        address hook,
        address underlying,
        address yieldToken,
        uint24 poolFee,
        string calldata metadataURI
    ) external {
        if (!allowedCreators[msg.sender] && msg.sender != owner()) {
            revert StrategyRegistry__NotAllowedCreator();
        }
        if (vault == address(0) || hook == address(0) || underlying == address(0) || yieldToken == address(0)) {
            revert StrategyRegistry__ZeroAddress();
        }
        if (s_strategies[strategyId].vault != address(0)) {
            revert StrategyRegistry__AlreadyExists(strategyId);
        }

        s_strategies[strategyId] = StrategyConfig({
            vault: vault,
            hook: hook,
            underlying: underlying,
            yieldToken: yieldToken,
            poolFee: poolFee,
            active: true,
            metadataURI: metadataURI
        });

        emit StrategyRegistered(strategyId, vault, hook, underlying);
    }

    function updateStrategy(bytes32 strategyId, bool active, string calldata metadataURI) external onlyOwner {
        StrategyConfig storage strategy = s_strategies[strategyId];
        if (strategy.vault == address(0)) {
            revert StrategyRegistry__NotFound(strategyId);
        }
        strategy.active = active;
        strategy.metadataURI = metadataURI;
        emit StrategyUpdated(strategyId, active, metadataURI);
    }

    /*//////////////////////////////////////////////////////////////
                           USER-FACING VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getStrategy(bytes32 strategyId) external view returns (StrategyConfig memory) {
        return s_strategies[strategyId];
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setAllowedCreator(address account, bool allowed) external onlyOwner {
        allowedCreators[account] = allowed;
        emit AllowedCreatorSet(account, allowed);
    }
}
