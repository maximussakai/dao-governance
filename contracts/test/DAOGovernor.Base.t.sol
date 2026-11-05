// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DAOToken} from "../DAOToken.sol";
import {DAOGovernor} from "../DAOGovernor.sol";

abstract contract DAOGovernorTestBase is Test {
    DAOToken internal token;
    DAOGovernor internal governor;
    TimelockController internal timelock;

    address internal holder = makeAddr("holder");
    address internal alice = makeAddr("alice"); // 300k
    address internal bob = makeAddr("bob"); // 200k
    address internal carol = makeAddr("carol"); // 10k (1%)
    address internal dave = makeAddr("dave"); // 0
    address internal outsider = makeAddr("outsider");

    uint256 internal constant SUPPLY = 1_000_000e18;
    uint48 internal constant DELAY = 60;
    uint32 internal constant PERIOD = 600;
    uint256 internal constant QUORUM_PCT = 4;
    uint256 internal constant TL_DELAY = 86400;

    // Current proposal under test
    address[] internal targets;
    uint256[] internal values;
    bytes[] internal calldatas;
    string internal description = "Proposal #1: set voting period to 1200";
    uint256 internal pid;

    function setUp() public virtual {
        vm.warp(1_000_000);
        token = new DAOToken("DAO Token", "DAO", holder, SUPPLY);
        governor = new DAOGovernor("DAO Governor", IVotes(address(token)), DELAY, PERIOD, 0, QUORUM_PCT, TL_DELAY);
        timelock = TimelockController(payable(governor.timelock()));

        vm.startPrank(holder);
        token.transfer(alice, 300_000e18);
        token.transfer(bob, 200_000e18);
        token.transfer(carol, 10_000e18);
        token.delegate(holder); // 490k
        vm.stopPrank();
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.prank(carol);
        token.delegate(carol);
        skip(1);
    }

    function _descHash() internal view returns (bytes32) {
        return keccak256(bytes(description));
    }

    /// @dev Builds a proposal calling governor.setVotingPeriod(newPeriod) through the timelock.
    function _setActions(uint32 newPeriod) internal {
        delete targets;
        delete values;
        delete calldatas;
        targets.push(address(governor));
        values.push(0);
        calldatas.push(abi.encodeCall(governor.setVotingPeriod, (newPeriod)));
    }

    function _propose() internal returns (uint256) {
        _setActions(1200);
        vm.prank(alice);
        pid = governor.propose(targets, values, calldatas, description);
        return pid;
    }

    function _toActive() internal {
        vm.warp(governor.proposalSnapshot(pid) + 1);
    }

    function _toVotingEnd() internal {
        vm.warp(governor.proposalDeadline(pid) + 1);
    }

    function _queue() internal {
        governor.queue(targets, values, calldatas, _descHash());
    }

    function _execute() internal {
        governor.execute(targets, values, calldatas, _descHash());
    }

    function _passAndQueue() internal {
        _propose();
        _toActive();
        vm.prank(alice);
        governor.castVote(pid, 1);
        vm.prank(bob);
        governor.castVote(pid, 1);
        _toVotingEnd();
        _queue();
    }
}
