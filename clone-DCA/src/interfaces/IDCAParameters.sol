// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IDCAParameters {
    /* ========= VIEWS ========= */

    /// @notice Returns the byte representation of the set of active swap intervals for the given pair
    function activeSwapIntervals(address from_, address to_) external view returns (bytes1);

    /**
     * @notice Returns swapping information about a specific pair
     * @param swapInterval_ The byte representation of the swap interval to check
     */
    function swapData(address from_, address to_, bytes1 swapInterval_) external view 
        returns (uint256 performedSwaps, uint256 nextAmountToSwap, uint256 nextToNextSwap, uint256 lastSwappedAt);

    /// @notice Returns The difference of tokens to swap between a swap, and the previous one
    function swapAmountDelta(address from_, address to_, bytes1 swapInterval_, uint256 swapNo_) external view returns (uint256);

    /// @notice Returns the sum of the ratios reported in all swaps executed until the given swap number
    function accumRatio(address from_, address to_, bytes1 swapInterval_, uint256 swapNo_) external view returns (uint256);
}
