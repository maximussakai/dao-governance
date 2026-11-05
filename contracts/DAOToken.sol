// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title DAOToken
 * @notice Fixed-supply governance token with permit and timestamp-based vote checkpoints.
 * @dev Uses OpenZeppelin Contracts 5.6.1. Holders must delegate to activate voting power.
 * There is no owner and no post-construction mint or burn entry point.
 */
contract DAOToken is ERC20, ERC20Permit, ERC20Votes {
    /// @notice The initial supply must be greater than zero.
    error ZeroInitialSupply();

    /**
     * @notice Mints the entire fixed supply to the initial holder.
     * @param name Token name and EIP-712 permit domain name.
     * @param symbol Token symbol.
     * @param initialHolder Recipient of the initial supply; cannot be the zero address.
     * @param initialSupply Supply in base units (18 decimals), not whole tokens.
     */
    constructor(string memory name, string memory symbol, address initialHolder, uint256 initialSupply)
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        if (initialHolder == address(0)) revert ERC20InvalidReceiver(address(0));
        if (initialSupply == 0) revert ZeroInitialSupply();
        _mint(initialHolder, initialSupply);
    }

    /// @notice Returns the current checkpoint timepoint in Unix seconds.
    /// @return The current block timestamp.
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @notice Describes the ERC-6372 clock as timestamp-based.
    /// @return The ERC-6372 timestamp clock descriptor.
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /// @notice Returns the shared permit and signed-delegation nonce for an account.
    /// @param owner Account whose nonce is requested.
    /// @return The next unused nonce.
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /// @dev Updates token balances and delegated voting checkpoints together.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }
}
