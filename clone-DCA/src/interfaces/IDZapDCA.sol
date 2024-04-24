// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./IDCAConfigHandler.sol";
import "./IDCAPositionHandler.sol";
import "./IDCASwapHandler.sol";
import "./IDCAParameters.sol";

interface IDZapDCA is IDCAParameters, IDCAConfigHandler, IDCAPositionHandler, IDCASwapHandler {
    /* ========= EVENTS ========= */

    event TokensRescued(address indexed to, address indexed token, uint256 amount);

    /* ========= OPEN ========= */

    /// @notice Receives and executes a batch of function calls on this contract.
    function batchCall(bytes[] calldata data_) external returns (bytes[] memory results);
}
