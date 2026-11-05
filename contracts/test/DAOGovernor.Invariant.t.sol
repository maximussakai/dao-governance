// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DAOToken} from "../DAOToken.sol";
import {DAOGovernorTestBase} from "./DAOGovernor.Base.t.sol";

contract TokenHandler is Test {
    DAOToken public token;
    address[] public actors;

    constructor(DAOToken t, address[] memory a) {
        token = t;
        actors = a;
    }

    function transfer(uint256 from, uint256 to, uint256 amt) external {
        address f = actors[bound(from, 0, actors.length - 1)];
        address t = actors[bound(to, 0, actors.length - 1)];
        amt = bound(amt, 0, token.balanceOf(f));
        vm.prank(f);
        token.transfer(t, amt);
    }

    function delegate(uint256 from, uint256 to) external {
        address f = actors[bound(from, 0, actors.length - 1)];
        address t = actors[bound(to, 0, actors.length - 1)];
        vm.prank(f);
        token.delegate(t);
    }

    function warp(uint256 secs) external {
        skip(bound(secs, 1, 1 days));
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}

contract DAOGovernorInvariantTest is DAOGovernorTestBase {
    TokenHandler internal handler;

    function setUp() public override {
        super.setUp();
        address[] memory a = new address[](5);
        a[0] = holder;
        a[1] = alice;
        a[2] = bob;
        a[3] = carol;
        a[4] = dave;
        handler = new TokenHandler(token, a);
        targetContract(address(handler));
    }

    /// S1: supply is constant and equals the sum of the actors' balances.
    function invariant_SupplyConstantAndConserved() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
    }

    /// Delegated voting power never exceeds supply.
    function invariant_VotesNeverExceedSupply() public view {
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            sum += token.getVotes(handler.actors(i));
        }
        assertLe(sum, SUPPLY);
    }

    /// Timelock roles stay frozen without governance.
    function invariant_NoEOAAdmin() public view {
        for (uint256 i; i < handler.actorCount(); ++i) {
            assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), handler.actors(i)));
        }
    }
}
