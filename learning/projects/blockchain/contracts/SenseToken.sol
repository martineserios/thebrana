// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title SenseToken — governance + reward token for SenseLedger
/// @notice ERC-20 with voting (ERC20Votes) so it can power the SenseDAO
///         Governor. Minting is gated to MINTER_ROLE, which is granted to
///         the RewardDistributor contract at deployment.
contract SenseToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Hard cap on total supply — prevents the DAO from accidentally
    ///         granting infinite mints.
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether; // 1B SENSE

    error MaxSupplyExceeded(uint256 attempted, uint256 cap);

    constructor(address admin) ERC20("SenseLedger", "SENSE") ERC20Permit("SenseLedger") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Mint SENSE to `to`. Only callable by MINTER_ROLE holders.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > MAX_SUPPLY) {
            revert MaxSupplyExceeded(totalSupply() + amount, MAX_SUPPLY);
        }
        _mint(to, amount);
    }

    // ---- Required OZ overrides (v5) ----

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
