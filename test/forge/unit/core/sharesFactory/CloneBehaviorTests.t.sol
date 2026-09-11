// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {SharesFactory} from "contracts/core/assets/SharesFactory.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract SharesFactoryCloneBehaviorTests is BaseTest {
    bytes32 private constant CPT_SALT_DOMAIN = keccak256("CORK_POOL_SHARE_CPT");
    bytes32 private constant CST_SALT_DOMAIN = keccak256("CORK_POOL_SHARE_CST");

    function test_Constructor_DeploysOneFixedImplementationBoundToFactoryAndManager() external {
        address implementation = sharesFactory.POOL_SHARE_IMPLEMENTATION();
        assertNotEq(implementation, address(0));
        assertGt(implementation.code.length, 0);
        assertEq(implementation, vm.computeCreateAddress(address(sharesFactory), 1));
        assertEq(PoolShare(implementation).factory(), address(sharesFactory));
        assertEq(address(PoolShare(implementation).poolManager()), address(corkPoolManager));

        _deployShares(MarketId.wrap(keccak256("implementation-stability-a")), _validMarket(block.timestamp + 30 days));
        _deployShares(MarketId.wrap(keccak256("implementation-stability-b")), _validMarket(block.timestamp + 60 days));
        assertEq(sharesFactory.POOL_SHARE_IMPLEMENTATION(), implementation);
    }

    function test_PredictPoolShares_MatchesSpecifiedSaltFormula() external view {
        MarketId poolId = MarketId.wrap(keccak256("formula-market"));
        address implementation = sharesFactory.POOL_SHARE_IMPLEMENTATION();
        bytes32 cptSalt = keccak256(abi.encode(MarketId.unwrap(poolId), CPT_SALT_DOMAIN));
        bytes32 cstSalt = keccak256(abi.encode(MarketId.unwrap(poolId), CST_SALT_DOMAIN));
        (address principalToken, address swapToken) = sharesFactory.predictPoolShares(poolId);
        assertEq(principalToken, Clones.predictDeterministicAddress(implementation, cptSalt, address(sharesFactory)));
        assertEq(swapToken, Clones.predictDeterministicAddress(implementation, cstSalt, address(sharesFactory)));
    }

    function test_Prediction_EqualsDeploymentAndIsIndependentOfTimeAndFactoryNonce() external {
        MarketId targetPoolId = MarketId.wrap(keccak256("prediction-target"));
        Market memory targetMarket = _validMarket(block.timestamp + 100 days);
        (address predictedPrincipal, address predictedSwap) = sharesFactory.predictPoolShares(targetPoolId);
        vm.warp(block.timestamp + 17 days);
        (address afterWarpPrincipal, address afterWarpSwap) = sharesFactory.predictPoolShares(targetPoolId);
        assertEq(afterWarpPrincipal, predictedPrincipal);
        assertEq(afterWarpSwap, predictedSwap);
        _deployShares(MarketId.wrap(keccak256("unrelated-prior-deployment")), _validMarket(block.timestamp + 200 days));
        (address deployedPrincipal, address deployedSwap) = _deployShares(targetPoolId, targetMarket);
        assertEq(deployedPrincipal, predictedPrincipal);
        assertEq(deployedSwap, predictedSwap);
    }

    function test_Prediction_SeparatesVariantsMarketsAndFactories() external {
        MarketId firstPoolId = MarketId.wrap(keccak256("separation-market-a"));
        MarketId secondPoolId = MarketId.wrap(keccak256("separation-market-b"));
        (address firstPrincipal, address firstSwap) = sharesFactory.predictPoolShares(firstPoolId);
        (address secondPrincipal, address secondSwap) = sharesFactory.predictPoolShares(secondPoolId);
        assertNotEq(firstPrincipal, firstSwap);
        assertNotEq(firstPrincipal, secondPrincipal);
        assertNotEq(firstPrincipal, secondSwap);
        assertNotEq(firstSwap, secondPrincipal);
        assertNotEq(firstSwap, secondSwap);
        assertNotEq(secondPrincipal, secondSwap);

        SharesFactory otherFactory = new SharesFactory(address(corkPoolManager), ensOwner);
        (address otherPrincipal, address otherSwap) = otherFactory.predictPoolShares(firstPoolId);
        assertNotEq(otherFactory.POOL_SHARE_IMPLEMENTATION(), sharesFactory.POOL_SHARE_IMPLEMENTATION());
        assertNotEq(otherPrincipal, firstPrincipal);
        assertNotEq(otherSwap, firstSwap);
    }

    function test_DeployedShares_HaveExactCanonical45ByteRuntimeTargetingFixedImplementation() external view {
        address implementation = sharesFactory.POOL_SHARE_IMPLEMENTATION();
        _assertCanonicalClone(address(principalToken), implementation);
        _assertCanonicalClone(address(swapToken), implementation);
    }

    function test_DeployPoolShares_DuplicateRevertsAndPreservesExistingClones() external {
        MarketId poolId = MarketId.wrap(keccak256("duplicate-market"));
        Market memory market = _validMarket(block.timestamp + 90 days);
        (address principal, address swap) = _deployShares(poolId, market);
        overridePrank(address(corkPoolManager));
        PoolShare(principal).mint(alice, 3 ether);
        bytes32 principalCodehash = principal.codehash;
        bytes32 swapCodehash = swap.codehash;
        vm.expectRevert();
        sharesFactory.deployPoolShares(ISharesFactory.DeployParams({poolParams: market, poolId: poolId}));
        assertEq(principal.codehash, principalCodehash);
        assertEq(swap.codehash, swapCodehash);
        assertEq(PoolShare(principal).balanceOf(alice), 3 ether);
    }

    function test_DeployPoolShares_SnapshotsCurrentFactoryOwner() external {
        overridePrank(ensOwner);
        sharesFactory.transferOwnership(alice);

        (address principal, address swap) =
            _deployShares(MarketId.wrap(keccak256("factory-owner-transfer")), _validMarket(block.timestamp + 90 days));

        assertEq(PoolShare(principal).owner(), alice);
        assertEq(PoolShare(swap).owner(), alice);
    }

    function test_DeployPoolShares_FailedInitializationLeavesNeitherPredictedCloneDeployed() external {
        MarketId poolId = MarketId.wrap(keccak256("atomic-initialization"));
        Market memory market = _validMarket(block.timestamp + 90 days);
        (address predictedPrincipal, address predictedSwap) = sharesFactory.predictPoolShares(poolId);
        overridePrank(ensOwner);
        sharesFactory.renounceOwnership();
        overridePrank(address(corkPoolManager));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
        sharesFactory.deployPoolShares(ISharesFactory.DeployParams({poolParams: market, poolId: poolId}));
        assertEq(predictedPrincipal.code.length, 0);
        assertEq(predictedSwap.code.length, 0);
    }

    function _deployShares(MarketId poolId, Market memory market) internal returns (address principal, address swap) {
        overridePrank(address(corkPoolManager));
        return sharesFactory.deployPoolShares(ISharesFactory.DeployParams({poolParams: market, poolId: poolId}));
    }

    function _validMarket(uint256 expiryTimestamp) internal view returns (Market memory market) {
        market = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: expiryTimestamp,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle),
            swapFeePercentage: DEFAULT_BASE_REDEMPTION_FEE,
            unwindSwapFeePercentage: DEFAULT_REVERSE_SWAP_FEE
        });
    }

    function _assertCanonicalClone(address clone, address implementation) internal view {
        bytes memory runtime = clone.code;
        bytes memory expectedRuntime =
            abi.encodePacked(hex"363d3d373d3d3d363d73", bytes20(implementation), hex"5af43d82803e903d91602b57fd5bf3");
        assertEq(runtime.length, 45);
        assertEq(keccak256(runtime), keccak256(expectedRuntime));
    }
}
