// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Vesting} from "../src/Vesting.sol";
import {DeployVesting} from "../script/Vesting.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract VestingTest is Test {
    Vesting public vesting;
    ERC20Mock public token;

    address public locker = address(this);
    address public beneficiary = makeAddr("beneficiary");

    uint256 public constant LOCKED_AMOUNT = 10e18;
    uint256 public constant EXPIRY_DURATION = 30; // 30 seconds

    // Vesting contract events
    event Locked(address indexed from, address indexed receiver, uint256 indexed amount, uint256 expiry);
    event Claimed(address indexed receiver, uint256 indexed amount);

    function setUp() public {
        DeployVesting deployer = new DeployVesting();
        (vesting, token) = deployer.run();

        // Mint tokens to the beneficiary, start the prank, transfer tokens to the locker, stop the prank, approve the vesting contract to transfer tokens
        token.mint(beneficiary, LOCKED_AMOUNT);
        vm.startPrank(beneficiary);
        token.transfer(locker, LOCKED_AMOUNT);
        vm.stopPrank();
        token.approve(address(vesting), LOCKED_AMOUNT);

        vm.label(locker, "Locker");
        vm.label(beneficiary, "Beneficiary");
        vm.label(address(vesting), "Vesting");
        vm.label(address(token), "Token");
    }

    //============= Constructor Tests =============//

    function test__constructor() public {
        assertEq(address(vesting.token()), address(token));
        assertEq(vesting.receiver(), address(0));
        assertEq(vesting.amount(), 0);
        assertEq(vesting.expiry(), 0);
        assertFalse(vesting.locked());
        assertFalse(vesting.claimed());
    }

    //============= Lock Tests =============//

    function test__lock() public {
        vesting.lock(beneficiary, LOCKED_AMOUNT, block.timestamp + EXPIRY_DURATION);

        assertEq(vesting.receiver(), beneficiary);
        assertEq(vesting.amount(), LOCKED_AMOUNT);
        assertEq(vesting.expiry(), block.timestamp + EXPIRY_DURATION);
        assertTrue(vesting.locked());
        assertFalse(vesting.claimed());

        assertEq(token.balanceOf(address(vesting)), LOCKED_AMOUNT);
        assertEq(token.balanceOf(locker), 0);
    }

    // Use modifier after testing for success case
    modifier tokensLocked() {
        vesting.lock(beneficiary, LOCKED_AMOUNT, block.timestamp + EXPIRY_DURATION);
        assertTrue(vesting.locked());
        _;
    }

    function test__lockRevertsWithInvalidExpiration() public {
        vm.expectRevert(Vesting.Vesting__expirationMustBeInTheFuture.selector);
        vesting.lock(beneficiary, LOCKED_AMOUNT, block.timestamp - 1);
        uint256 currTime = vesting.getTime();
        vm.expectRevert(Vesting.Vesting__expirationMustBeInTheFuture.selector);
        vesting.lock(beneficiary, LOCKED_AMOUNT, currTime);
    }

    function test__lockRevertsIfAlreadyLocked() public tokensLocked {
        vm.expectRevert(Vesting.Vesting__alreadyLockedTokens.selector);
        vesting.lock(beneficiary, LOCKED_AMOUNT, block.timestamp + EXPIRY_DURATION);
    }

    function test__lockEmitsEvent() public {
        vm.expectEmit(true, true, true, true, address(vesting));
        emit Locked(locker, beneficiary, LOCKED_AMOUNT, block.timestamp + EXPIRY_DURATION);
        vesting.lock(beneficiary, LOCKED_AMOUNT, block.timestamp + EXPIRY_DURATION);
        assertTrue(vesting.locked());
    }

    //============= Claim Tests =============//

    function test__claimRevertsIfNotLocked() public {
        vm.expectRevert(Vesting.Vesting__TokensNotLocked.selector);
        vesting.claim();
        assertFalse(vesting.claimed());
    }

    function test__claimRevertsIfNotExpired() public tokensLocked {
        vm.expectRevert(Vesting.Vesting__tokenLockNotExpired.selector);
        vesting.claim();
        assertFalse(vesting.claimed());
    }

    function test__claim() public tokensLocked {
        vm.warp(block.timestamp + EXPIRY_DURATION + 1);
        vesting.claim();

        assertTrue(vesting.claimed());
        assertFalse(vesting.locked());
        assertEq(token.balanceOf(beneficiary), LOCKED_AMOUNT);
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    function test__claimRevertsIfAlreadyClaimed() public tokensLocked {
        vm.warp(block.timestamp + EXPIRY_DURATION + 1);
        vesting.claim();
        assertTrue(vesting.claimed());

        vm.expectRevert(Vesting.Vesting__tokensAlreadyClaimed.selector);
        vesting.claim();

        // Still claimed only once
        assertTrue(vesting.claimed());
        assertFalse(vesting.locked());
        assertEq(token.balanceOf(beneficiary), LOCKED_AMOUNT);
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    function test__claimEmitsEvent() public tokensLocked {
        vm.warp(block.timestamp + EXPIRY_DURATION + 1);
        vm.expectEmit(true, true, false, true, address(vesting));
        emit Claimed(beneficiary, LOCKED_AMOUNT);
        vesting.claim();
        assertTrue(vesting.claimed());
    }

    //============= Lock and Claim Cycle Test =============//

    function test__lockAndClaimCycle() public {
        // Lock tokens for first time
        vesting.lock(beneficiary, LOCKED_AMOUNT, block.timestamp + EXPIRY_DURATION);
        assertTrue(vesting.locked());
        // Claim tokens
        vm.warp(block.timestamp + EXPIRY_DURATION + 1);
        vesting.claim();
        assertTrue(vesting.claimed());
        assertFalse(vesting.locked());

        // Lock tokens for second time for new beneficiary
        address newBeneficiary = makeAddr("newBeneficiary");
        uint256 newAmount = 20e18;
        uint256 newExpiry = vesting.getTime() + 60;
        token.mint(newBeneficiary, newAmount);
        vm.prank(newBeneficiary);
        token.transfer(locker, newAmount);
        token.approve(address(vesting), newAmount);
        vesting.lock(newBeneficiary, newAmount, newExpiry);
        // Check state changes
        assertEq(vesting.receiver(), newBeneficiary);
        assertEq(vesting.amount(), newAmount);
        assertEq(vesting.expiry(), newExpiry);
        assertTrue(vesting.locked());
        assertFalse(vesting.claimed());
        // Claim tokens for new beneficiary
        vm.warp(newExpiry + 1);
        vesting.claim();
        assertTrue(vesting.claimed());
        assertFalse(vesting.locked());

        // Check balances
        assertEq(token.balanceOf(beneficiary), LOCKED_AMOUNT);
        assertEq(token.balanceOf(newBeneficiary), newAmount);
        assertEq(token.balanceOf(address(vesting)), 0);
        assertEq(token.balanceOf(locker), 0);
    }
}
