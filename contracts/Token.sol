// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract IdolWorldToken is ERC20 {
    uint256 public immutable supply = 1000000000000000000000000; // 1 million token

    constructor() ERC20("IdolWorldToken", "IDWT") {
        _mint(msg.sender, supply);
    }

    function _mint(address account, uint256 amount) internal override {
        super._mint(account, amount);
    }
}