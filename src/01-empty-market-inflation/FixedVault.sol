// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockToken} from "./MockToken.sol";

/// @title FixedVault
/// @notice Same vault with two standard mitigations:
///
///         1. Virtual shares and assets (the approach used by OpenZeppelin's ERC4626).
///            The math behaves as if VIRTUAL_SHARES extra shares and 1 extra asset always exist.
///            An attacker who owns "the only share" no longer owns the whole vault, so a donation
///            is mostly captured by the virtual shares and the attack loses money.
///
///         2. Deposits that would mint zero shares revert, so a victim can never silently
///            receive nothing for their tokens.
///
///         A third common mitigation (what Sonne's normal process relied on) is to seed a new market
///         with a small deposit and burn those shares before enabling it, so it is never empty.
contract FixedVault {
    // forge-lint: disable-next-line(screaming-snake-case-immutable) -- vaults expose `asset()` by convention
    MockToken public immutable asset;

    /// @dev 10^6 virtual shares: makes the attack cost ~1,000,000x more than it could ever gain.
    uint256 public constant VIRTUAL_SHARES = 1e6;
    uint256 public constant VIRTUAL_ASSETS = 1;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    error ZeroShares();
    error TransferFailed();

    constructor(MockToken _asset) {
        asset = _asset;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice shares = assets * (totalSupply + VIRTUAL_SHARES) / (totalAssets + VIRTUAL_ASSETS)
    function convertToShares(uint256 assets) public view returns (uint256) {
        return (assets * (totalSupply + VIRTUAL_SHARES)) / (totalAssets() + VIRTUAL_ASSETS);
    }

    /// @notice assets = shares * (totalAssets + VIRTUAL_ASSETS) / (totalSupply + VIRTUAL_SHARES)
    function convertToAssets(uint256 shares) public view returns (uint256) {
        return (shares * (totalAssets() + VIRTUAL_ASSETS)) / (totalSupply + VIRTUAL_SHARES);
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = convertToShares(assets);
        if (shares == 0) revert ZeroShares(); // FIX: never accept a deposit that mints nothing
        if (!asset.transferFrom(msg.sender, address(this), assets)) revert TransferFailed();
        totalSupply += shares;
        balanceOf[msg.sender] += shares;
    }

    function redeem(uint256 shares) external returns (uint256 assets) {
        assets = convertToAssets(shares);
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        if (!asset.transfer(msg.sender, assets)) revert TransferFailed();
    }
}
