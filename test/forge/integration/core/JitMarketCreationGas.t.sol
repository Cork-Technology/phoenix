// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {Market, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract JitMarketCreationGasTest is BaseTest {
    // Pinned from origin/main@9bc470e with FOUNDRY_PROFILE=production using these exact call frames.
    uint256 internal constant CURRENT_MAIN_SHARE_DEPLOYMENT_GAS = 4_448_508;
    uint256 internal constant MAX_SHARE_DEPLOYMENT_GAS = (CURRENT_MAIN_SHARE_DEPLOYMENT_GAS * 15) / 100;
    uint256 internal constant CURRENT_MAIN_JIT_GAS = 5_102_378;
    uint256 internal constant MAX_JIT_GAS = (CURRENT_MAIN_JIT_GAS * 30) / 100;

    function test_isolatedShareDeploymentGasReduction() external {
        Market memory market = _benchmarkMarket();
        MarketId marketId = MarketId.wrap(keccak256(abi.encode(market)));
        vm.stopPrank();
        vm.prank(address(corkPoolManager));
        uint256 gasBefore = gasleft();
        sharesFactory.deployPoolShares(ISharesFactory.DeployParams({poolParams: market, poolId: marketId}));
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("ISOLATED_SHARE_DEPLOYMENT_GAS", gasUsed);
        assertLe(gasUsed, MAX_SHARE_DEPLOYMENT_GAS, "isolated share deployment gas reduction below 85%");
    }

    function test_jitMarketCreationAndInitialLiquidityGasReduction() external {
        Market memory market = _benchmarkMarket();
        MarketId marketId = MarketId.wrap(keccak256(abi.encode(market)));
        testOracle.setRate(marketId, DEFAULT_ORACLE_RATE);

        uint256 gasBefore = gasleft();
        defaultCorkController.createNewPool(
            IDefaultCorkController.PoolCreationParams(
                market, DEFAULT_REVERSE_SWAP_FEE, DEFAULT_BASE_REDEMPTION_FEE, false
            )
        );
        corkPoolManager.deposit(marketId, 1 ether, bravo);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("JIT_CREATE_AND_INITIAL_LIQUIDITY_GAS", gasUsed);
        assertLe(gasUsed, MAX_JIT_GAS, "JIT gas reduction below 70%");
    }

    function _benchmarkMarket() private view returns (Market memory) {
        return Market({
            collateralAsset: address(collateralAsset),
            referenceAsset: address(referenceAsset),
            expiryTimestamp: block.timestamp + 100 days,
            rateMin: DEFAULT_RATE_MIN,
            rateMax: DEFAULT_RATE_MAX,
            rateChangePerDayMax: DEFAULT_RATE_CHANGE_PER_DAY_MAX,
            rateChangeCapacityMax: DEFAULT_RATE_CHANGE_CAPACITY_MAX,
            rateOracle: address(testOracle)
        });
    }
}
