// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author jyh
 * @notice 这个库用于检查 Chainlink 预言机的数据是否过期。
 * 如果价格过期，函数将会回滚，DSCEngine 将不可用——这是设计使然。
 * 如果价格过期，我们希望 DSCEngine 冻结。
 *
 * 所以如果 Chainlink 网络崩溃，而你有大量资金锁定在协议里……很遗憾，无法取出。
 */
library OracleLib {
    error OracleLib__StalePrice(); // 自定义错误：价格过期

    uint256 private constant TIMEOUT = 3 hours; // 超时时间为 3 小时

    function staleCheckLatestRoundData(AggregatorV3Interface pricefeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            pricefeed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }

        uint256 secondsSince = block.timestamp - updatedAt; // 计算自上次更新后的秒数
        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice(); // 若价格过期，抛出错误

        return (roundId, answer, startedAt, updatedAt, answeredInRound); // 返回最新的价格数据
    }

    function getTimeout(AggregatorV3Interface /* chainlinkFeed */ ) public pure returns (uint256) {
        return TIMEOUT;
    }
}
