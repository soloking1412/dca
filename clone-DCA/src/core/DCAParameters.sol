// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./../interfaces/IDCAParameters.sol";

import { SwapData } from "./../common/Types.sol";

abstract contract DCAParameters is IDCAParameters {
    /* ========= VIEWS ========= */

    mapping(address => mapping(address => bytes1)) public activeSwapIntervals;

    mapping(address => mapping(address => mapping(bytes1 => SwapData))) public swapData;

    mapping(address => mapping(address => mapping(bytes1 => mapping(uint256 => uint256)))) public swapAmountDelta;

    mapping(address => mapping(address => mapping(bytes1 => mapping(uint256 => uint256)))) public accumRatio;
}
