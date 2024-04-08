// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./BaseOracle.sol";

interface IAggregator {
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract ChainlinkOracle is BaseOracle {
    // Pyth USD-denominated feeds store answers at 8 decimals
    uint256 private constant USD_DECIMAL = 8;
    uint256 private constant DECIMAL_DELTA = 10 ** (18 - USD_DECIMAL);

    // Stores price feed of the particular token
    mapping(address => address) public priceFeeds;

    constructor(string memory tokenSymbol) BaseOracle(tokenSymbol) {}

    /**
     * @param token underlying address of cToken
     * @return price underlying price in 18 decimal places
     */
    function getOraclePrice(address token) internal view override returns (uint price) {
        (, int256 _price, , uint256 _updatedAt, ) = IAggregator(priceFeeds[token]).latestRoundData();
        if (_price <= 0 || block.timestamp < _updatedAt || block.timestamp - _updatedAt > maxDelayTime) return 0;

        price = uint256(_price) * DECIMAL_DELTA;
    }

    function updatePriceFeed(address[] memory tokens, address[] memory data) external onlyAdmin {
        for (uint256 i = 0; i < tokens.length; i++) {
            priceFeeds[tokens[i]] = data[i];
        }
    }
}
