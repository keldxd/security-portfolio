// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockToken} from "./MockToken.sol";

/// @title VulnerableVault
/// @notice A minimal share-based vault with the same root cause as the Compound v2 fork exploits
///         (Hundred Finance, Apr 2023; Sonne Finance, May 2024):
///
///         1. The share price is derived from the vault's raw token balance.
///         2. Anyone can raise that balance by transferring tokens in directly ("donating").
///         3. Share math rounds down, and a deposit that rounds to zero shares is accepted.
///
///         When the vault is empty, an attacker can own the only share, donate to inflate its price,
///         and make the next depositor's shares round down to zero, then withdraw everything.
///
/// @dev DO NOT USE. Intentionally vulnerable, for education only.
contract VulnerableVault {
    // forge-lint: disable-next-line(screaming-snake-case-immutable) -- vaults expose `asset()` by convention
    MockToken public immutable asset;

    uint256 public totalSupply; // total shares issued
    mapping(address => uint256) public balanceOf; // shares per account

    error TransferFailed();

    constructor(MockToken _asset) {
        asset = _asset;
    }

    /// @notice Value backing all shares. BUG: reads the live balance, so a direct transfer
    ///         (a donation that never goes through deposit) changes the share price.
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice shares = assets * totalSupply / totalAssets, rounded down.
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? assets : (assets * supply) / totalAssets();
    }

    /// @notice assets = shares * totalAssets / totalSupply, rounded down.
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? shares : (shares * totalAssets()) / supply;
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = convertToShares(assets);
        // BUG: no check that shares > 0. A victim's deposit can round to 0 shares and still go through,
        // handing their tokens to whoever already holds the existing shares.
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
