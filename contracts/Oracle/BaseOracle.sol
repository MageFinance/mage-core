// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./HomoraMath.sol";

interface IERC20 {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
}

interface ISwapPair is IERC20 {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint, uint);
}

interface Token is IERC20 {
    function underlying() external view returns (address);
}

contract BaseOracle {
    string public nativeSymbol;
    address public admin;
    address public keeper;
    uint256 public maxDelayTime;

    bool public constant isPriceOracle = true;

    address internal constant NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    mapping(address => uint) public directPrices;

    constructor(string memory tokenSymbol) {
        nativeSymbol = tokenSymbol;
        admin = msg.sender;
        keeper = msg.sender;
    }

    /**
     * @dev returns price of cToken underlying
     * @param cToken address of the cToken
     * @return scaled price of the underlying
     */
    function getUnderlyingPrice(Token cToken) external view returns (uint) {
        string memory symbol = cToken.symbol();
        if (compareStrings(symbol, nativeSymbol)) {
            return getOraclePrice(NATIVE_ADDRESS);
        } else {
            return getPrice(cToken);
        }
    }

    /**
     * @dev returns price of token
     * @param cToken address of the cToken
     * @return price scaled price of the token
     */
    function getPrice(Token cToken) public view returns (uint price) {
        address token = cToken.underlying();

        price = getPriceByToken(token);
    }

    /**
     * @param token underlying address of cToken
     * @return price underlying price in 18 decimal places
     */
    function getOraclePrice(address token) internal view virtual returns (uint price) {
        price = directPrices[token];

        uint decimalDelta = uint(18) - IERC20(token).decimals();
        // Ensure that we don't multiply the result by 0
        if (decimalDelta > 0) {
            price = price * (10 ** decimalDelta);
        }
    }

    /**
     * @dev set price of the token directly, only in case if there is no feed
     * @param token address of the underlying token
     * @param price underlying price in 18 decimal places
     */
    function setDirectPrice(address token, uint price) external onlyAdmin {
        directPrices[token] = price;
    }

    function updateAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function updateLPPrice(address[] calldata pairs) external {
        require(msg.sender == keeper, "only keeper may call");
        for (uint i = 0; i < pairs.length; i++) {
            address pair = pairs[i];
            uint price = getFairLPPrice(ISwapPair(pair));
            directPrices[pair] = price;
        }
    }

    function getFairLPPrice(ISwapPair pair) public view returns (uint price) {
        address token0 = pair.token0();
        address token1 = pair.token1();
        uint totalSupply = pair.totalSupply();
        (uint r0, uint r1) = pair.getReserves();
        uint sqrtK = HomoraMath.sqrt(r0 * r1);
        uint px0 = getPriceByToken(token0);
        uint px1 = getPriceByToken(token1);
        return (sqrtK * 2 * HomoraMath.sqrt(px0 * px1)) / totalSupply;
    }

    function getPriceByToken(address token) public view returns (uint price) {
        uint directPrice = directPrices[token];
        if (directPrice > 0) {
            price = directPrice;
        } else {
            price = getOraclePrice(token);
        }

        uint decimalDelta = uint(18) - IERC20(token).decimals();
        // Ensure that we don't multiply the result by 0
        if (decimalDelta > 0) {
            price = price * (10 ** decimalDelta);
        }
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin may call");
        _;
    }

    function setKeeper(address _keeper) external onlyAdmin {
        keeper = _keeper;
    }

    function setMaxDelayTime(uint256 time) external onlyAdmin {
        maxDelayTime = time;
    }
}
