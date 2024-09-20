// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
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
        dsce.depositCollateral(collateral, amountToDeposite);
        vm.stopPrank();
    }
}
