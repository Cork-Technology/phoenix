// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

// Compile the pinned real Safe artifacts separately from the Phoenix test harness.
// The production profile restricts this compilation unit to the legacy pipeline.
import {Safe} from "safe-contracts/Safe.sol";
import {CompatibilityFallbackHandler} from "safe-contracts/handler/CompatibilityFallbackHandler.sol";
