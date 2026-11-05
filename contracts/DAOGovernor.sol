// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

/**
 * @title DAOGovernor
 * @notice Token-weighted governance with simple counting, fractional quorum and a dedicated timelock.
 * @dev Uses OpenZeppelin Contracts 5.6.1. The clock follows the voting token; use DAOToken for
 * timestamp-based delays and periods. No privileged deployer or external timelock admin is installed.
 * The timelock retains its standard self-admin role, exercisable through governance proposals.
 */
contract DAOGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /// @notice Thrown when the voting token is zero, not a contract, or not on a timestamp clock.
    /// @param token The rejected token address.
    error InvalidVotingToken(address token);

    /**
     * @notice Initializes governance and deploys its dedicated TimelockController.
     * @param name Governor name used by its EIP-712 domain.
     * @param token Voting token; DAOToken supplies a timestamp clock.
     * @param votingDelay_ Delay before voting, measured in token clock units (seconds for DAOToken).
     * @param votingPeriod_ Voting duration in token clock units (seconds for DAOToken).
     * @param proposalThreshold_ Minimum delegated voting power required to propose, in base units.
     * @param quorumPercent Initial quorum numerator with denominator 100.
     * @param timelockDelay Minimum execution delay in seconds.
     */
    constructor(
        string memory name,
        IVotes token,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumPercent,
        uint256 timelockDelay
    )
        Governor(name)
        GovernorSettings(votingDelay_, votingPeriod_, proposalThreshold_)
        GovernorVotes(token)
        GovernorVotesQuorumFraction(quorumPercent)
        GovernorTimelockControl(_deployTimelock(timelockDelay))
    {
        // Reject zero/code-less addresses and tokens that are not on a timestamp clock.
        // A high-level call to a code-less address reverts, so this also rejects EOAs.
        if (
            address(token) == address(0)
                || keccak256(bytes(IERC6372(address(token)).CLOCK_MODE())) != keccak256("mode=timestamp")
        ) {
            revert InvalidVotingToken(address(token));
        }
    }

    /// @notice Returns the voting token's current timepoint.
    /// @return The current timepoint, in seconds when using DAOToken.
    function clock() public view override(Governor, GovernorVotes) returns (uint48) {
        return super.clock();
    }

    /// @notice Returns the clock descriptor supplied by the voting token.
    /// @return The ERC-6372 clock descriptor; mode=timestamp for DAOToken.
    function CLOCK_MODE() public view override(Governor, GovernorVotes) returns (string memory) {
        return super.CLOCK_MODE();
    }

    /// @notice Returns the delay from proposal creation to its voting snapshot.
    /// @return The delay in voting token clock units.
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /// @notice Returns the duration of a proposal's voting period.
    /// @return The duration in voting token clock units.
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /// @notice Returns the minimum delegated voting power required to propose.
    /// @return The proposal threshold in voting token base units.
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    /// @notice Returns the proposal state, including its timelock operation status.
    /// @param proposalId Identifier of the proposal.
    /// @return The current proposal state.
    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    /// @notice Reports whether a proposal requires queuing before execution.
    /// @param proposalId Identifier of the proposal.
    /// @return True because this governor executes through a timelock.
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    /// @notice Reports support for an ERC-165 interface.
    /// @param interfaceId Interface identifier to query.
    /// @return Whether the inherited governor supports the interface.
    function supportsInterface(bytes4 interfaceId) public view override(Governor) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @dev Deploys a self-administered timelock with this governor as sole initial proposer/canceller.
    /// Execution is open to everyone; the zero admin argument grants no external admin role.
    function _deployTimelock(uint256 timelockDelay) private returns (TimelockController) {
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        return new TimelockController(timelockDelay, proposers, executors, address(0));
    }

    /// @dev Queues successful proposal actions through the inherited timelock integration.
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @dev Executes queued proposal actions through the timelock after its enforced delay.
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @dev Cancels a proposal and its associated timelock operation, if queued.
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /// @dev Returns the timelock address used for governance execution and authorization.
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
