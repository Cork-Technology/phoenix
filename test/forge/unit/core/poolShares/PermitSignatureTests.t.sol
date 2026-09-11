// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {PoolShare} from "contracts/core/assets/PoolShare.sol";
import {IErrors} from "contracts/interfaces/IErrors.sol";
import {SafeProxyFactory} from "safe-contracts/proxies/SafeProxyFactory.sol";
import {BaseTest} from "test/forge/BaseTest.sol";
import {ERC1271RevertingWalletMock, ERC1271WalletMock} from "test/forge/mocks/ERC1271WalletMock.sol";

/// @dev ABI-only boundary keeps the real Safe fixture outside Phoenix's via-IR compilation unit.
interface ISafePermitFixture {
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
}

interface ISafePermitHandler {
    function getMessageHashForSafe(ISafePermitFixture safe, bytes calldata message) external view returns (bytes32);
}

contract PoolSharePermitSignatureTests is BaseTest {
    uint256 private constant SAFE_OWNER_KEY = 0x5AFE1;
    uint256 private constant SAFE_OWNER_2_KEY = 0x5AFE2;
    uint256 private constant STRANGER_KEY = 0xBAD;
    uint256 private constant PERMIT_VALUE = 4.25 ether;

    ISafePermitFixture private singleton;
    SafeProxyFactory private factory;
    ISafePermitHandler private handler;
    uint256 private saltNonce;

    function setUp() public override {
        super.setUp();
        singleton = ISafePermitFixture(deployCode(_fixtureArtifact("Safe.sol/Safe.json")));
        factory = new SafeProxyFactory();
        handler = ISafePermitHandler(
            deployCode(_fixtureArtifact("CompatibilityFallbackHandler.sol/CompatibilityFallbackHandler.json"))
        );
    }

    /// @dev Foundry 1.4.4 name lookup excludes other compiler profiles. Resolve JSON
    /// relative to this running test artifact so custom output directories also work.
    function _fixtureArtifact(string memory relativePath) internal view returns (string memory) {
        bytes memory directory = bytes(vm.getArtifactPathByDeployedCode(address(this).code));
        uint256 separators;
        for (uint256 i = directory.length; i > 0; --i) {
            if (directory[i - 1] == bytes1("/") && ++separators == 2) {
                assembly ("memory-safe") { mstore(directory, i) }
                return string.concat(string(directory), relativePath);
            }
        }
        revert("Missing test artifact directory");
    }

    //------------------------------------------------- EOA -------------------------------------------------//

    function test_PermitBytes_EoaSignatureSetsAllowanceAndConsumesNonce() external {
        address tokenOwner = vm.addr(SAFE_OWNER_KEY);
        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig = _sign(SAFE_OWNER_KEY, _digest(swapToken, tokenOwner, eve, PERMIT_VALUE, deadline));

        swapToken.permit(tokenOwner, eve, PERMIT_VALUE, deadline, sig);

        assertEq(swapToken.allowance(tokenOwner, eve), PERMIT_VALUE);
        assertEq(swapToken.nonces(tokenOwner), 1);
    }

    function test_PermitBytes_WrongSignerReverts() external {
        address tokenOwner = vm.addr(SAFE_OWNER_KEY);
        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig = _sign(STRANGER_KEY, _digest(swapToken, tokenOwner, eve, PERMIT_VALUE, deadline));

        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidPermitSignature.selector, tokenOwner));
        swapToken.permit(tokenOwner, eve, PERMIT_VALUE, deadline, sig);

        assertEq(swapToken.allowance(tokenOwner, eve), 0);
        assertEq(swapToken.nonces(tokenOwner), 0);
    }

    function test_PermitBytes_ExpiredDeadlineReverts() external {
        address tokenOwner = vm.addr(SAFE_OWNER_KEY);
        uint256 deadline = block.timestamp - 1;
        bytes memory sig = _sign(SAFE_OWNER_KEY, _digest(swapToken, tokenOwner, eve, PERMIT_VALUE, deadline));

        vm.expectRevert(abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612ExpiredSignature.selector, deadline));
        swapToken.permit(tokenOwner, eve, PERMIT_VALUE, deadline, sig);

        assertEq(swapToken.allowance(tokenOwner, eve), 0);
        assertEq(swapToken.nonces(tokenOwner), 0);
    }

    function test_PermitBytes_ZeroOwnerReverts() external {
        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig = _sign(SAFE_OWNER_KEY, _digest(swapToken, address(0), eve, PERMIT_VALUE, deadline));

        vm.expectRevert(IErrors.ZeroAddress.selector);
        swapToken.permit(address(0), eve, PERMIT_VALUE, deadline, sig);

        assertEq(swapToken.nonces(address(0)), 0);
    }

    function test_PermitBytes_MalformedSignatureReverts() external {
        address tokenOwner = vm.addr(SAFE_OWNER_KEY);
        uint256 deadline = block.timestamp + 30 days;
        (, bytes32 r, bytes32 s) = vm.sign(SAFE_OWNER_KEY, _digest(swapToken, tokenOwner, eve, PERMIT_VALUE, deadline));
        bytes memory sig = abi.encodePacked(r, s);

        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidPermitSignature.selector, tokenOwner));
        swapToken.permit(tokenOwner, eve, PERMIT_VALUE, deadline, sig);

        assertEq(swapToken.allowance(tokenOwner, eve), 0);
        assertEq(swapToken.nonces(tokenOwner), 0);
    }

    function test_PermitBytes_ReplayReverts() external {
        address tokenOwner = vm.addr(SAFE_OWNER_KEY);
        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig = _sign(SAFE_OWNER_KEY, _digest(swapToken, tokenOwner, eve, PERMIT_VALUE, deadline));

        swapToken.permit(tokenOwner, eve, PERMIT_VALUE, deadline, sig);

        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidPermitSignature.selector, tokenOwner));
        swapToken.permit(tokenOwner, eve, PERMIT_VALUE, deadline, sig);

        assertEq(swapToken.allowance(tokenOwner, eve), PERMIT_VALUE);
        assertEq(swapToken.nonces(tokenOwner), 1);
    }

    function test_PermitBytes_SharesNonceWithVrsPermit() external {
        address tokenOwner = vm.addr(SAFE_OWNER_KEY);
        uint256 deadline = block.timestamp + 30 days;

        bytes32 digestNonce0 = _digest(swapToken, tokenOwner, eve, PERMIT_VALUE, deadline);
        swapToken.permit(tokenOwner, eve, PERMIT_VALUE, deadline, _sign(SAFE_OWNER_KEY, digestNonce0));
        assertEq(swapToken.nonces(tokenOwner), 1);

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(SAFE_OWNER_KEY, _digest(swapToken, tokenOwner, eve, PERMIT_VALUE + 1, deadline));
        swapToken.permit(tokenOwner, eve, PERMIT_VALUE + 1, deadline, v, r, s);
        assertEq(swapToken.nonces(tokenOwner), 2);
        assertEq(swapToken.allowance(tokenOwner, eve), PERMIT_VALUE + 1);

        (v, r, s) = vm.sign(SAFE_OWNER_KEY, digestNonce0);
        vm.expectPartialRevert(ERC20PermitUpgradeable.ERC2612InvalidSigner.selector);
        swapToken.permit(tokenOwner, eve, PERMIT_VALUE, deadline, v, r, s);
        assertEq(swapToken.nonces(tokenOwner), 2);
        assertEq(swapToken.allowance(tokenOwner, eve), PERMIT_VALUE + 1);
    }

    function test_PermitBytes_CrossCloneReplayReverts() external {
        address tokenOwner = vm.addr(SAFE_OWNER_KEY);
        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig = _sign(SAFE_OWNER_KEY, _digest(principalToken, tokenOwner, eve, PERMIT_VALUE, deadline));

        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidPermitSignature.selector, tokenOwner));
        swapToken.permit(tokenOwner, eve, PERMIT_VALUE, deadline, sig);

        assertEq(swapToken.allowance(tokenOwner, eve), 0);
        assertEq(principalToken.nonces(tokenOwner), 0);
        assertEq(swapToken.nonces(tokenOwner), 0);
    }

    //------------------------------------------- Mock contract wallet -------------------------------------------//

    function test_PermitBytes_Erc1271WalletSetsAllowance() external {
        address wallet = address(new ERC1271WalletMock(vm.addr(SAFE_OWNER_KEY)));
        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig = _sign(SAFE_OWNER_KEY, _digest(swapToken, wallet, eve, PERMIT_VALUE, deadline));

        swapToken.permit(wallet, eve, PERMIT_VALUE, deadline, sig);

        assertEq(swapToken.allowance(wallet, eve), PERMIT_VALUE);
        assertEq(swapToken.nonces(wallet), 1);
    }

    function test_PermitBytes_Erc1271WalletWrongSignerReverts() external {
        address wallet = address(new ERC1271WalletMock(vm.addr(SAFE_OWNER_KEY)));
        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig = _sign(STRANGER_KEY, _digest(swapToken, wallet, eve, PERMIT_VALUE, deadline));

        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidPermitSignature.selector, wallet));
        swapToken.permit(wallet, eve, PERMIT_VALUE, deadline, sig);

        assertEq(swapToken.allowance(wallet, eve), 0);
        assertEq(swapToken.nonces(wallet), 0);
    }

    function test_PermitBytes_Erc1271RevertingWalletReverts() external {
        address wallet = address(new ERC1271RevertingWalletMock());
        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig = _sign(SAFE_OWNER_KEY, _digest(swapToken, wallet, eve, PERMIT_VALUE, deadline));

        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidPermitSignature.selector, wallet));
        swapToken.permit(wallet, eve, PERMIT_VALUE, deadline, sig);

        assertEq(swapToken.allowance(wallet, eve), 0);
        assertEq(swapToken.nonces(wallet), 0);
    }

    //------------------------------------------------- Safe -------------------------------------------------//

    function test_PermitBytes_SafeOwnerSignatureSetsAllowance() external {
        ISafePermitFixture safe = _deploySafe(_owners(SAFE_OWNER_KEY), 1);
        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig =
            _safeSign(safe, _keys(SAFE_OWNER_KEY), _digest(principalToken, address(safe), eve, PERMIT_VALUE, deadline));

        principalToken.permit(address(safe), eve, PERMIT_VALUE, deadline, sig);

        assertEq(principalToken.allowance(address(safe), eve), PERMIT_VALUE);
        assertEq(principalToken.nonces(address(safe)), 1);
    }

    function test_PermitBytes_SafeSignatureFromNonOwnerReverts() external {
        ISafePermitFixture safe = _deploySafe(_owners(SAFE_OWNER_KEY), 1);
        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig =
            _safeSign(safe, _keys(STRANGER_KEY), _digest(principalToken, address(safe), eve, PERMIT_VALUE, deadline));

        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidPermitSignature.selector, address(safe)));
        principalToken.permit(address(safe), eve, PERMIT_VALUE, deadline, sig);

        assertEq(principalToken.allowance(address(safe), eve), 0);
        assertEq(principalToken.nonces(address(safe)), 0);
    }

    function test_PermitBytes_SafeRawDigestSignatureReverts() external {
        ISafePermitFixture safe = _deploySafe(_owners(SAFE_OWNER_KEY), 1);
        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig = _sign(SAFE_OWNER_KEY, _digest(principalToken, address(safe), eve, PERMIT_VALUE, deadline));

        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidPermitSignature.selector, address(safe)));
        principalToken.permit(address(safe), eve, PERMIT_VALUE, deadline, sig);

        assertEq(principalToken.allowance(address(safe), eve), 0);
        assertEq(principalToken.nonces(address(safe)), 0);
    }

    function test_PermitBytes_SafeTwoOfTwoRequiresBothOwners() external {
        ISafePermitFixture safe = _deploySafe(_owners(SAFE_OWNER_KEY, SAFE_OWNER_2_KEY), 2);
        uint256 deadline = block.timestamp + 30 days;

        bytes memory sig = _safeSign(
            safe,
            _keys(SAFE_OWNER_KEY, SAFE_OWNER_2_KEY),
            _digest(principalToken, address(safe), eve, PERMIT_VALUE, deadline)
        );
        principalToken.permit(address(safe), eve, PERMIT_VALUE, deadline, sig);
        assertEq(principalToken.allowance(address(safe), eve), PERMIT_VALUE);
        assertEq(principalToken.nonces(address(safe)), 1);

        sig = _safeSign(
            safe, _keys(SAFE_OWNER_KEY), _digest(principalToken, address(safe), eve, PERMIT_VALUE + 1, deadline)
        );
        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidPermitSignature.selector, address(safe)));
        principalToken.permit(address(safe), eve, PERMIT_VALUE + 1, deadline, sig);
        assertEq(principalToken.allowance(address(safe), eve), PERMIT_VALUE);
        assertEq(principalToken.nonces(address(safe)), 1);
    }

    function test_PermitBytes_SafePermitThenSpenderTransfersFrom() external {
        ISafePermitFixture safe = _deploySafe(_owners(SAFE_OWNER_KEY), 1);
        vm.startPrank(address(corkPoolManager));
        principalToken.mint(address(safe), PERMIT_VALUE);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig =
            _safeSign(safe, _keys(SAFE_OWNER_KEY), _digest(principalToken, address(safe), eve, PERMIT_VALUE, deadline));
        principalToken.permit(address(safe), eve, PERMIT_VALUE, deadline, sig);

        vm.startPrank(eve);
        principalToken.transferFrom(address(safe), eve, PERMIT_VALUE);
        vm.stopPrank();

        assertEq(principalToken.balanceOf(address(safe)), 0);
        assertEq(principalToken.balanceOf(eve), PERMIT_VALUE);
        assertEq(principalToken.allowance(address(safe), eve), 0);
        assertEq(principalToken.nonces(address(safe)), 1);
    }

    function test_PermitBytes_SafeSignatureOnOtherCloneReverts() external {
        ISafePermitFixture safe = _deploySafe(_owners(SAFE_OWNER_KEY), 1);
        uint256 deadline = block.timestamp + 30 days;
        bytes memory sig =
            _safeSign(safe, _keys(SAFE_OWNER_KEY), _digest(principalToken, address(safe), eve, PERMIT_VALUE, deadline));

        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidPermitSignature.selector, address(safe)));
        swapToken.permit(address(safe), eve, PERMIT_VALUE, deadline, sig);

        assertEq(swapToken.allowance(address(safe), eve), 0);
        assertEq(swapToken.nonces(address(safe)), 0);
        assertEq(principalToken.nonces(address(safe)), 0);
    }

    //------------------------------------------------- Helpers -------------------------------------------------//

    function _digest(PoolShare token, address tokenOwner, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        Permit memory permitData = Permit({
            owner: tokenOwner, spender: spender, value: value, nonce: token.nonces(tokenOwner), deadline: deadline
        });
        return getTypedDataHash(permitData, token.DOMAIN_SEPARATOR());
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _deploySafe(address[] memory owners, uint256 threshold) internal returns (ISafePermitFixture) {
        bytes memory initializer = abi.encodeCall(
            ISafePermitFixture.setup,
            (owners, threshold, address(0), "", address(handler), address(0), 0, payable(address(0)))
        );
        return ISafePermitFixture(
            payable(address(factory.createProxyWithNonce(address(singleton), initializer, saltNonce++)))
        );
    }

    /// @dev Safe validates owner signatures over its own SafeMessage wrapper of the permit digest.
    function _safeSign(ISafePermitFixture safe, uint256[] memory pks, bytes32 digest)
        internal
        view
        returns (bytes memory sig)
    {
        bytes32 safeDigest = handler.getMessageHashForSafe(safe, abi.encode(digest));
        uint256[] memory sorted = _sortByAddress(pks);
        for (uint256 i = 0; i < sorted.length; i++) {
            sig = bytes.concat(sig, _sign(sorted[i], safeDigest));
        }
    }

    function _sortByAddress(uint256[] memory pks) internal pure returns (uint256[] memory) {
        for (uint256 i = 1; i < pks.length; i++) {
            for (uint256 j = i; j > 0 && vm.addr(pks[j - 1]) > vm.addr(pks[j]); j--) {
                (pks[j - 1], pks[j]) = (pks[j], pks[j - 1]);
            }
        }
        return pks;
    }

    function _owners(uint256 pk) internal pure returns (address[] memory owners) {
        owners = new address[](1);
        owners[0] = vm.addr(pk);
    }

    function _owners(uint256 pk1, uint256 pk2) internal pure returns (address[] memory owners) {
        owners = new address[](2);
        owners[0] = vm.addr(pk1);
        owners[1] = vm.addr(pk2);
    }

    function _keys(uint256 pk) internal pure returns (uint256[] memory keys) {
        keys = new uint256[](1);
        keys[0] = pk;
    }

    function _keys(uint256 pk1, uint256 pk2) internal pure returns (uint256[] memory keys) {
        keys = new uint256[](2);
        keys[0] = pk1;
        keys[1] = pk2;
    }
}
