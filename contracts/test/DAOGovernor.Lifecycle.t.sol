// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {DAOGovernorTestBase} from "./DAOGovernor.Base.t.sol";

contract DAOGovernorLifecycleTest is DAOGovernorTestBase {
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

    function _votes() internal view returns (uint256 against, uint256 forV, uint256 abstain) {
        return governor.proposalVotes(pid);
    }

    // ---------------- Happy path ----------------

    function test_Propose_AnyoneWithZeroVotesCanPropose() public {
        _setActions(1200);
        vm.prank(outsider); // zero tokens, zero votes; threshold is 0
        pid = governor.propose(targets, values, calldatas, description);
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Pending));
        assertEq(governor.proposalProposer(pid), outsider);
    }

    function test_Propose_SetsSnapshotAndDeadline() public {
        uint256 t = block.timestamp;
        _propose();
        assertEq(governor.proposalSnapshot(pid), t + 60);
        assertEq(governor.proposalDeadline(pid), t + 60 + 600);
    }

    function test_StateTransitions_PendingActiveDefeated() public {
        _propose();
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Pending));
        _toActive();
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Active));
        _toVotingEnd();
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Defeated)); // no votes
    }

    function test_FullLifecycle_ProposeVoteQueueWaitExecute() public {
        assertEq(governor.votingPeriod(), 600);
        _propose();
        _toActive();

        vm.expectEmit(true, false, false, true, address(governor));
        emit IGovernor.VoteCast(alice, pid, 1, 300_000e18, "");
        vm.prank(alice);
        governor.castVote(pid, 1);
        vm.prank(bob);
        governor.castVote(pid, 1);
        (uint256 a, uint256 f, uint256 ab) = _votes();
        assertEq(a, 0);
        assertEq(f, 500_000e18);
        assertEq(ab, 0);

        _toVotingEnd();
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Succeeded));

        vm.expectEmit(true, false, false, true, address(governor));
        emit IGovernor.ProposalQueued(pid, block.timestamp + TL_DELAY);
        _queue();
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Queued));
        assertEq(governor.proposalEta(pid), block.timestamp + TL_DELAY);

        skip(TL_DELAY);
        vm.expectEmit(false, false, false, true, address(governor));
        emit VotingPeriodSet(600, 1200);
        vm.expectEmit(true, false, false, false, address(governor));
        emit IGovernor.ProposalExecuted(pid);
        vm.prank(outsider); // anyone can execute
        _execute();

        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Executed));
        assertEq(governor.votingPeriod(), 1200);
    }

    function test_Lifecycle_GovernanceCanUpdateQuorum() public {
        description = "raise quorum";
        delete targets;
        delete values;
        delete calldatas;
        targets.push(address(governor));
        values.push(0);
        calldatas.push(abi.encodeCall(governor.updateQuorumNumerator, (10)));
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
        _execute();
        assertEq(governor.quorumNumerator(), 10);
    }

    function test_Anyone_CanQueue() public {
        _propose();
        _toActive();
        vm.prank(alice);
        governor.castVote(pid, 1);
        vm.prank(bob);
        governor.castVote(pid, 1);
        _toVotingEnd();
        vm.prank(outsider);
        _queue();
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Queued));
    }

    function test_Cancel_ProposerCanCancelWhilePending() public {
        _propose();
        vm.prank(alice);
        governor.cancel(targets, values, calldatas, _descHash());
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Canceled));
    }

    // ---------------- Defeat paths ----------------

    function test_Defeated_AgainstOutweighsFor() public {
        _propose();
        _toActive();
        vm.prank(alice);
        governor.castVote(pid, 1); // 300k
        vm.prank(holder);
        governor.castVote(pid, 0); // 490k against
        _toVotingEnd();
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Defeated));
        vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
        _queue();
    }

    function test_Defeated_QuorumNotReached() public {
        _propose();
        _toActive();
        vm.prank(carol);
        governor.castVote(pid, 1); // 10k = 1% < 4%
        _toVotingEnd();
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_Defeated_JustBelowQuorum() public {
        // carol 10k; move 29_999.. so total For is just under 40k
        vm.prank(holder);
        token.transfer(carol, 30_000e18 - 1); // carol = 40k - 1 wei
        skip(1);
        _propose();
        _toActive();
        vm.prank(carol);
        governor.castVote(pid, 1);
        _toVotingEnd();
        assertEq(governor.quorum(governor.proposalSnapshot(pid)), 40_000e18);
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_Succeeds_ExactlyAtQuorum() public {
        vm.prank(holder);
        token.transfer(carol, 30_000e18); // carol = 40k
        skip(1);
        _propose();
        _toActive();
        vm.prank(carol);
        governor.castVote(pid, 1);
        _toVotingEnd();
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function test_Defeated_AbstainOnlyMeetsQuorumButNoForVotes() public {
        _propose();
        _toActive();
        vm.prank(alice);
        governor.castVote(pid, 2); // abstain 300k
        _toVotingEnd();
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_AbstainCountsTowardQuorum() public {
        _propose();
        _toActive();
        vm.prank(alice);
        governor.castVote(pid, 2); // 300k abstain -> quorum met
        vm.prank(carol);
        governor.castVote(pid, 1); // 10k for > 0 against
        _toVotingEnd();
        assertEq(uint8(governor.state(pid)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function test_Defeated_AfterDeadlineNoVotesCastLate() public {
        _propose();
        _toVotingEnd();
        vm.prank(alice);
        vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
        governor.castVote(pid, 1);
    }

    // ---------------- Delegation snapshot ----------------

    function test_Snapshot_DelegationAfterSnapshotGivesNoWeight() public {
        vm.prank(holder);
        token.transfer(dave, 100_000e18);
        _propose();
        _toActive();
        vm.prank(dave);
        token.delegate(dave); // after snapshot
        skip(1);
        assertEq(token.getVotes(dave), 100_000e18);
        vm.prank(dave);
        uint256 w = governor.castVote(pid, 1);
        assertEq(w, 0);
        (, uint256 f,) = _votes();
        assertEq(f, 0);
    }

    function test_Snapshot_DelegationBeforeSnapshotCounts() public {
        vm.prank(holder);
        token.transfer(dave, 100_000e18);
        _propose();
        skip(10); // still in voting delay
        vm.prank(dave);
        token.delegate(dave);
        _toActive();
        vm.prank(dave);
        uint256 w = governor.castVote(pid, 1);
        assertEq(w, 100_000e18);
    }

    function test_Snapshot_TransferAfterSnapshotKeepsWeight() public {
        _propose();
        _toActive();
        vm.startPrank(alice);
        token.transfer(dave, 300_000e18);
        vm.stopPrank();
        vm.prank(dave);
        token.delegate(dave);
        skip(1);

        vm.prank(alice);
        assertEq(governor.castVote(pid, 1), 300_000e18);
        vm.prank(dave);
        assertEq(governor.castVote(pid, 1), 0);
        (, uint256 f,) = _votes();
        assertEq(f, 300_000e18);
    }

    function test_Snapshot_RedelegationAfterSnapshotDoesNotMoveWeight() public {
        _propose();
        _toActive();
        vm.prank(alice);
        token.delegate(bob);
        skip(1);
        vm.prank(alice);
        assertEq(governor.castVote(pid, 1), 300_000e18); // weight fixed at snapshot
        vm.prank(bob);
        assertEq(governor.castVote(pid, 1), 200_000e18);
    }
}
