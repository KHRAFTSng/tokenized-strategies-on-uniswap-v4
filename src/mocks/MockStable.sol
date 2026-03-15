// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockStable
 * @notice Demo-only stable token for lending adapter flows.
 * @custom:security-contact security@tokenized-strategies.local
 */
contract MockStable is ERC20 {
    address public immutable minter;

    error MockStable__OnlyMinter();

    constructor(string memory name_, string memory symbol_, address minter_) ERC20(name_, symbol_) {
        minter = minter_;
    }

    modifier onlyMinter() {
        if (msg.sender != minter) {
            revert MockStable__OnlyMinter();
        }
        _;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }
}
