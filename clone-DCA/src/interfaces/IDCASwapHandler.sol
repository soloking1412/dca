// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SwapInfo, SwapDetails, Pair } from "./../common/Types.sol";

interface IDCASwapHandler {
    /* ========= EVENTS ========= */

    event Swapped(address indexed sender, address indexed rewardRecipient, SwapInfo[] swapInformation);
   
    event BlankSwapped(address indexed sender, address from, address to, bytes1 interval);

    /* ========= VIEWS ========= */

    /// @notice Returns the time after which next swap chan be done
    /// @param pairs_ The pairs that you want to swap.
    /// @return time after which swap can can be done
    function secondsUntilNextSwap(Pair[] calldata pairs_) external view returns (uint256[] memory);

    /// @notice Returns all information related to the next swap
    /// @dev Zero will returned for SwapInfo.receivedAmount
    /// @param pairs_ The pairs that you want to swap.
    /// @return The information about the next swap
    function getNextSwapInfo(Pair[] calldata pairs_) external view returns (SwapInfo[] memory);

    /* ========= RESTRICTED ========= */

    /// @notice Executes a swap
    /// @dev Can only be call by swapExecutors
    /// @param data_ Array of swap details
    /// @param rewardRecipient_ The address to send the reward to
    function swap(SwapDetails[] calldata data_, address rewardRecipient_) external;
}
