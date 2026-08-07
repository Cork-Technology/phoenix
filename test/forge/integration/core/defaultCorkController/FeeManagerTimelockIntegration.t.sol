// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DefaultCorkController} from "contracts/core/DefaultCorkController.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract FeeManagerTimelockIntegrationTest is BaseTest {
    function test_TimelockOperationalExecutesFeeUpdateThroughController() public {
        vm.warp(2);
        address[] memory proposers = new address[](1);
        proposers[0] = bravo;
        address[] memory executors = new address[](1);
        executors[0] = bravo;
        TimelockController operationalTimelock = new TimelockController(0, proposers, executors, bravo);

        defaultCorkController.grantRole(defaultCorkController.FEE_MANAGER_ROLE(), address(operationalTimelock));
        defaultCorkController.revokeRole(defaultCorkController.FEE_MANAGER_ROLE(), feeManager);

        bytes memory data =
            abi.encodeWithSelector(DefaultCorkController.updateSwapFeePercentage.selector, defaultPoolId, 2.5 ether);
        bytes32 salt = keccak256("issue-555-fee-update");
        operationalTimelock.schedule(address(defaultCorkController), 0, data, bytes32(0), salt, 0);
        bytes32 operationId =
            operationalTimelock.hashOperation(address(defaultCorkController), 0, data, bytes32(0), salt);
        vm.warp(operationalTimelock.getTimestamp(operationId) + 1);
        assertTrue(operationalTimelock.isOperationReady(operationId));
        operationalTimelock.execute(address(defaultCorkController), 0, data, bytes32(0), salt);

        assertEq(corkPoolManager.swapFee(defaultPoolId), 2.5 ether);
        assertEq(corkPoolManager.unwindSwapFee(defaultPoolId), DEFAULT_REVERSE_SWAP_FEE);
    }
}
