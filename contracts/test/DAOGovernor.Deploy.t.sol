// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DAOToken} from "../DAOToken.sol";
import {DAOGovernor} from "../DAOGovernor.sol";
import {MockBlockClockVotes, MockNoClock} from "../test-helpers/MockBlockClockVotes.sol";
import {DAOGovernorTestBase} from "./DAOGovernor.Base.t.sol";

contract DAOGovernorDeployTest is DAOGovernorTestBase {
    // ---------------- DAOToken constructor ----------------

    function test_Token_RevertsOnZeroHolder() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        new DAOToken("T", "T", address(0), SUPPLY);
    }

    function test_Token_RevertsOnZeroSupply() public {
        vm.expectRevert(DAOToken.ZeroInitialSupply.selector);
        new DAOToken("T", "T", holder, 0);
    }

    function test_Token_MintsFullSupplyToHolder() public {
        DAOToken t = new DAOToken("T", "T", outsider, SUPPLY);
        assertEq(t.totalSupply(), SUPPLY);
        assertEq(t.balanceOf(outsider), SUPPLY);
        assertEq(t.decimals(), 18);
        assertEq(t.CLOCK_MODE(), "mode=timestamp");
        assertEq(t.clock(), uint48(block.timestamp));
    }

    function test_Token_NoVotingPowerUntilDelegated() public {
        DAOToken t = new DAOToken("T", "T", outsider, SUPPLY);
        assertEq(t.getVotes(outsider), 0);
        vm.prank(outsider);
        t.delegate(outsider);
        assertEq(t.getVotes(outsider), SUPPLY);
    }

    function test_Token_NoMintOrBurnEntryPoints() public {
        bytes[4] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", outsider, 1),
            abi.encodeWithSignature("burn(uint256)", 1),
            abi.encodeWithSignature("burn(address,uint256)", holder, 1),
            abi.encodeWithSignature("burnFrom(address,uint256)", holder, 1)
        ];
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(holder);
            (bool ok,) = address(token).call(calls[i]);
            assertFalse(ok);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_Token_SupplyConstantAfterTransfersAndDelegation() public {
        vm.prank(alice);
        token.transfer(dave, 1e18);
        vm.prank(dave);
        token.delegate(bob);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_Token_PermitSetsAllowanceAndConsumesNonce() public {
        (address signer, uint256 pk) = makeAddrAndKey("signer");
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                dave,
                5e18,
                token.nonces(signer),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        token.permit(signer, dave, 5e18, deadline, v, r, s);
        assertEq(token.allowance(signer, dave), 5e18);
        assertEq(token.nonces(signer), 1);
    }

    // ---------------- DAOGovernor constructor ----------------

    function test_Governor_ParametersSet() public view {
        assertEq(governor.votingDelay(), 60);
        assertEq(governor.votingPeriod(), 600);
        assertEq(governor.proposalThreshold(), 0);
        assertEq(governor.quorumNumerator(), 4);
        assertEq(governor.quorumDenominator(), 100);
        assertEq(address(governor.token()), address(token));
        assertEq(timelock.getMinDelay(), 86400);
        assertEq(governor.CLOCK_MODE(), "mode=timestamp");
        assertEq(governor.clock(), uint48(block.timestamp));
        assertEq(governor.name(), "DAO Governor");
    }

    function test_Governor_QuorumIsFourPercentOfPastSupply() public {
        _propose();
        _toActive();
        assertEq(governor.quorum(governor.proposalSnapshot(pid)), 40_000e18);
    }

    function test_Governor_RejectsZeroToken() public {
        vm.expectRevert();
        new DAOGovernor("G", IVotes(address(0)), DELAY, PERIOD, 0, QUORUM_PCT, TL_DELAY);
    }

    function test_Governor_RejectsEOAToken() public {
        vm.expectRevert();
        new DAOGovernor("G", IVotes(outsider), DELAY, PERIOD, 0, QUORUM_PCT, TL_DELAY);
    }

    function test_Governor_RejectsTokenWithoutClockMode() public {
        MockNoClock bad = new MockNoClock();
        vm.expectRevert();
        new DAOGovernor("G", IVotes(address(bad)), DELAY, PERIOD, 0, QUORUM_PCT, TL_DELAY);
    }

    function test_Governor_RejectsBlockNumberClockToken() public {
        MockBlockClockVotes bad = new MockBlockClockVotes();
        vm.expectRevert(abi.encodeWithSelector(DAOGovernor.InvalidVotingToken.selector, address(bad)));
        new DAOGovernor("G", IVotes(address(bad)), DELAY, PERIOD, 0, QUORUM_PCT, TL_DELAY);
    }

    function test_Governor_RejectsQuorumAbove100() public {
        vm.expectRevert();
        new DAOGovernor("G", IVotes(address(token)), DELAY, PERIOD, 0, 101, TL_DELAY);
    }

    // ---------------- Timelock wiring ----------------

    function test_Timelock_GovernorIsProposerAndCanceller() public view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor)));
    }

    function test_Timelock_AnyoneIsExecutor() public view {
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
    }

    function test_Timelock_NoEOAAdminOrOtherProposer() public view {
        bytes32 admin = timelock.DEFAULT_ADMIN_ROLE();
        address[7] memory others = [holder, alice, bob, carol, dave, outsider, address(this)];
        for (uint256 i; i < others.length; ++i) {
            assertFalse(timelock.hasRole(admin, others[i]));
            assertFalse(timelock.hasRole(timelock.PROPOSER_ROLE(), others[i]));
            assertFalse(timelock.hasRole(timelock.CANCELLER_ROLE(), others[i]));
        }
        assertFalse(timelock.hasRole(admin, address(governor)));
        assertFalse(timelock.hasRole(admin, address(0)));
        assertTrue(timelock.hasRole(admin, address(timelock))); // self-administered
    }

    function test_Timelock_OutsiderCannotGrantRoles() public {
        bytes32 proposer = timelock.PROPOSER_ROLE();
        vm.prank(outsider);
        vm.expectRevert();
        timelock.grantRole(proposer, outsider);
        vm.prank(holder);
        vm.expectRevert();
        timelock.grantRole(proposer, holder);
    }

    function test_Timelock_OutsiderCannotScheduleOrUpdateDelay() public {
        _setActions(1200);
        vm.prank(holder);
        vm.expectRevert();
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), bytes32(0), TL_DELAY);
        vm.prank(holder);
        vm.expectRevert();
        timelock.updateDelay(0);
    }

    function test_Governor_HoldsNoFunds() public view {
        assertEq(address(governor).balance, 0);
        assertEq(token.balanceOf(address(governor)), 0);
    }
}
