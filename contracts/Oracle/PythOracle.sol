// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./BaseOracle.sol";

struct Price {
    // Price
    int64 price;
    // Confidence interval around the price
    uint64 conf;
    // Price exponent
    int32 expo;
    // Unix timestamp describing when the price was published
    uint publishTime;
}

interface IPyth {
    function getPriceUnsafe(bytes32 id) external view returns (Price memory);
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint feeAmount);
    function updatePriceFeeds(bytes[] calldata updateData) external payable;
}

contract PythOracle is BaseOracle {
    IPyth public immutable pyth;

    uint256 private constant USD_DECIMAL = 8;
    uint256 private constant DECIMAL_DELTA = 10 ** (18 - USD_DECIMAL);

    // Stores price feed of the particular token
    mapping(address => bytes32) public priceFeeds;

    constructor(address pythContract, string memory tokenSymbol) BaseOracle(tokenSymbol) {
        pyth = IPyth(pythContract);
    }

    /**
     * @param token underlying address of cToken
     * @return price underlying price in 18 decimal places
     */
    function getOraclePrice(address token) internal view virtual override returns (uint price) {
        Price memory _price = pyth.getPriceUnsafe(priceFeeds[token]);
        if (_price.price < 0 || _price.expo > 0 || _price.expo < -255) return 0;
        if (block.timestamp < _price.publishTime || block.timestamp - _price.publishTime > maxDelayTime) return 0;

        price = uint(uint64(_price.price)) * DECIMAL_DELTA;
    }

    function updatePriceFeed(address[] memory tokens, bytes[] memory data) external onlyAdmin {
        for (uint i = 0; i < tokens.length; i++) {
            priceFeeds[tokens[i]] = bytes32(data[i]);
        }
    }
}
