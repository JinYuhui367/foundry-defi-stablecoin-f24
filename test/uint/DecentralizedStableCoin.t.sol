// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelpConfig} from "../../script/HelpConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelpConfig config;
    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MAX_STARTING_ERC20_BALANCE = 100 ether;
    uint256 constant INITIAL_DSC_MINT = 100 ether;
    uint256 constant COLLATERAL_PRICE = 2000 ether; // $2
    uint256 constant PRECISION = 1e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    address[] tokenAddresses;
    address[] priceFeeds;

    function testConstructor() public {
        tokenAddresses.push(ethUsdPriceFeed);
        tokenAddresses.push(btcUsdPriceFeed);
        priceFeeds.push(weth);
        // priceFeeds.push(wbtc);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedsMustBeSameLength.selector);
        // length diff
        new DSCEngine(tokenAddresses, priceFeeds, address(dsc));
    }

    /////////////////
    // Price Tests //
    /////////////////

    function testGetUsdValue() public view {
        // 15e18 * 2,000/ETH = 30,000e18
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectWethAmount = 0.05 ether;
        uint256 actualWethAmount = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectWethAmount, actualWethAmount);
    }

    /////////////////////////////
    // depositCollateral Tests //
    /////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert();
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCollateralMoreThanZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        dsce.depositCollateral(weth, 2e18);
        console.log("USER's collateral in USD: ", dsce.getAccountCollateralValueInUsd(USER));
        vm.stopPrank();
    }

    function testRedeemWithUnapprovedToken() public {
        ERC20Mock unapprovedToken = new ERC20Mock();
        // ERC20Mock(address(unapprovedToken)).mint(USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(unapprovedToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////
    // modifier  //
    ///////////////
    modifier deposited() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier approved() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier setLiquidator() {
        ERC20Mock(weth).mint(LIQUIDATOR, MAX_STARTING_ERC20_BALANCE);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), MAX_STARTING_ERC20_BALANCE);
        vm.stopPrank();
        _;
    }

    function testDeopsiteAndGetAccountInformation() public deposited {
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectDCSMinted = 0;
        uint256 expectCollteralAmount = AMOUNT_COLLATERAL;
        uint256 actualCollteralAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDSCMinted, expectDCSMinted);
        assertEq(actualCollteralAmount, expectCollteralAmount);
    }

    ///////////////////
    // ChatGPT Tests //
    ///////////////////

    function testDepositCollateralAndMintDsc() public approved {
        vm.prank(USER);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, INITIAL_DSC_MINT);

        // 验证抵押金存入 2000$ / eth
        // 10 eth AMOUNT_COLLATERAL == 20,000 $
        // 100 dsc INITIAL_DSC_MINT == 100 $
        assertEq(dsce.getAccountCollateralValueInUsd(USER), AMOUNT_COLLATERAL * COLLATERAL_PRICE / PRECISION);
        // 验证 DSC 已铸造
        assertEq(dsc.balanceOf(USER), INITIAL_DSC_MINT);
    }

    function testRedeemCollateral() public approved {
        vm.prank(USER);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, INITIAL_DSC_MINT);

        // 用户赎回一部分抵押品
        uint256 amountToRedeem = 2 ether;
        vm.prank(USER);
        dsce.redeemCollateral(address(weth), amountToRedeem);

        // 验证抵押品被赎回
        assertEq(ERC20Mock(weth).balanceOf(USER), amountToRedeem);
    }

    // function testLiquidate() public approved setLiquidator {
    //     // 设置用户的健康因子低于阈值
    //     vm.prank(USER);
    //     dsce.depositCollateralAndMintDsc(address(weth), 0.1 ether, 150 ether);
    //     // deposited 0.1 eth == 200 $
    //     // minted 150 dsc == 150 $
    //     // 200 / 150 == 133%

    //     // 计算清算所需的 DSC
    //     uint256 debtToCover = 150 ether;

    //     // 为清算者提供 DSC
    //     vm.prank(LIQUIDATOR); // 变更调用者为测试合约
    //     dsce.depositCollateralAndMintDsc(weth, 10 ether, 10 ether);
    //     dsc.approve(address(dsce), debtToCover);

    //     // 尝试清算用户
    //     vm.prank(LIQUIDATOR);
    //     dsce.liquidate(address(weth), USER, debtToCover);

    //     // 验证用户的 DSC 被销毁
    //     assertEq(dsc.balanceOf(USER), 0);
    //     // 验证清算者的 DSC 被转移
    //     // assertEq(dsc.balanceOf(address(this)), debtToCover);
    // }

    // function testHealthFactor() public {
    //     // 设置用户的健康因子
    //     vm.prank(USER);
    //     dsce.depositCollateralAndMintDsc(address(weth), AMOUNT_COLLATERAL, INITIAL_DSC_MINT);

    //     // 验证用户的健康因子
    //     uint256 healthFactor = dsce.getHealthFactor();
    //     assert(healthFactor < 1e18); // 假设健康因子 < 1 表示健康因子不合格
    // }

    function testDepositZeroCollateral() public {
        vm.prank(USER);
        // 尝试存入零的抵押品，应该会失败
        vm.expectRevert(DSCEngine.DSCEngine__NotMoreThanZero.selector);
        dsce.depositCollateral(address(weth), 0);
    }

    function testTransferFailed() public {
        // 测试转账失败的情况
        // 在这里我们需要模拟 IERC20 的转账失败，可以通过重写 MockToken 来实现
        // 这部分需要实现一个新的 MockToken，返回 false
    }
}
