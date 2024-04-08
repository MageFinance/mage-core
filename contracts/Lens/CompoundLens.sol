// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.12;

import "../CErc20.sol";
import "../CToken.sol";
import "../PriceOracle.sol";
import "../EIP20Interface.sol";
import "../Governance/Comp.sol";

interface ComptrollerLensInterface {
    function markets(address) external view returns (bool, uint);
    function oracle() external view returns (PriceOracle);
    function getAccountLiquidity(address) external view returns (uint, uint, uint);
    function getAssetsIn(address) external view returns (CToken[] memory);
    function claimComp(address) external;
    function compAccrued(address) external view returns (uint);
    function compSpeeds(address) external view returns (uint);
    function compSupplySpeeds(address) external view returns (uint);
    function compBorrowSpeeds(address) external view returns (uint);
    function borrowCaps(address) external view returns (uint);
    function getAllMarkets() external view returns (CToken[] memory);
    function getAllBorrowers() external view returns (address[] memory);
    function checkMembership(address account, CToken cToken) external view returns (bool);
}

contract CompoundLens is ExponentialNoError {
    string public nativeSymbol;

    struct CTokenMetadata {
        address cToken;
        uint exchangeRateCurrent;
        uint supplyRatePerBlock;
        uint borrowRatePerBlock;
        uint reserveFactorMantissa;
        uint totalBorrows;
        uint totalReserves;
        uint totalSupply;
        uint totalCash;
        bool isListed;
        uint collateralFactorMantissa;
        address underlyingAssetAddress;
        uint cTokenDecimals;
        uint underlyingDecimals;
        uint compSupplySpeed;
        uint compBorrowSpeed;
        uint borrowCap;
    }

    constructor(string memory tokenSymbol) {
        nativeSymbol = tokenSymbol;
    }

    function getCompSpeeds(ComptrollerLensInterface comptroller, CToken cToken) internal returns (uint, uint) {
        // Getting comp speeds is gnarly due to not every network having the
        // split comp speeds from Proposal 62 and other networks don't even
        // have comp speeds.
        uint compSupplySpeed = 0;
        (bool compSupplySpeedSuccess, bytes memory compSupplySpeedReturnData) = address(comptroller).call(
            abi.encodePacked(comptroller.compSupplySpeeds.selector, abi.encode(address(cToken)))
        );
        if (compSupplySpeedSuccess) {
            compSupplySpeed = abi.decode(compSupplySpeedReturnData, (uint));
        }

        uint compBorrowSpeed = 0;
        (bool compBorrowSpeedSuccess, bytes memory compBorrowSpeedReturnData) = address(comptroller).call(
            abi.encodePacked(comptroller.compBorrowSpeeds.selector, abi.encode(address(cToken)))
        );
        if (compBorrowSpeedSuccess) {
            compBorrowSpeed = abi.decode(compBorrowSpeedReturnData, (uint));
        }

        // If the split comp speeds call doesn't work, try the  oldest non-spit version.
        if (!compSupplySpeedSuccess || !compBorrowSpeedSuccess) {
            (bool compSpeedSuccess, bytes memory compSpeedReturnData) = address(comptroller).call(abi.encodePacked(comptroller.compSpeeds.selector, abi.encode(address(cToken))));
            if (compSpeedSuccess) {
                compSupplySpeed = compBorrowSpeed = abi.decode(compSpeedReturnData, (uint));
            }
        }
        return (compSupplySpeed, compBorrowSpeed);
    }

    function cTokenMetadata(CToken cToken) public returns (CTokenMetadata memory) {
        uint exchangeRateCurrent = cToken.exchangeRateCurrent();
        ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(cToken.comptroller()));
        (bool isListed, uint collateralFactorMantissa) = comptroller.markets(address(cToken));
        address underlyingAssetAddress;
        uint underlyingDecimals;

        if (compareStrings(cToken.symbol(), nativeSymbol)) {
            underlyingAssetAddress = address(0);
            underlyingDecimals = 18;
        } else {
            CErc20 cErc20 = CErc20(address(cToken));
            underlyingAssetAddress = cErc20.underlying();
            underlyingDecimals = EIP20Interface(cErc20.underlying()).decimals();
        }

        (uint compSupplySpeed, uint compBorrowSpeed) = getCompSpeeds(comptroller, cToken);

        uint borrowCap = 0;
        (bool borrowCapSuccess, bytes memory borrowCapReturnData) = address(comptroller).call(abi.encodePacked(comptroller.borrowCaps.selector, abi.encode(address(cToken))));
        if (borrowCapSuccess) {
            borrowCap = abi.decode(borrowCapReturnData, (uint));
        }

        return
            CTokenMetadata({
                cToken: address(cToken),
                exchangeRateCurrent: exchangeRateCurrent,
                supplyRatePerBlock: cToken.supplyRatePerBlock(),
                borrowRatePerBlock: cToken.borrowRatePerBlock(),
                reserveFactorMantissa: cToken.reserveFactorMantissa(),
                totalBorrows: cToken.totalBorrows(),
                totalReserves: cToken.totalReserves(),
                totalSupply: cToken.totalSupply(),
                totalCash: cToken.getCash(),
                isListed: isListed,
                collateralFactorMantissa: collateralFactorMantissa,
                underlyingAssetAddress: underlyingAssetAddress,
                cTokenDecimals: cToken.decimals(),
                underlyingDecimals: underlyingDecimals,
                compSupplySpeed: compSupplySpeed,
                compBorrowSpeed: compBorrowSpeed,
                borrowCap: borrowCap
            });
    }

    function cTokenMetadataAll(CToken[] calldata cTokens) external returns (CTokenMetadata[] memory) {
        uint cTokenCount = cTokens.length;
        CTokenMetadata[] memory res = new CTokenMetadata[](cTokenCount);
        for (uint i = 0; i < cTokenCount; i++) {
            res[i] = cTokenMetadata(cTokens[i]);
        }
        return res;
    }

    struct CTokenBalances {
        address cToken;
        uint balanceOf;
        uint borrowBalanceCurrent;
        uint balanceOfUnderlying;
        uint tokenBalance;
        uint tokenAllowance;
    }

    function cTokenBalances(CToken cToken, address payable account) public returns (CTokenBalances memory) {
        uint balanceOf = cToken.balanceOf(account);
        uint borrowBalanceCurrent = cToken.borrowBalanceCurrent(account);
        uint balanceOfUnderlying = cToken.balanceOfUnderlying(account);
        uint tokenBalance;
        uint tokenAllowance;

        if (compareStrings(cToken.symbol(), nativeSymbol)) {
            tokenBalance = account.balance;
            tokenAllowance = account.balance;
        } else {
            CErc20 cErc20 = CErc20(address(cToken));
            EIP20Interface underlying = EIP20Interface(cErc20.underlying());
            tokenBalance = underlying.balanceOf(account);
            tokenAllowance = underlying.allowance(account, address(cToken));
        }

        return
            CTokenBalances({
                cToken: address(cToken),
                balanceOf: balanceOf,
                borrowBalanceCurrent: borrowBalanceCurrent,
                balanceOfUnderlying: balanceOfUnderlying,
                tokenBalance: tokenBalance,
                tokenAllowance: tokenAllowance
            });
    }

    function cTokenBalancesAll(CToken[] calldata cTokens, address payable account) external returns (CTokenBalances[] memory) {
        uint cTokenCount = cTokens.length;
        CTokenBalances[] memory res = new CTokenBalances[](cTokenCount);
        for (uint i = 0; i < cTokenCount; i++) {
            res[i] = cTokenBalances(cTokens[i], account);
        }
        return res;
    }

    struct CTokenUnderlyingPrice {
        address cToken;
        uint underlyingPrice;
    }

    function cTokenUnderlyingPrice(CToken cToken) public view returns (CTokenUnderlyingPrice memory) {
        ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(cToken.comptroller()));
        PriceOracle priceOracle = comptroller.oracle();

        return CTokenUnderlyingPrice({cToken: address(cToken), underlyingPrice: priceOracle.getUnderlyingPrice(cToken)});
    }

    function cTokenUnderlyingPriceAll(CToken[] calldata cTokens) external view returns (CTokenUnderlyingPrice[] memory) {
        uint cTokenCount = cTokens.length;
        CTokenUnderlyingPrice[] memory res = new CTokenUnderlyingPrice[](cTokenCount);
        for (uint i = 0; i < cTokenCount; i++) {
            res[i] = cTokenUnderlyingPrice(cTokens[i]);
        }
        return res;
    }

    struct AccountLimits {
        CToken[] markets;
        uint liquidity;
        uint shortfall;
    }

    function getAccountLimits(ComptrollerLensInterface comptroller, address account) public view returns (AccountLimits memory) {
        (uint errorCode, uint liquidity, uint shortfall) = comptroller.getAccountLiquidity(account);
        require(errorCode == 0);

        return AccountLimits({markets: comptroller.getAssetsIn(account), liquidity: liquidity, shortfall: shortfall});
    }

    struct CompBalanceMetadata {
        uint balance;
        uint votes;
        address delegate;
    }

    function getCompBalanceMetadata(Comp comp, address account) external view returns (CompBalanceMetadata memory) {
        return CompBalanceMetadata({balance: comp.balanceOf(account), votes: uint256(comp.getCurrentVotes(account)), delegate: comp.delegates(account)});
    }

    struct CompBalanceMetadataExt {
        uint balance;
        uint votes;
        address delegate;
        uint allocated;
    }

    function getCompBalanceMetadataExt(Comp comp, ComptrollerLensInterface comptroller, address account) external returns (CompBalanceMetadataExt memory) {
        uint balance = comp.balanceOf(account);
        comptroller.claimComp(account);
        uint newBalance = comp.balanceOf(account);
        uint accrued = comptroller.compAccrued(account);
        uint total = add(accrued, newBalance, "sum comp total");
        uint allocated = sub(total, balance, "sub allocated");

        return CompBalanceMetadataExt({balance: balance, votes: uint256(comp.getCurrentVotes(account)), delegate: comp.delegates(account), allocated: allocated});
    }

    struct CompVotes {
        uint blockNumber;
        uint votes;
    }

    function getCompVotes(Comp comp, address account, uint32[] calldata blockNumbers) external view returns (CompVotes[] memory) {
        CompVotes[] memory res = new CompVotes[](blockNumbers.length);
        for (uint i = 0; i < blockNumbers.length; i++) {
            res[i] = CompVotes({blockNumber: uint256(blockNumbers[i]), votes: uint256(comp.getPriorVotes(account, blockNumbers[i]))});
        }
        return res;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function add(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
        require(b <= a, errorMessage);
        uint c = a - b;
        return c;
    }

    struct Asset {
        address cToken;
        uint256 supplyBalance;
        uint256 borrowBalance;
        uint256 underlyingPrice;
        uint256 underlyingBalance;
        uint256 exchangeRate;
        uint256 collateralFactor;
    }

    struct BorrowerData {
        address account;
        Asset[] assets;
        uint256 totalSupplied;
        uint256 totalBorrowed;
        uint256 healthFactor;
        bool isLiquidatable;
    }

    struct MarketData {
        address cToken;
        uint256 underlyingPrice;
        uint256 exchangeRate;
        uint256 collateralFactor;
    }

    struct BorrowerDataLocalVars {
        uint256 supplyBalance;
        uint256 borrowBalance;
        uint256 underlyingBalance;
        uint256 healthFactor;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp tokensToDenom;
        Exp underlyingPrice;
    }

    function getAllBorrowersData(ComptrollerLensInterface comptroller) external returns (BorrowerData[] memory borrowersData) {
        PriceOracle oracle = comptroller.oracle();
        CToken[] memory markets = comptroller.getAllMarkets();
        address[] memory borrowers = comptroller.getAllBorrowers();

        uint256 marketsLength = markets.length;
        uint256[] memory collateralFactors = new uint256[](marketsLength);

        for (uint256 i = 0; i < markets.length; i++) {
            (, collateralFactors[i]) = comptroller.markets(address(markets[i]));
        }

        MarketData[] memory marketsData = new MarketData[](marketsLength);
        marketsData = getMarketsData(markets, oracle, collateralFactors);

        borrowersData = new BorrowerData[](borrowers.length);
        for (uint256 j = 0; j < borrowers.length; j++) {
            borrowersData[j] = getBorrowerData(comptroller, borrowers[j], marketsData);
        }
    }

    function getComptrollerData(
        ComptrollerLensInterface comptroller
    ) public view returns (PriceOracle oracle, CToken[] memory markets, address[] memory activeBorrowers, uint256[] memory collateralFactors) {
        oracle = comptroller.oracle();
        markets = comptroller.getAllMarkets();
        activeBorrowers = comptroller.getAllBorrowers();
        collateralFactors = new uint256[](markets.length);
        for (uint256 i = 0; i < markets.length; i++) {
            (, collateralFactors[i]) = comptroller.markets(address(markets[i]));
        }
    }

    function getMarketsData(CToken[] memory markets, PriceOracle oracle, uint256[] memory collateralFactors) public returns (MarketData[] memory marketsData) {
        marketsData = new MarketData[](markets.length);
        for (uint256 i = 0; i < markets.length; i++) {
            CErc20 cErc20 = CErc20(address(markets[i]));
            marketsData[i] = MarketData({
                cToken: address(markets[i]),
                underlyingPrice: oracle.getUnderlyingPrice(markets[i]),
                exchangeRate: cErc20.exchangeRateCurrent(),
                collateralFactor: collateralFactors[i]
            });
        }
    }

    function getBorrowersData(
        ComptrollerLensInterface comptroller,
        address[] calldata borrowers,
        MarketData[] calldata marketsData
    ) external returns (BorrowerData[] memory borrowersData) {
        uint256 borrowersLength = borrowers.length;
        borrowersData = new BorrowerData[](borrowersLength);
        for (uint256 i = 0; i < marketsData.length; i++) {
            CErc20(marketsData[i].cToken).accrueInterest();
        }
        for (uint256 j = 0; j < borrowersLength; j++) {
            borrowersData[j] = getBorrowerData(comptroller, borrowers[j], marketsData);
        }
    }

    function getBorrowerData(ComptrollerLensInterface comptroller, address borrower, MarketData[] memory marketsData) internal view returns (BorrowerData memory borrowerData) {
        uint256 sumCollaterals;
        uint256 sumBorrows;
        BorrowerDataLocalVars memory vars;
        uint256 marketsLength = marketsData.length;
        Asset[] memory borrowerAssets = new Asset[](marketsLength);

        for (uint256 i = 0; i < marketsLength; i++) {
            MarketData memory marketData = marketsData[i];
            CErc20 cErc20 = CErc20(marketData.cToken);
            vars.supplyBalance = cErc20.balanceOf(borrower);
            vars.borrowBalance = cErc20.borrowBalanceStored(borrower);

            vars.underlyingPrice = Exp({mantissa: marketData.underlyingPrice});
            vars.collateralFactor = Exp({mantissa: marketData.collateralFactor});
            vars.exchangeRate = Exp({mantissa: marketData.exchangeRate});
            vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.underlyingPrice);
            vars.underlyingBalance = mul_ScalarTruncate(vars.exchangeRate, vars.supplyBalance);

            if (ComptrollerLensInterface(comptroller).checkMembership(borrower, CToken(marketData.cToken))) {
                sumCollaterals = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.supplyBalance, sumCollaterals);
            }
            sumBorrows = mul_ScalarTruncateAddUInt(vars.underlyingPrice, vars.borrowBalance, sumBorrows);

            borrowerAssets[i] = Asset({
                cToken: marketData.cToken,
                underlyingPrice: marketData.underlyingPrice,
                exchangeRate: marketData.exchangeRate,
                collateralFactor: marketData.collateralFactor,
                supplyBalance: vars.supplyBalance,
                borrowBalance: vars.borrowBalance,
                underlyingBalance: vars.underlyingBalance
            });

            if (i == marketsLength - 1) {
                vars.healthFactor = sumBorrows > 0 ? div_((sumCollaterals * 1e18), sumBorrows) : type(uint256).max;

                borrowerData = BorrowerData({
                    account: borrower,
                    assets: borrowerAssets,
                    totalSupplied: sumCollaterals,
                    totalBorrowed: sumBorrows,
                    healthFactor: vars.healthFactor,
                    isLiquidatable: vars.healthFactor < 1e18
                });
            }
        }
    }
}
