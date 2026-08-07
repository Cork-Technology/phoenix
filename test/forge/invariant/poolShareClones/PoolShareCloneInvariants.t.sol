// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {SharesFactory} from "contracts/core/assets/SharesFactory.sol";
import {Market, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {ISharesFactory} from "contracts/interfaces/ISharesFactory.sol";
import {Test} from "forge-std/Test.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract PoolShareCloneHandler is Test {
    SharesFactory public immutable factory;
    address public immutable poolManager;
    Market private templateMarket;

    MarketId[] private poolIds;
    PoolShare[] private principalTokens;
    PoolShare[] private swapTokens;
    mapping(MarketId poolId => bool deployed) public isDeployed;
    mapping(address token => uint256 supply) public expectedSupply;

    constructor(SharesFactory factory_, address poolManager_, Market memory templateMarket_) {
        factory = factory_;
        poolManager = poolManager_;
        templateMarket = templateMarket_;
    }

    function deploy(bytes32 rawPoolId) public {
        if (poolIds.length == 16) return;
        MarketId poolId = MarketId.wrap(rawPoolId);
        if (isDeployed[poolId]) return;
        (address predictedPrincipal, address predictedSwap) = factory.predictPoolShares(poolId);
        if (predictedPrincipal.code.length != 0 || predictedSwap.code.length != 0) return;

        vm.prank(poolManager);
        (address principal, address swap) =
            factory.deployPoolShares(ISharesFactory.DeployParams({poolParams: templateMarket, poolId: poolId}));
        isDeployed[poolId] = true;
        poolIds.push(poolId);
        principalTokens.push(PoolShare(principal));
        swapTokens.push(PoolShare(swap));
    }

    function mint(uint256 indexSeed, bool mintSwap, address receiver, uint96 rawAmount) external {
        if (poolIds.length == 0) return;
        uint256 index = indexSeed % poolIds.length;
        if (receiver == address(0)) receiver = address(uint160(uint256(keccak256(abi.encode(indexSeed, rawAmount)))));
        if (receiver == address(0)) receiver = address(1);
        uint256 amount = bound(rawAmount, 1, type(uint96).max);
        PoolShare token = mintSwap ? swapTokens[index] : principalTokens[index];

        vm.prank(poolManager);
        token.mint(receiver, amount);
        expectedSupply[address(token)] += amount;
    }

    function pairCount() external view returns (uint256) {
        return poolIds.length;
    }

    function pairAt(uint256 index) external view returns (MarketId poolId, PoolShare principal, PoolShare swap) {
        return (poolIds[index], principalTokens[index], swapTokens[index]);
    }
}

contract PoolShareCloneInvariantTest is BaseTest {
    PoolShareCloneHandler private handler;

    function setUp() public override {
        super.setUp();
        handler =
            new PoolShareCloneHandler(sharesFactory, address(corkPoolManager), corkPoolManager.market(defaultPoolId));
        vm.stopPrank();
        handler.deploy(keccak256("initial-invariant-market"));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = PoolShareCloneHandler.deploy.selector;
        selectors[1] = PoolShareCloneHandler.mint.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_predictionMatchesEveryDeployment() external view {
        uint256 length = handler.pairCount();
        assertGt(length, 0, "handler must exercise at least one deployment");
        for (uint256 i; i < length; ++i) {
            (MarketId poolId, PoolShare principal, PoolShare swap) = handler.pairAt(i);
            (address predictedPrincipal, address predictedSwap) = sharesFactory.predictPoolShares(poolId);
            assertEq(address(principal), predictedPrincipal);
            assertEq(address(swap), predictedSwap);
        }
    }

    function invariant_deployedSharesKeepCanonicalRuntimeAndImmutableBindings() external view {
        uint256 length = handler.pairCount();
        for (uint256 i; i < length; ++i) {
            (MarketId poolId, PoolShare principal, PoolShare swap) = handler.pairAt(i);
            assertEq(address(principal).code.length, 45);
            assertEq(address(swap).code.length, 45);
            assertEq(address(principal.poolManager()), address(corkPoolManager));
            assertEq(address(swap.poolManager()), address(corkPoolManager));
            assertEq(principal.factory(), address(sharesFactory));
            assertEq(swap.factory(), address(sharesFactory));
            assertEq(MarketId.unwrap(principal.poolId()), MarketId.unwrap(poolId));
            assertEq(MarketId.unwrap(swap.poolId()), MarketId.unwrap(poolId));
        }
    }

    function invariant_cptCstAndCrossMarketAddressesNeverCollide() external view {
        uint256 length = handler.pairCount();
        for (uint256 i; i < length; ++i) {
            (, PoolShare principalI, PoolShare swapI) = handler.pairAt(i);
            assertNotEq(address(principalI), address(swapI));
            for (uint256 j = i + 1; j < length; ++j) {
                (, PoolShare principalJ, PoolShare swapJ) = handler.pairAt(j);
                assertNotEq(address(principalI), address(principalJ));
                assertNotEq(address(principalI), address(swapJ));
                assertNotEq(address(swapI), address(principalJ));
                assertNotEq(address(swapI), address(swapJ));
            }
        }
    }

    function invariant_cptCstAndCrossMarketSupplyStateRemainIsolated() external view {
        uint256 length = handler.pairCount();
        for (uint256 i; i < length; ++i) {
            (, PoolShare principal, PoolShare swap) = handler.pairAt(i);
            assertEq(principal.totalSupply(), handler.expectedSupply(address(principal)));
            assertEq(swap.totalSupply(), handler.expectedSupply(address(swap)));
        }
    }
}
