// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {MarketId} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract PoolShareCloneBehaviorTests is BaseTest {
    function test_Constructor_RevertsForZeroPoolManager() external {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        new PoolShare(address(0));
    }

    function test_Implementation_IsInitializationLocked() external {
        PoolShare implementation = PoolShare(sharesFactory.POOL_SHARE_IMPLEMENTATION());
        overridePrank(address(sharesFactory));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(defaultPoolId, "locked", "LOCK", ensOwner);
        assertEq(implementation.owner(), address(0));
        assertEq(implementation.name(), "");
        assertEq(implementation.issuedAt(), 0);
    }

    function test_Initialize_RawCloneRejectsNonFactoryThenFactoryInitializesAllState() external {
        PoolShare implementation = PoolShare(sharesFactory.POOL_SHARE_IMPLEMENTATION());
        PoolShare clone = PoolShare(Clones.clone(address(implementation)));
        MarketId poolId = MarketId.wrap(keccak256("raw-clone-market"));
        overridePrank(alice);
        vm.expectRevert(IErrors.NotSharesFactory.selector);
        clone.initialize(poolId, "Collateral-Reference7cPT", "REF7cPT", alice);

        vm.warp(block.timestamp + 7 days);
        overridePrank(address(sharesFactory));
        clone.initialize(poolId, "Collateral-Reference7cPT", "REF7cPT", ensOwner);
        assertEq(MarketId.unwrap(clone.poolId()), MarketId.unwrap(poolId));
        assertEq(clone.pairName(), "Collateral-Reference7cPT");
        assertEq(clone.name(), "Collateral-Reference7cPT");
        assertEq(clone.symbol(), "REF7cPT");
        assertEq(clone.owner(), ensOwner);
        assertEq(clone.issuedAt(), block.timestamp);
        assertEq(address(clone.poolManager()), address(corkPoolManager));
        assertEq(clone.factory(), address(sharesFactory));
    }

    function test_Initialize_ReinitializationByFactoryRevertsWithoutMutation() external {
        PoolShare implementation = PoolShare(sharesFactory.POOL_SHARE_IMPLEMENTATION());
        PoolShare clone = PoolShare(Clones.clone(address(implementation)));
        MarketId poolId = MarketId.wrap(keccak256("initialized-once"));
        overridePrank(address(sharesFactory));
        clone.initialize(poolId, "Pair cST", "PcST", ensOwner);
        overridePrank(address(sharesFactory));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        clone.initialize(MarketId.wrap(bytes32(uint256(99))), "Changed", "BAD", eve);
        assertEq(MarketId.unwrap(clone.poolId()), MarketId.unwrap(poolId));
        assertEq(clone.name(), "Pair cST");
        assertEq(clone.owner(), ensOwner);
    }

    function test_ERC20_CloneSupportsTransferApprovalAndStandardTransferFrom() external {
        overridePrank(address(corkPoolManager));
        swapToken.mint(alice, 10 ether);
        overridePrank(alice);
        assertTrue(swapToken.transfer(bravo, 2 ether));
        assertTrue(swapToken.approve(eve, 4 ether));
        overridePrank(eve);
        assertTrue(swapToken.transferFrom(alice, charlie, 3 ether));
        assertEq(swapToken.balanceOf(alice), 5 ether);
        assertEq(swapToken.balanceOf(bravo), 2 ether);
        assertEq(swapToken.balanceOf(charlie), 3 ether);
        assertEq(swapToken.allowance(alice, eve), 1 ether);
    }

    function test_Ownership_CloneEnforcesOwnerAndDoesNotGrantPoolManagerPrivileges() external {
        overridePrank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        swapToken.transferOwnership(alice);
        overridePrank(ensOwner);
        swapToken.transferOwnership(alice);
        assertEq(swapToken.owner(), alice);
        overridePrank(alice);
        vm.expectRevert(IErrors.NotCorkPoolManager.selector);
        swapToken.mint(alice, 1 ether);
        overridePrank(address(corkPoolManager));
        swapToken.mint(eve, 1 ether);
        assertEq(swapToken.balanceOf(eve), 1 ether);
    }
}
