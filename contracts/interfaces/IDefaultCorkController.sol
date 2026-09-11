// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IErrors} from "contracts/interfaces/IErrors.sol";
import {Market, MarketId} from "contracts/interfaces/IPoolManager.sol";

//             CCCCCCCCC  C
//          CCCCCCCCCCC   C
//       CCCCCCCCCCCCCC   C
//     CCCCCCCCCCCCCCCC   C        CCCCCC                    CCCCCCCCCCCCCCC             CCCCCCCCCCCCCCC     CCCCCCCCCCCCCCCCCCCC     CCCCCCCCCCC     CCCCCCCCCC
//    CCCCCCCCCCCCCCCCC CC       CCCCCC  C               CCCCCCCCCCCCCCCCCC  CCC     CCCCCCCCCCCCCCCCCC  CC  CCCCCCCCCCCCCCCCCCCC  CC CCCCCCC   C    CCCCCCCC  CC
//   CCCCCCCCCCCCCCCC CC       CCCCCCCCC  C            CCCCCCCCCCCCCCCCCCCCC    CC CCCCCCCCCCCCCCCCCCCCCC   CCCCCCCCCCCCCCCCCCCCCCC  CCCCCCCC   C    CCCCCCCC  CC
//  CCCCCCCCCCCCCCC CC        CCCCCCCCCCC  C          CCCCCCCCCCCCCCCCCCCCCCCC    CCCCCCCCCCCCCCCCCCCCCCCC   CCCCCCCCCCCCCCCCCCCCCCC  CCCCCCC   C  CCCCCCCCCC  CC
// CCCCCCCCCCCCCC CC        CCCCCCCCCCCCC  CC        CCCCCCCCC    CC  CCCCCCCCC  CCCCCCCCC   CC   CCCCCCCCC  CCCCCCC    C   CCCCCCCC  CCCCCCC   CCCCCCCCCCC  CC
// CCCCCCCCCCCC  C         CCCCCCCCCCCCCCC  C        CCCCCCCC    CC     CCCCCCCCCCCCCCCC    CC     CCCCCCCC  CCCCCCC    C    CCCCCCC  CCCCCCC  CCCCCCCCCC  CC
// CCCCCCCCCCCC  C         CCCCCCCCCCCCCCC  C       CCCCCCCC    CC              CCCCCCCC   CC       CCCCCCCC CCCCCCC    C   CCCCCCCC  CCCCCCC  CCCCCCCC   C
// CCCCCCCCCCCC  C         CCCCCCCCCCCCCCC   C      CCCCCCCC    C               CCCCCCCC   C        CCCCCCCC CCCCCCCCCCCCCCCCCCCCCCC  CCCCCCC  CCCCCCCC   C
// CCCCCCCCCCCC  C         CCCCCCCCCCCCCCC  C       CCCCCCCC    CC              CCCCCCCC   CC       CCCCCCCC CCCCCCCCCCCCCCCCCCCCC   CCCCCCCC  CCCCCCCC   CC
// CCCCCCCCCCCC  C         CCCCCCCCCCCCCCC  C        CCCCCCCC    CC     CCCCCCCCCCCCCCCC    CC     CCCCCCCC  CCCCCCCCCCCCCCCCCCC   CC CCCCCCC  CCCCCCCCCC   C
// CCCCCCCCCCCCCC CC        CCCCCCCCCCCCC  CC        CCCCCCCCC    CCC CCCCCCCCC  CCCCCCCCC   CCC  CCCCCCCCC  CCCCCCCCCCCCCCCCCCCCC   CCCCCCCC   CCCCCCCCCCC  CC
//  CCCCCCCCCCCCCCC CC        CCCCCCCCCCC  C          CCCCCCCCCCCCCCCCCCCCCCCC   CCCCCCCCCCCCCCCCCCCCCCCCC   CCCCCCC    C CCCCCCCCCC  CCCCCCC   C  CCCCCCCCCC  CC
//   CCCCCCCCCCCCCCCC CC        CCCCCCCC  C            CCCCCCCCCCCCCCCCCCCCC    CC CCCCCCCCCCCCCCCCCCCCCC  CCCCCCCCC    C   CCCCCCCC  CCCCCCC   C    CCCCCCCC  CC
//    CCCCCCCCCCCCCCCC  CC        CCCCC CC                CCCCCCCCCCCCCCCC   CC      CCCCCCCCCCCCCCCCC  CCC  CCCCCCC    C   CCCCCCCC  CCCCCCC   C    CCCCCCCC  CC
//     CCCCCCCCCCCCCCCC   C        CCCCCC                    CCCCCCCCCCCCCCC             CCCCCCCCCCCCCC      CCCCCCCCCCCC    CCCCCCCCCCCCCCCCCCCC     CCCCCCCCCC
//       CCCCCCCCCCCCCC   C
//          CCCCCCCCCCC   C
//              CCCCCCCCCCC

/// @title IDefaultCorkController
/// @author Cork Team
/// @custom:security-contact security@cork.tech
/// @notice Interface for DefaultCorkController contract.
interface IDefaultCorkController is IErrors {
    /// @notice Emitted when a treasury is set.
    /// @param treasury Address of treasury contract/address.
    event TreasurySet(address treasury);

