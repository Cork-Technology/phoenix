// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IDefaultCorkController} from "contracts/interfaces/IDefaultCorkController.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {IPoolManager, MarketId} from "contracts/interfaces/IPoolManager.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract UpdateFeesTest is BaseTest {
    //------------------------------------- Tests for updateUnwindSwapFeePercentage ----------------------------------------//
    function test_UpdateUnwindSwapFeePercentageRevertWhenCalledByUnprivilegedAccount() public __as(alice) {
        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), DEFAULT_REVERSE_SWAP_FEE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                defaultCorkController.FEE_MANAGER_ROLE()
            )
        );
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, 1.234_567_89 ether);

        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), DEFAULT_REVERSE_SWAP_FEE);
    }

    function test_UpdateUnwindSwapFeePercentageRevertWhenCalledByConfiguratorOnly() public __as(bravo) {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                bravo,
                defaultCorkController.FEE_MANAGER_ROLE()
            )
        );
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, 2 ether);
    }

    function test_UpdateUnwindSwapFeePercentageShouldWorkCorrectly() public __as(feeManager) {
        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), DEFAULT_REVERSE_SWAP_FEE);
        uint256 swapFeeBefore = corkPoolManager.swapFee(defaultPoolId);

        vm.expectEmit(true, true, false, true, address(corkPoolManager));
        emit IPoolManager.UnwindSwapFeePercentageUpdated(defaultPoolId, 1.234_567_89 ether);
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, 1.234_567_89 ether);

        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), 1.234_567_89 ether);
        assertEq(corkPoolManager.swapFee(defaultPoolId), swapFeeBefore);
    }

    //-----------------------------------------------------------------------------------------------------//

    //------------------------------------- Tests for updateSwapFeePercentage ----------------------------------------//
    function test_UpdateSwapFeePercentageRevertWhenCalledByUnprivilegedAccount() public __as(alice) {
        assertEq(corkPoolManager.swapFee(defaultPoolId), DEFAULT_BASE_REDEMPTION_FEE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                defaultCorkController.FEE_MANAGER_ROLE()
            )
        );
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 1.234_567_89 ether);

        assertEq(corkPoolManager.swapFee(defaultPoolId), DEFAULT_BASE_REDEMPTION_FEE);
    }

    function test_UpdateSwapFeePercentageRevertWhenCalledByConfiguratorOnly() public __as(bravo) {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                bravo,
                defaultCorkController.FEE_MANAGER_ROLE()
            )
        );
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 2 ether);
    }

    function test_UpdateSwapFeePercentageShouldWorkCorrectly() public __as(feeManager) {
        assertEq(corkPoolManager.swapFee(defaultPoolId), DEFAULT_BASE_REDEMPTION_FEE);
        uint256 unwindFeeBefore = corkPoolManager.unwindSwapFee(defaultPoolId);

        vm.expectEmit(true, true, false, true, address(corkPoolManager));
        emit IPoolManager.SwapFeePercentageUpdated(defaultPoolId, 1.234_567_89 ether);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 1.234_567_89 ether);

        assertEq(corkPoolManager.swapFee(defaultPoolId), 1.234_567_89 ether);
        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), unwindFeeBefore);
    }

    function test_UpdateFees_AcceptZeroAndMaximum() public __as(feeManager) {
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 0);
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, 0);
        assertEq(corkPoolManager.swapFee(defaultPoolId), 0);
        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), 0);

        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 5 ether);
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, 5 ether);
        assertEq(corkPoolManager.swapFee(defaultPoolId), 5 ether);
        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), 5 ether);
    }

    function test_UpdateSwapFeePercentage_ShouldRevert_WhenFeeExceedsMaximum() public __as(feeManager) {
        uint256 feeBefore = corkPoolManager.swapFee(defaultPoolId);
        vm.expectRevert(IErrors.InvalidFees.selector);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 6 ether);
        assertEq(corkPoolManager.swapFee(defaultPoolId), feeBefore);
    }

    function test_UpdateUnwindSwapFeePercentage_ShouldRevert_WhenFeeExceedsMaximum() public __as(feeManager) {
        uint256 feeBefore = corkPoolManager.unwindSwapFee(defaultPoolId);
        vm.expectRevert(IErrors.InvalidFees.selector);
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, 6 ether);
        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), feeBefore);
    }

    function test_UpdateFees_ShouldRevertForUninitializedMarket() public __as(feeManager) {
        MarketId uninitialized = MarketId.wrap(keccak256("uninitialized"));
        vm.expectRevert(IErrors.NotInitialized.selector);
        defaultCorkController.updateSwapFeePercentage(uninitialized, 1 ether);
        vm.expectRevert(IErrors.NotInitialized.selector);
        defaultCorkController.updateUnwindSwapFeePercentage(uninitialized, 1 ether);
    }

    function test_PoolCreatorSelectsInitialFeesButOnlyFeeManagerCanChangeThem() public {
        overridePrank(bravo);
        _setupMarketAssets(18, 18);
        MarketId marketId = _createPool(2 days, 2 ether, 3 ether, false);
        assertEq(corkPoolManager.unwindSwapFee(marketId), 2 ether);
        assertEq(corkPoolManager.swapFee(marketId), 3 ether);

        vm.expectRevert(_unauthorized(bravo, defaultCorkController.FEE_MANAGER_ROLE()));
        defaultCorkController.updateSwapFeePercentage(marketId, 4 ether);

        overridePrank(feeManager);
        defaultCorkController.updateSwapFeePercentage(marketId, 4 ether);
        assertEq(corkPoolManager.swapFee(marketId), 4 ether);
        assertEq(corkPoolManager.unwindSwapFee(marketId), 2 ether);
    }

    function test_FeeManagerRevocationAndRegrantTakeEffectImmediately() public {
        overridePrank(bravo);
        defaultCorkController.revokeRole(defaultCorkController.FEE_MANAGER_ROLE(), feeManager);

        overridePrank(feeManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                feeManager,
                defaultCorkController.FEE_MANAGER_ROLE()
            )
        );
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 2 ether);

        overridePrank(bravo);
        defaultCorkController.grantRole(defaultCorkController.FEE_MANAGER_ROLE(), feeManager);
        overridePrank(feeManager);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 2 ether);
        assertEq(corkPoolManager.swapFee(defaultPoolId), 2 ether);
    }

    function test_FeeManagerCannotUseUnrelatedControllerAuthorities() public __as(feeManager) {
        bytes32 configuratorRole = defaultCorkController.CONFIGURATOR_ROLE();
        bytes32 poolCreatorRole = defaultCorkController.POOL_CREATOR_ROLE();
        bytes32 pauserRole = defaultCorkController.PAUSER_ROLE();
        bytes32 unpauserRole = defaultCorkController.UNPAUSER_ROLE();
        bytes32 whitelistAdderRole = defaultCorkController.WHITELIST_ADDER_ROLE();
        bytes32 whitelistRemoverRole = defaultCorkController.WHITELIST_REMOVER_ROLE();
        IDefaultCorkController.PoolCreationParams memory poolCreationParams = _defaultPoolCreationParams();

        vm.expectRevert(_unauthorized(feeManager, configuratorRole));
        defaultCorkController.setTreasury(makeAddr("newTreasury"));
        vm.expectRevert(_unauthorized(feeManager, configuratorRole));
        defaultCorkController.setSharesFactory(makeAddr("newSharesFactory"));
        vm.expectRevert(_unauthorized(feeManager, poolCreatorRole));
        defaultCorkController.createNewPool(poolCreationParams);
        vm.expectRevert(_unauthorized(feeManager, pauserRole));
        defaultCorkController.pause();
        vm.expectRevert(_unauthorized(feeManager, unpauserRole));
        defaultCorkController.unpause();

        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        vm.expectRevert(_unauthorized(feeManager, whitelistAdderRole));
        defaultCorkController.addToGlobalWhitelist(accounts);
        vm.expectRevert(_unauthorized(feeManager, whitelistRemoverRole));
        defaultCorkController.removeFromGlobalWhitelist(accounts);
        vm.expectRevert(_unauthorized(feeManager, bytes32(0)));
        defaultCorkController.disableMarketWhitelist(defaultPoolId);
    }

    function testFuzz_FeeManagerCanSetValidFees(uint256 swapFee, uint256 unwindFee) public __as(feeManager) {
        swapFee = bound(swapFee, 0, 5 ether);
        unwindFee = bound(unwindFee, 0, 5 ether);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, swapFee);
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, unwindFee);
        assertEq(corkPoolManager.swapFee(defaultPoolId), swapFee);
        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), unwindFee);
    }

    function testFuzz_FeesAboveMaximumRevertWithoutMutation(uint256 invalidFee) public __as(feeManager) {
        invalidFee = bound(invalidFee, 5 ether + 1, type(uint256).max);
        uint256 swapFeeBefore = corkPoolManager.swapFee(defaultPoolId);
        uint256 unwindFeeBefore = corkPoolManager.unwindSwapFee(defaultPoolId);
        vm.expectRevert(IErrors.InvalidFees.selector);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, invalidFee);
        vm.expectRevert(IErrors.InvalidFees.selector);
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, invalidFee);
        assertEq(corkPoolManager.swapFee(defaultPoolId), swapFeeBefore);
        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), unwindFeeBefore);
    }

    function testFuzz_FeeUpdatesRequireFeeManager(address caller, bool grantFeeRole) public {
        vm.assume(caller != address(0) && caller != address(defaultCorkController));
        vm.assume(caller != bravo && caller != feeManager);
        if (grantFeeRole) {
            overridePrank(bravo);
            defaultCorkController.grantRole(defaultCorkController.FEE_MANAGER_ROLE(), caller);
        }

        overridePrank(caller);
        if (!grantFeeRole) vm.expectRevert(_unauthorized(caller, defaultCorkController.FEE_MANAGER_ROLE()));
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, 2 ether);
        assertEq(corkPoolManager.swapFee(defaultPoolId), grantFeeRole ? 2 ether : DEFAULT_BASE_REDEMPTION_FEE);
    }

    function testFuzz_SequentialFeeUpdatesRemainIndependent(
        uint256 firstSwapFee,
        uint256 unwindFee,
        uint256 secondSwapFee
    ) public __as(feeManager) {
        firstSwapFee = bound(firstSwapFee, 0, 5 ether);
        unwindFee = bound(unwindFee, 0, 5 ether);
        secondSwapFee = bound(secondSwapFee, 0, 5 ether);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, firstSwapFee);
        defaultCorkController.updateUnwindSwapFeePercentage(defaultPoolId, unwindFee);
        defaultCorkController.updateSwapFeePercentage(defaultPoolId, secondSwapFee);
        assertEq(corkPoolManager.swapFee(defaultPoolId), secondSwapFee);
        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), unwindFee);
    }

    function testFuzz_FeeUpdatesRemainIsolatedAcrossMarkets(uint256 swapFee, uint256 unwindFee) public {
        swapFee = bound(swapFee, 0, 5 ether);
        unwindFee = bound(unwindFee, 0, 5 ether);
        MarketId firstMarket = defaultPoolId;

        overridePrank(bravo);
        _setupMarketAssets(18, 18);
        MarketId secondMarket = _createPool(2 days, 2 ether, 3 ether, false);

        overridePrank(feeManager);
        defaultCorkController.updateSwapFeePercentage(firstMarket, swapFee);
        defaultCorkController.updateUnwindSwapFeePercentage(firstMarket, unwindFee);

        assertEq(corkPoolManager.swapFee(firstMarket), swapFee);
        assertEq(corkPoolManager.unwindSwapFee(firstMarket), unwindFee);
        assertEq(corkPoolManager.swapFee(secondMarket), 3 ether);
        assertEq(corkPoolManager.unwindSwapFee(secondMarket), 2 ether);
    }

    function _unauthorized(address account, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, role);
    }

    function _defaultPoolCreationParams()
        internal
        view
        returns (IDefaultCorkController.PoolCreationParams memory params)
    {
        params = IDefaultCorkController.PoolCreationParams({
            pool: corkPoolManager.market(defaultPoolId),
            unwindSwapFeePercentage: 1 ether,
            swapFeePercentage: 1 ether,
            isWhitelistEnabled: false
        });
    }

    //-----------------------------------------------------------------------------------------------------//
}
