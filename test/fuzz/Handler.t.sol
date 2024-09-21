// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelpConfig} from "../../script/HelpConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dsce;

    address weth;
    address wbtc;
    address[] usersWithCollateralMinted;
    uint256 public timesMintIsCalles = 0;
    uint256 constant MAX_DEPOSIT = type(uint96).max;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        dsce = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = collateralTokens[0];
        wbtc = collateralTokens[1];
    }

    function setUp() external {}

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (address) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountToDeposite) public {
        address collateral = _getCollateralFromSeed(collateralSeed);
        amountToDeposite = bound(amountToDeposite, 1, MAX_DEPOSIT);

        vm.startPrank(msg.sender);
        ERC20Mock(weth).mint(address(msg.sender), amountToDeposite);
        ERC20Mock(wbtc).mint(address(msg.sender), amountToDeposite);
        ERC20Mock(weth).approve(address(dsce), amountToDeposite);
        ERC20Mock(wbtc).approve(address(dsce), amountToDeposite);

        console.log("1 amountToDeposite: ", amountToDeposite);
        dsce.depositCollateral(collateral, amountToDeposite);
        usersWithCollateralMinted.push(msg.sender);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountToRedeem, uint256 userSeed) public {
        if (usersWithCollateralMinted.length == 0) {
            return;
        }
        address sender = usersWithCollateralMinted[userSeed % usersWithCollateralMinted.length];
        // TODO: 这里没有prank的话，dsce.redeemCollateral(collateral, amountToRedeem)传入的from地址为address(this),导致余额为0！！！
        vm.startPrank(sender);
        address collateral = _getCollateralFromSeed(collateralSeed);
        uint256 totalBalanceCollaterral = dsce.getCollateralBalanceOfUser(sender, collateral);
        amountToRedeem = bound(amountToRedeem, 0, totalBalanceCollaterral);
        if (amountToRedeem == 0) {
            return;
        }
        // console.log("totalBalanceCollaterral: ", totalBalanceCollaterral);
        console.log("3 amountToRedeem: ", amountToRedeem);
        // console.log("msg.sender: ", msg.sender);
        dsce.redeemCollateral(collateral, amountToRedeem);
        vm.stopPrank();
    }

    function mintDsc(uint256 amountToMint, uint256 userSeed) public {
        if (usersWithCollateralMinted.length == 0) {
            return;
        }
        address sender = usersWithCollateralMinted[userSeed % usersWithCollateralMinted.length];
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);

        int256 maxAmountToMint = (int256(collateralValueInUsd / 2) - int256(totalDSCMinted));

        if (maxAmountToMint < 0) {
            return;
        }

        amountToMint = bound(amountToMint, 0, uint256(maxAmountToMint));
        if (amountToMint == 0) {
            return;
        }
        vm.startPrank(sender);
        console.log("2 amountToMint: ", amountToMint);
        dsce.mintDsc(amountToMint);
        vm.stopPrank();
        timesMintIsCalles++;
        console.log("** mint times: ", timesMintIsCalles);
    }
}
