// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice Minimal contract wallet that accepts signatures from a single owner key.
contract ERC1271WalletMock is IERC1271 {
    address public immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
        if (err == ECDSA.RecoverError.NoError && recovered == owner) {
            return this.isValidSignature.selector;
        }
        return bytes4(0);
    }
}

/// @notice Contract wallet that rejects every signature by reverting.
contract ERC1271RevertingWalletMock is IERC1271 {
    error AlwaysReverts();

    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4) {
        revert AlwaysReverts();
    }
}
