// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {DAOGovernorTestBase} from "./DAOGovernor.Base.t.sol";

contract DAOGovernorFuzzTest is DAOGovernorTestBase {
    address internal eve = makeAddr("eve");

    /// Vote weight equals the delegated balance at the snapshot, regardless of later transfers.
    function testFuzz_VoteWeightIgnoresTransfersAfterSnapshot(uint256 given, uint256 moved, uint8 support) public {
        given = bound(given, 1, 400_000e18);
        support = uint8(bound(support, 0, 2));
        vm.prank(holder);
        token.transfer(dave, given);
        vm.prank(dave);
        token.delegate(dave);
        skip(1);

        _propose();
        _toActive();

        moved = bound(moved, 0, given);
        vm.prank(dave);
        token.transfer(eve, moved);
        vm.prank(eve);
        token.delegate(eve);
        skip(1);

        vm.prank(dave);
        assertEq(governor.castVote(pid, support), given);
        vm.prank(eve);
        assertEq(governor.castVote(pid, support), 0);

        (uint256 a, uint256 f, uint256 ab) = governor.proposalVotes(pid);
        uint256[3] memory tally = [a, f, ab];
        uint256 expectedIdx = support == 0 ? 0 : (support == 1 ? 1 : 2);
        assertEq(tally[expectedIdx], given);
        assertEq(a + f + ab, given);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// Tallies equal the sum of snapshot balances per support bucket.
    function testFuzz_TalliesMatchSnapshotBalances(uint8 sA, uint8 sB, uint8 sC) public {
        sA = uint8(bound(sA, 0, 2));
        sB = uint8(bound(sB, 0, 2));
        sC = uint8(bound(sC, 0, 2));
        _propose();
        _toActive();
        vm.prank(alice);
        governor.castVote(pid, sA);
        vm.prank(bob);
        governor.castVote(pid, sB);
        vm.prank(carol);
        governor.castVote(pid, sC);

        uint256[3] memory exp;
        exp[sA] += 300_000e18;
        exp[sB] += 200_000e18;
        exp[sC] += 10_000e18;
        (uint256 a, uint256 f, uint256 ab) = governor.proposalVotes(pid);
        assertEq(a, exp[0]);
        assertEq(f, exp[1]);
        assertEq(ab, exp[2]);
    }

    /// A lone For voter passes iff its weight meets the 4% quorum.
    function testFuzz_QuorumThreshold(uint256 weight) public {
        weight = bound(weight, 1, 490_000e18);
        vm.prank(holder);
        token.transfer(dave, weight);
        vm.prank(dave);
        token.delegate(dave);
        skip(1);
        _propose();
        _toActive();
        vm.prank(dave);
        governor.castVote(pid, 1);
        _toVotingEnd();
        IGovernor.ProposalState s = governor.state(pid);
        if (weight >= 40_000e18) {
            assertEq(uint8(s), uint8(IGovernor.ProposalState.Succeeded));
        } else {
            assertEq(uint8(s), uint8(IGovernor.ProposalState.Defeated));
        }
    }

    /// For must strictly exceed Against (with quorum met by both).
    function testFuzz_ForMustExceedAgainst(uint256 forW, uint256 againstW) public {
        forW = bound(forW, 50_000e18, 240_000e18);
        againstW = bound(againstW, 50_000e18, 240_000e18);
        vm.startPrank(holder);
        token.transfer(dave, forW);
        token.transfer(eve, againstW);
        vm.stopPrank();
        vm.prank(dave);
        token.delegate(dave);
        vm.prank(eve);
        token.delegate(eve);
        skip(1);
        _propose();
        _toActive();
        vm.prank(dave);
        governor.castVote(pid, 1);
        vm.prank(eve);
        governor.castVote(pid, 0);
        _toVotingEnd();
        IGovernor.ProposalState s = governor.state(pid);
        assertEq(uint8(s), forW > againstW ? uint8(IGovernor.ProposalState.Succeeded) : uint8(IGovernor.ProposalState.Defeated));
    }

    /// Transfers never change supply and conserve balances.
    function testFuzz_TransferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, 300_000e18);
        uint256 a0 = token.balanceOf(alice);
        uint256 d0 = token.balanceOf(dave);
        vm.prank(alice);
        token.transfer(dave, amount);
        assertEq(token.balanceOf(alice), a0 - amount);
        assertEq(token.balanceOf(dave), d0 + amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// Execution is only possible once the full timelock delay has elapsed.
    function testFuzz_ExecuteOnlyAfterDelay(uint256 wait) public {
        wait = bound(wait, 0, 3 days);
        _passAndQueue();
        skip(wait);
        if (wait < TL_DELAY) {
            vm.expectRevert();
            _execute();
            assertEq(governor.votingPeriod(), 600);
        } else {
            _execute();
            assertEq(governor.votingPeriod(), 1200);
        }
    }
}
