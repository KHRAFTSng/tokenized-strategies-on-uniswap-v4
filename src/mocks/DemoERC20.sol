// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title DemoERC20
 * @notice Demo-only mintable token for testnet showcase flows.
 * @custom:security-contact security@tokenized-strategies.local
 */
contract DemoERC20 is ERC20, Ownable2Step {
    constructor(string memory name_, string memory symbol_, address initialOwner) ERC20(name_, symbol_) Ownable(initialOwner) {
        _mint(initialOwner, 1_000_000e18);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
