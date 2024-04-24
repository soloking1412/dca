// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./../interfaces/IDZapDCA.sol";

import "./DCAParameters.sol";
import "./DCAConfigHandler.sol";
import "./DCAPositionHandler.sol"; 
import "./DCASwapHandler.sol";

import { ZeroAddress } from "./../common/Error.sol";

contract DZapDCA is DCAParameters, DCAConfigHandler, DCASwapHandler, DCAPositionHandler, IDZapDCA {
    using SafeERC20 for IERC20;

    constructor(address governor_, address wNative_, address feeVault_, address permit2_, uint256 maxNoOfSwap_) DCAConfigHandler(governor_, wNative_, feeVault_, maxNoOfSwap_) DCAPositionHandler(permit2_) {} // solhint-disable-line no-empty-blocks

    /* ========= USER FUNCTIONS ========= */

    function batchCall(bytes[] calldata data_) external returns (bytes[] memory results) {
        results = new bytes[](data_.length);
        for (uint256 i; i < data_.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data_[i]);
        }
        return results;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
