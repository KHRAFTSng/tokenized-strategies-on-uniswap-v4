// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title YieldToken
 * @notice Vault share token for a tokenized Uniswap v4 strategy.
 * @custom:security-contact security@tokenized-strategies.local
 */
contract YieldToken is ERC20, ERC20Permit {
    address public immutable vault;

    error YieldToken__OnlyVault();
    error YieldToken__ZeroAddress();

    constructor(string memory name_, string memory symbol_, address vault_)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {
        if (vault_ == address(0)) {
            revert YieldToken__ZeroAddress();
        }
        vault = vault_;
    }

    modifier onlyVault() {
        if (msg.sender != vault) {
            revert YieldToken__OnlyVault();
        }
        _;
    }

    function mint(address to, uint256 amount) external onlyVault {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyVault {
        _burn(from, amount);
    }
}
