// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./PythOracle.sol";

import "hardhat/console.sol";

interface IPool {
    function tokenX() external view returns (IERC20);

    function tokenY() external view returns (IERC20);

    function state() external view returns (uint160 sqrtPrice_96, int24 currentPoint, uint16 observationCurrentIndex, uint16 observationQueueLen);

    function observations(uint256 index) external view returns (uint32 timestamp, int56 accPoint, bool init);

    function observe(uint32[] calldata secondsAgos) external view returns (int56[] memory accPoints);

    function expandObservationQueue(uint16 newNextQueueLen) external;
}

struct BaseToken {
    address token;
    IPool pool;
}

contract MageOracle is PythOracle {
    int24 internal constant MIN_TICK = -887272;
    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = -MIN_TICK;

    uint32 public twapInterval = 3600;

    mapping(address => BaseToken) public baseTokens;

    constructor(address pythContract, string memory tokenSymbol) PythOracle(pythContract, tokenSymbol) {}

    function setBaseToken(address token, address baseToken, IPool basePool) external onlyAdmin {
        baseTokens[token] = BaseToken(baseToken, basePool);
    }

    function setTwapInterval(uint32 value) external onlyAdmin {
        twapInterval = value;
    }

    function getOraclePrice(address token) internal view override returns (uint price) {
        BaseToken memory baseToken = baseTokens[token];
        if (baseToken.pool == IPool(address(0))) return super.getOraclePrice(token);

        uint256 baseTokenPrice = super.getOraclePrice(baseToken.token);
        uint256 twapPrice = getTwapPrice(token, baseToken.pool);
        return (twapPrice * baseTokenPrice) / 1e18;
    }

    function getTwapPrice(address token, IPool pool) public view returns (uint256) {
        (uint256 sqrtPriceX96, , uint16 index, uint16 cardinality) = pool.state();
        (uint32 targetElementTime, , bool initialized) = pool.observations((index + 1) % cardinality);
        if (!initialized) (targetElementTime, , ) = pool.observations(0);
        uint32 delta = uint32(block.timestamp) - targetElementTime;
        if (delta > 0) {
            if (delta > twapInterval) delta = twapInterval;
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = delta;
            secondsAgos[1] = 0;
            int56[] memory tickCumulatives = pool.observe(secondsAgos);
            sqrtPriceX96 = getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(delta))));
        }
        IERC20 token0 = pool.tokenX();
        IERC20 token1 = pool.tokenY();
        uint256 price = mul(mul(sqrtPriceX96, sqrtPriceX96), 10 ** token0.decimals()) >> 192;
        if (price == 0) return 0;

        price = mul(price, 1e18) / (10 ** token1.decimals());
        return (token == address(token0)) ? price : 1e36 / price;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) private pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return 0;

        uint256 c = a * b;
        if (c / a == b) return c;

        return 0;
    }

    /// @notice Calculates sqrt(1.0001^tick) * 2^96
    /// @dev Throws if |tick| > max tick
    /// @param tick The input tick for the above formula
    /// @return sqrtPriceX96 A Fixed point Q64.96 number representing the sqrt of the ratio of the two assets (token1/token0)
    /// at the given tick
    function getSqrtRatioAtTick(int24 tick) private pure returns (uint160 sqrtPriceX96) {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= uint256(int256(MAX_TICK)), "T");

        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        // this divides by 1<<32 rounding up to go from a Q128.128 to a Q128.96.
        // we then downcast because we know the result always fits within 160 bits due to our tick input constraint
        // we round up in the division so getTickAtSqrtRatio of the output price is always consistent
        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }
}