    /// @notice Parameters for creating a new pool.
    /// The swap and unwindSwap fees are part of `pool` (18 decimals, 1e18 = 1%). They are fixed at
    /// creation, form part of the pool id, and cannot be changed later.
    struct PoolCreationParams {
        Market pool;
        bool isWhitelistEnabled; // Is whitelist enabled for the new pool.
    }

    /// @dev Sets new treasury contract address.
    /// @param _treasury New treasury contract address.
    function setTreasury(address _treasury) external;

    /// @dev Sets new shares factory contract address.
    /// @param _sharesFactory New shares factory contract address.
    function setSharesFactory(address _sharesFactory) external;

    /// @dev Initialize cork pool.
    /// @dev The caller must hold POOL_CREATOR_ROLE and selects both fee values inside `params.pool`.
    /// @param params Parameters for the new pool.
    function createNewPool(PoolCreationParams calldata params) external;

    /// @notice Pause this contract.
    function pause() external;

    /// @notice Unpause this contract.
    function unpause() external;

    /// @notice Pauses deposits for a Cork Pool.
    function pauseDeposits(MarketId id) external;

    /// @notice Unpauses deposits for a Cork Pool.
    function unpauseDeposits(MarketId id) external;

    /// @notice Pauses unwindSwaps for a Cork Pool.
    function pauseUnwindSwaps(MarketId id) external;

    /// @notice Unpauses unwindSwaps for a Cork Pool.
    function unpauseUnwindSwaps(MarketId id) external;

    /// @notice Pauses swaps for a Cork Pool.
    function pauseSwaps(MarketId id) external;

    /// @notice Unpauses swaps for a Cork Pool.
    function unpauseSwaps(MarketId id) external;

    /// @notice Pauses withdrawals for a Cork Pool.
    function pauseWithdrawals(MarketId id) external;

    /// @notice Unpauses withdrawals for a Cork Pool.
    function unpauseWithdrawals(MarketId id) external;

    /// @notice Pauses premature withdrawals for a Cork Pool.
    function pauseUnwindDepositAndMints(MarketId id) external;

    /// @notice Unpauses premature withdrawals for a Cork Pool.
    function unpauseUnwindDepositAndMints(MarketId id) external;

    /// @notice Freeze a market, will disable ALL functionality on the given pool(swaps, withdraw, deposit, unwindExericise/mints).
    function pauseMarket(MarketId id) external;

    /// @notice Pause all markets at once.
    function pauseAll() external;

    /// @notice Pause all markets at once.
    function unpauseAll() external;

    /// @notice Checks if deposits are paused for a specific market.
    /// @param id The pool id.
    /// @return isPaused True if deposits are paused, false otherwise.
    function isDepositPaused(MarketId id) external view returns (bool isPaused);

    /// @notice Checks if swaps are paused for a specific market.
    /// @param id The pool id.
    /// @return isPaused True if swaps are paused, false otherwise.
    function isSwapPaused(MarketId id) external view returns (bool isPaused);

    /// @notice Checks if withdrawals are paused for a specific market.
    /// @param id The pool id.
    /// @return isPaused True if withdrawals are paused, false otherwise.
    function isWithdrawalPaused(MarketId id) external view returns (bool isPaused);

    /// @notice Checks if premature withdrawals are paused for a specific market.
    /// @param id The pool id.
    /// @return isPaused True if premature withdrawals are paused, false otherwise.
    function isUnwindDepositAndMintPaused(MarketId id) external view returns (bool isPaused);

    /// @notice Checks if unwind swaps are paused for a specific market.
    /// @param id The pool id.
    /// @return isPaused True if unwind swaps are paused, false otherwise.
    function isUnwindSwapPaused(MarketId id) external view returns (bool isPaused);

    ///======================================================///
    ///================= WHITELIST FUNCTIONS ===============///
    ///======================================================///

    /// @notice Disables whitelisting for a specific market (cannot be re-enabled).
    /// @param marketId The pool Id.
    function disableMarketWhitelist(MarketId marketId) external;

    /// @notice Adds accounts to the global whitelist.
    /// @param accounts Array of accounts to add.
    function addToGlobalWhitelist(address[] calldata accounts) external;

    /// @notice Removes accounts from the global whitelist.
    /// @param accounts Array of accounts to remove.
    function removeFromGlobalWhitelist(address[] calldata accounts) external;

    /// @notice Adds accounts to a market-specific whitelist.
    /// @param marketId The pool Id.
    /// @param accounts Array of accounts to add.
    function addToMarketWhitelist(MarketId marketId, address[] calldata accounts) external;

    /// @notice Removes accounts from a market-specific whitelist.
    /// @param marketId The pool Id.
    /// @param accounts Array of accounts to remove.
    function removeFromMarketWhitelist(MarketId marketId, address[] calldata accounts) external;

    /// @notice Checks if an account is whitelisted for a specific market.
    /// @param marketId The pool Id.
    /// @param account The account to check.
    /// @return True if the account is whitelisted, false otherwise.
    function isWhitelisted(MarketId marketId, address account) external view returns (bool);
}
