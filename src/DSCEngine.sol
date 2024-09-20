// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author jyh
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    //   Errors      //
    ///////////////////
    error DSCEngine__NotMoreThanZero();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TokenAddressesAndPriceFeedsMustBeSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreakHealthFactor(uint256 userHealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ////////////////////////////
    //   State variables      //
    ////////////////////////////
    DecentralizedStableCoin private immutable i_dsc;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amountToken)) private s_collaterDeposited;
    mapping(address user => uint256 amountMinted) private s_dscMinted;
    address[] s_collateralAddresses;
    uint256 private constant ADDITIONAL_PRICE_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // (200% 质押/DSC 的对应阈值)
    uint256 private constant LIQUIDATION_PRECISION = 100; // (200% 质押/DSC 的对应阈值对应精度)
    uint256 private constant LIQUIDATION_BONUS = 10; // (200% 质押/DSC 的对应阈值对应精度)
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    ///////////////////
    //   Events      //
    ///////////////////
    event DSCEngine__DepositCollateral(address indexed user, address indexed tokenCollateralAddress, uint256 amount);
    event DSCEngine__RedeemCollateral(address indexed from, address indexed to, address token, uint256 amountToRedeem);

    ///////////////////
    //   Modifier    //
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NotMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////////
    //   Functions   //
    ///////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeeds, address dscAddress) {
        if (tokenAddresses.length != priceFeeds.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeeds[i];
            s_collateralAddresses.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////////////
    //   External / Public Functions  //
    ///////////////////////////
    /*
    * @param tokenCollateralAddress: the address of the token to deposit as collateral
    * @param amountCollateral: The amount of collateral to deposit
    * @param amountDscToMint: The amount of DecentralizedStableCoin to mint
    * @notice: This function will deposit your collateral and mint DSC in one transaction
    */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) public isAllowedToken(tokenCollateralAddress) moreThanZero(amountCollateral) moreThanZero(amountDscToMint) {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collaterDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit DSCEngine__DepositCollateral(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc(uint256 amountDscToBurn, address tokenCollateralAddress, uint256 amountCollateral)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral has checked health factor;
    }

    function redeemCollateral(address token, uint256 amountToRedeem)
        public
        moreThanZero(amountToRedeem)
        nonReentrant
        isAllowedToken(token)
    {
        _redeemCollateral(token, amountToRedeem, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDSCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amountToBurn) public {
        _burnDsc(amountToBurn, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
    * This is collateral that you're going to take from the user who is insolvent.
    * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
    * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
    * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
    *
    * @notice: You can partially liquidate a user.
    * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 200% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
    * For example, if the price of the collateral plummeted before anyone could be liquidated.
    */
    function liquidate(address token, address user, uint256 debtToCover) external {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(token, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalRedeemCollateral = bonusCollateral + tokenAmountFromDebtCovered;
        // IERC20(token).transfer(msg.sender, bonusCollateral + tokenAmountFromDebtCovered);
        _redeemCollateral(token, totalRedeemCollateral, user, msg.sender);

        _burnDsc(debtToCover, user, msg.sender);

        //Importantly, we're calling these low level internal calls, so we've going to want to check some `Health Factors` here.
        //If the `liquidation` somehow doesn't result in the user's `Health Factor` improving, we should revert.&#x20;
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    ///////////////////////////
    //   Internal / Private View Functions  //
    ///////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        totalDSCMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
        return (totalDSCMinted, collateralValueInUsd);
    }

    function _healthFactor(address user) private view returns (uint256) {
        // amount of DSC minted
        // total value of collateral in USDT
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        // uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // // 150 ETH / 100 DSC
        // // 150 * 50 == 7500, 7500 / 100 == 75
        // // 75 adjustETH / 100 DSC = 0.75 < 1
        // return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUsd);
    }

    function _redeemCollateral(address token, uint256 amountToRedeem, address from, address to) internal {
        s_collaterDeposited[from][token] -= amountToRedeem;
        emit DSCEngine__RedeemCollateral(from, to, token, amountToRedeem);
        bool success = IERC20(token).transfer(to, amountToRedeem);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(uint256 amountToBurn, address onBehalf, address dscFrom) internal {
        s_dscMinted[onBehalf] -= amountToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountToBurn);
    }

    // 1. check health factor (if they have enough collateral)
    // 2. revert if don't
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreakHealthFactor(userHealthFactor);
        }
    }

    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) * ADDITIONAL_PRICE_PRECISION * amount) / PRECISION;
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    ///////////////////////////
    //   External / Public View Functions  //
    ///////////////////////////
    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralInUsd) {
        for (uint256 i = 0; i < s_collateralAddresses.length; i++) {
            address token = s_collateralAddresses[i];
            uint256 amount = s_collaterDeposited[user][token];
            totalCollateralInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_PRICE_PRECISION);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        (totalDSCMinted, collateralValueInUsd) = _getAccountInformation(user);
        return (totalDSCMinted, collateralValueInUsd);
    }

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collaterDeposited[user][token];
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_PRICE_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralAddresses;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
