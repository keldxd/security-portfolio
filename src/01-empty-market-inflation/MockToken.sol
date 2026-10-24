// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockToken
/// @notice Minimal ERC20 used only in tests. Anyone can mint, so test accounts can be funded easily.
contract MockToken {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    // forge-lint: disable-next-line(screaming-snake-case-const) -- ERC20 requires the name `decimals`
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
