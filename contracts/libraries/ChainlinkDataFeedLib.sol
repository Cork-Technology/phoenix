// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import {MinimalAggregatorV3Interface} from "contracts/interfaces/MinimalAggregatorV3Interface.sol";

/// @title ChainlinkDataFeedLib
/// @author Cork Team
/// @custom:security-contact security@cork.tech
/// @notice Library exposing functions to interact with a Chainlink-compliant feed with robust staleness and round validation.
library ChainlinkDataFeedLib {
    uint256 internal constant MAX_ORACLE_DELAY = 86400; // 24 hours maximum oracle staleness threshold

    /// @notice Get the price of a feed.
    /// @param feed The feed to get the price from.
    /// @dev Performs robust safety checks (round validation, staleness, and positive price check) on `feed`.
    /// @dev When `feed` is the address zero, returns 1.
    /// @return The latest price of the feed.
    function getPrice(MinimalAggregatorV3Interface feed) internal view returns (uint256) {
        if (address(feed) == address(0)) return 1;

        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
        require(answer > 0, "Invalid oracle answer");
        require(updatedAt > 0 && block.timestamp - updatedAt <= MAX_ORACLE_DELAY, "Stale oracle price");
        require(answeredInRound >= roundId, "Stale oracle round");

        return uint256(answer);
    }

    /// @notice Returns the number of decimals of a `feed`.
    /// @param feed The feed to get the decimals from.
    /// @return The number of decimals of the feed.
    /// @dev When `feed` is the address zero, returns 0.
    function getDecimals(MinimalAggregatorV3Interface feed) internal view returns (uint256) {
        if (address(feed) == address(0)) return 0;

        return feed.decimals();
    }
}
