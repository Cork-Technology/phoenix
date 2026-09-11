// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IPoolManager, Market, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

/// @notice Swap and unwindSwap fees are fixed when a pool is created and are part of the pool id.
contract PoolFeesTest is BaseTest {
    /// @dev Pool creation rejects fees at or above 100%, so the fuzz covers the complete valid domain.
    uint256 internal constant FUZZ_FEE_UPPER_BOUND = 100 ether - 1;

    function test_CreateNewPool_StoresBothFees() public __as(bravo) {
        uint256 swapFeePercentage = 2 ether;
        uint256 unwindSwapFeePercentage = 1.5 ether;

        MarketId id = _createPoolWithFeesOnDefaultAssets(swapFeePercentage, unwindSwapFeePercentage);

        assertEq(corkPoolManager.swapFee(id), swapFeePercentage);
        assertEq(corkPoolManager.unwindSwapFee(id), unwindSwapFeePercentage);

        Market memory stored = corkPoolManager.market(id);
        assertEq(stored.swapFeePercentage, swapFeePercentage);
        assertEq(stored.unwindSwapFeePercentage, unwindSwapFeePercentage);
    }

    function test_CreateNewPool_AcceptsZeroFees() public __as(bravo) {
        MarketId id = _createPoolWithFeesOnDefaultAssets(0, 0);

        assertEq(corkPoolManager.swapFee(id), 0);
        assertEq(corkPoolManager.unwindSwapFee(id), 0);
    }

    /// @notice The old 5% policy cap is removed; higher fees remain valid inside the arithmetic domain.
    function test_CreateNewPool_AcceptsFeesAboveFivePercent() public __as(bravo) {
        uint256 swapFeePercentage = 15 ether;
        uint256 unwindSwapFeePercentage = 20 ether;

        MarketId id = _createPoolWithFeesOnDefaultAssets(swapFeePercentage, unwindSwapFeePercentage);

        assertEq(corkPoolManager.swapFee(id), swapFeePercentage);
        assertEq(corkPoolManager.unwindSwapFee(id), unwindSwapFeePercentage);

        Market memory stored = corkPoolManager.market(id);
        assertEq(stored.swapFeePercentage, swapFeePercentage);
        assertEq(stored.unwindSwapFeePercentage, unwindSwapFeePercentage);
    }

    function test_CreateNewPool_DifferentFeeGivesDifferentPoolId() public __as(bravo) {
        Market memory first = _market(1 ether, 1 ether);
        Market memory second = _market(2 ether, 1 ether);
        Market memory third = _market(1 ether, 2 ether);

        MarketId firstId = corkPoolManager.getId(first);
        MarketId secondId = corkPoolManager.getId(second);
        MarketId thirdId = corkPoolManager.getId(third);

        assertNotEq(MarketId.unwrap(firstId), MarketId.unwrap(secondId));
        assertNotEq(MarketId.unwrap(firstId), MarketId.unwrap(thirdId));
        assertNotEq(MarketId.unwrap(secondId), MarketId.unwrap(thirdId));

        // same assets and expiry, only the fee differs: all three pools can exist side by side
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(first, false));
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(second, false));
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(third, false));

        assertEq(corkPoolManager.swapFee(firstId), 1 ether);
        assertEq(corkPoolManager.swapFee(secondId), 2 ether);
        assertEq(corkPoolManager.unwindSwapFee(thirdId), 2 ether);
    }

    function test_CreateNewPool_EmitsMarketCreatedWithFees() public __as(bravo) {
        uint256 swapFeePercentage = 3 ether;
        uint256 unwindSwapFeePercentage = 0.5 ether;

        Market memory market = _market(swapFeePercentage, unwindSwapFeePercentage);
        MarketId id = corkPoolManager.getId(market);
        (address expectedPrincipalToken, address expectedSwapToken) = sharesFactory.predictPoolShares(id);

        vm.expectEmit(true, true, true, true, address(corkPoolManager));
        emit IPoolManager.MarketCreated(
            id,
            market.referenceAsset,
            market.collateralAsset,
            market.expiryTimestamp,
            market.rateOracle,
            expectedPrincipalToken,
            expectedSwapToken,
            swapFeePercentage,
            unwindSwapFeePercentage
        );
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(market, false));
    }

    function testFuzz_CreateNewPool_StoresAnyValidFees(uint256 swapFeePercentage, uint256 unwindSwapFeePercentage)
        public
        __as(bravo)
    {
        swapFeePercentage = bound(swapFeePercentage, 0, FUZZ_FEE_UPPER_BOUND);
        unwindSwapFeePercentage = bound(unwindSwapFeePercentage, 0, FUZZ_FEE_UPPER_BOUND);

        MarketId id = _createPoolWithFeesOnDefaultAssets(swapFeePercentage, unwindSwapFeePercentage);

        assertEq(corkPoolManager.swapFee(id), swapFeePercentage);
        assertEq(corkPoolManager.unwindSwapFee(id), unwindSwapFeePercentage);
    }

    //-----------------------------------------------------------------------------------------------------//

    /// @dev Uses the default test assets with a different expiry than the default pool so the id never collides.
    function _market(uint256 swapFeePercentage, uint256 unwindSwapFeePercentage)
        internal
        view
        returns (Market memory market)
    {
        market = Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 30 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle),
            swapFeePercentage: swapFeePercentage,
            unwindSwapFeePercentage: unwindSwapFeePercentage
        });
    }

    function _createPoolWithFeesOnDefaultAssets(uint256 swapFeePercentage, uint256 unwindSwapFeePercentage)
        internal
        returns (MarketId id)
    {
        Market memory market = _market(swapFeePercentage, unwindSwapFeePercentage);
        id = corkPoolManager.getId(market);
        testOracle.setRate(id, DEFAULT_ORACLE_RATE);
        defaultCorkController.createNewPool(IDefaultCorkController.PoolCreationParams(market, false));
    }
}
