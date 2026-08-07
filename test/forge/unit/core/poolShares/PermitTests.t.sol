// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {BaseTest} from "test/forge/BaseTest.sol";

contract PoolSharePermitTests is BaseTest {
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    uint256 private constant OWNER_PRIVATE_KEY = 0xA11CE;
    uint256 private constant PERMIT_VALUE = 4.25 ether;

    function test_Permit_DomainUsesCloneNameAndVerifyingContract() external view {
        _assertDomain(principalToken);
        _assertDomain(swapToken);
        assertNotEq(principalToken.DOMAIN_SEPARATOR(), swapToken.DOMAIN_SEPARATOR());
    }

    function test_Permit_ValidSignatureSetsAllowanceAndConsumesNonce() external {
        address tokenOwner = vm.addr(OWNER_PRIVATE_KEY);
        uint256 deadline = block.timestamp + 30 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(swapToken, tokenOwner, eve, PERMIT_VALUE, deadline);
        swapToken.permit(tokenOwner, eve, PERMIT_VALUE, deadline, v, r, s);
        assertEq(swapToken.allowance(tokenOwner, eve), PERMIT_VALUE);
        assertEq(swapToken.nonces(tokenOwner), 1);
    }

    function test_Permit_CrossVariantReplayFailsWithoutMutatingEitherNonce() external {
        address tokenOwner = vm.addr(OWNER_PRIVATE_KEY);
        uint256 deadline = block.timestamp + 30 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(principalToken, tokenOwner, eve, PERMIT_VALUE, deadline);
        vm.expectRevert();
        swapToken.permit(tokenOwner, eve, PERMIT_VALUE, deadline, v, r, s);
        assertEq(principalToken.nonces(tokenOwner), 0);
        assertEq(swapToken.nonces(tokenOwner), 0);
    }

    function test_Permit_CloneSignatureFailsOnImplementationWithoutMutation() external {
        PoolShare implementation = PoolShare(sharesFactory.POOL_SHARE_IMPLEMENTATION());
        address tokenOwner = vm.addr(OWNER_PRIVATE_KEY);
        uint256 deadline = block.timestamp + 30 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(principalToken, tokenOwner, eve, PERMIT_VALUE, deadline);
        vm.expectRevert();
        implementation.permit(tokenOwner, eve, PERMIT_VALUE, deadline, v, r, s);
        assertEq(implementation.nonces(tokenOwner), 0);
        assertEq(implementation.allowance(tokenOwner, eve), 0);
        assertEq(principalToken.nonces(tokenOwner), 0);
    }

    function _assertDomain(PoolShare token) internal view {
        (bytes1 fields, string memory domainName, string memory version, uint256 chainId, address verifyingContract,,) =
            token.eip712Domain();
        bytes32 expectedSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(token.name())),
                keccak256(bytes("1")),
                block.chainid,
                address(token)
            )
        );
        assertEq(uint8(fields), uint8(0x0f));
        assertEq(domainName, token.name());
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(token));
        assertEq(token.DOMAIN_SEPARATOR(), expectedSeparator);
    }

    function _signPermit(PoolShare token, address tokenOwner, address spender, uint256 value, uint256 deadline)
        internal
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        Permit memory permitData = Permit({
            owner: tokenOwner, spender: spender, value: value, nonce: token.nonces(tokenOwner), deadline: deadline
        });
        (v, r, s) = vm.sign(OWNER_PRIVATE_KEY, getTypedDataHash(permitData, token.DOMAIN_SEPARATOR()));
    }
}
