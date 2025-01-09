// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20, ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

contract MockNuvoToken is ERC20Votes, ERC20Permit {
    constructor() ERC20("Mock Nuvo Token", "MNVT") ERC20Permit("MockNuvoToken") {}

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
