// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DAOGovernorTestBase} from "./DAOGovernor.Base.t.sol";

contract DAOGovernorRevertTest is DAOGovernorTestBase {
    // ---------------- Voting reverts ----------------

    function test_Vote_RevertsOnDoubleVote() public {
        _propose();
        _toActive();
        vm.prank(alice);
        governor.castVote(pid, 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorAlreadyCastVote.selector, alice));
        governor.castVote(pid, 0);
        (uint256 a, uint256 f,) = governor.proposalVotes(pid);
        assertEq(a, 0);
        assertEq(f, 300_000e18);
    }

    function test_Vote_RevertsWhilePending() public {
        _propose();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                pid,
                IGovernor.ProposalState.Pending,
                bytes32(uint256(1) << uint8(IGovernor.ProposalState.Active))
            )
        );
        governor.castVote(pid, 1);
    }

    function test_Vote_RevertsOnInvalidSupportValue() public {
        _propose();
        _toActive();
        vm.prank(alice);
        vm.expectRevert();
        governor.castVote(pid, 3);
    }

    function test_Vote_RevertsOnUnknownProposal() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorNonexistentProposal.selector, 123));
        governor.castVote(123, 1);
    }

    // ---------------- Propose / cancel reverts ----------------

    function test_Propose_RevertsOnEmptyActions() public {
        delete targets;
        delete values;
        delete calldatas;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorInvalidProposalLength.selector, 0, 0, 0));
        governor.propose(targets, values, calldatas, description);
    }

    function test_Propose_RevertsOnLengthMismatch() public {
        _setActions(1200);
        values.push(0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorInvalidProposalLength.selector, 1, 1, 2));
        governor.propose(targets, values, calldatas, description);
    }

    function test_Propose_RevertsOnDuplicate() public {
        _propose();
        vm.prank(bob);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, description);
    }

    function test_Cancel_RevertsForNonProposer() public {
        _propose();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorUnableToCancel.selector, pid, bob));
        governor.cancel(targets, values, calldatas, _descHash());
    }

    function test_Cancel_RevertsOnceVotingStarted() public {
        _propose();
        _toActive();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorUnableToCancel.selector, pid, alice));
        governor.cancel(targets, values, calldatas, _descHash());
    }

    // ---------------- Queue / execute reverts ----------------

    function test_Queue_RevertsWhileActive() public {
        _propose();
        _toActive();
        vm.prank(alice);
        governor.castVote(pid, 1);
        vm.prank(bob);
        governor.castVote(pid, 1);
        vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
        _queue();
    }

    function test_Execute_RevertsBeforeQueue() public {
        _propose();
        _toActive();
        vm.prank(alice);
        governor.castVote(pid, 1);
        vm.prank(bob);
        governor.castVote(pid, 1);
        _toVotingEnd();
        // Succeeded but not queued: timelock operation was never scheduled
        vm.expectPartialRevert(TimelockController.TimelockUnexpectedOperationState.selector);
        _execute();
    }

    function test_Execute_RevertsImmediatelyAfterQueue() public {
        _passAndQueue();
        vm.expectPartialRevert(TimelockController.TimelockUnexpectedOperationState.selector);
        _execute();
        assertEq(governor.votingPeriod(), 600);
    }

    function test_Execute_RevertsOneSecondBeforeTimelockDelay() public {
        _passAndQueue();
        skip(TL_DELAY - 1);
        vm.expectPartialRevert(TimelockController.TimelockUnexpectedOperationState.selector);
        _execute();
        assertEq(governor.votingPeriod(), 600);
        skip(1);
        _execute(); // now allowed
        assertEq(governor.votingPeriod(), 1200);
    }

    function test_Execute_RevertsWhenDefeated() public {
        _propose();
        _toVotingEnd();
        vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
        _execute();
    }

    function test_Execute_CannotReplay() public {
        _passAndQueue();
        skip(TL_DELAY);
        _execute();
        vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
        _execute();
    }

    function test_Queue_CannotRequeue() public {
        _passAndQueue();
        vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
        _queue();
    }

    function test_Execute_FailingActionRevertsAndStaysQueued() public {
        // setVotingPeriod(0) is invalid -> action reverts in the timelock
        description = "bad period";
        _setActions(0);
        vm.prank(alice);
        pid = governor.propose(targets, values, calldatas, description);
        _toActive();
        vm.prank(alice);
        governor.castVote(pid, 1);
        vm.prank(bob);
        governor.castVote(pid, 1);
        _toVotingEnd();
        _queue();
        skip(TL_DELAY);
        vm.expectRevert();
        _execute();
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Queued));
        assertEq(governor.votingPeriod(), 600);
    }

    // ---------------- Governance-only setters ----------------

    function test_Setters_RevertForOutsider() public {
        vm.startPrank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, outsider));
        governor.setVotingDelay(1);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, outsider));
        governor.setVotingPeriod(1);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, outsider));
        governor.setProposalThreshold(1);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, outsider));
        governor.updateQuorumNumerator(50);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, outsider));
        governor.updateTimelock(timelock);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, outsider));
        governor.relay(outsider, 0, "");
        vm.stopPrank();
    }

    function test_Setters_RevertForHolderWithMajority() public {
        vm.startPrank(holder);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, holder));
        governor.setVotingPeriod(1);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, holder));
        governor.updateQuorumNumerator(1);
        vm.stopPrank();
        assertEq(governor.votingPeriod(), 600);
        assertEq(governor.quorumNumerator(), 4);
    }

    function test_Setters_RevertForGovernorItself() public {
        vm.prank(address(governor));
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, address(governor)));
        governor.setVotingDelay(1);
    }

    function test_Timelock_OnlyGovernorCanSchedule() public {
        _setActions(1200);
        vm.prank(alice);
        vm.expectRevert();
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), bytes32(0), TL_DELAY);
    }
}
