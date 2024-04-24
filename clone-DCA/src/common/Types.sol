// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/**
 * @notice User position info
 * swapWhereLastUpdated: swaps at which position was last updated (create, modify, withdraw)
 * startingSwap: swap at position will start (1st swap = 0)
 * finalSwap: swap at the all the swaps for position will be finished
 * swapIntervalMask: How frequently the position's swaps should be executed
 * rate: How many "from" tokens need to be traded in each swap
 * from: The token that the user deposited and will be swapped in exchange for "to"
 * to: The token that the user will get in exchange for their "from" tokens in each swap
 * owner: address of position owner
 */
struct UserPosition {
    address owner;
    address from;
    address to;
    bytes1 swapIntervalMask;
    uint256 rate;
    uint256 swapWhereLastUpdated;
    uint256 startingSwap;
    uint256 finalSwap;
}

/**
 * @notice User position info
 * @dev to get more readable information
 * owner: address of position owner
 * from: The token that the user deposited and will be swapped in exchange for "to"
 * to: The token that the user will get in exchange for their "from" tokens in each swap
 * swapInterval: How frequently the position's swaps should be executed
 * rate: How many "from" tokens need to be traded in each swap
 * swapsExecuted: How many swaps were executed since creation, last modification, or last withdraw
 * swapsLeft: How many swaps left the position has to execute
 * swapped: How many to swaps are available to withdraw
 * unswapped:How many "from" tokens there are left to swap
 */
struct PositionInfo {
    address owner;
    address from;
    address to;
    uint32 swapInterval;
    uint256 rate;
    uint256 swapsExecuted;
    uint256 swapsLeft;
    uint256 swapped;
    uint256 unswapped;
}

/**
 * @notice Create Position Details
 * @dev Will be use in createPosition and createBatchPositions as input arg
 * @dev For Native token user NATIVE_TOKEN as address
 * from: The address of the "from" token
 * to: The address of the "to" token
 * swapInterval: How frequently the position's swaps should be executed
 * amount: How many "from" tokens will be swapped in total
 * noOfSwaps: How many swaps to execute for this position
 * permit: Permit callData, erc20Permit, daiPermit and permit2 are supported
 */
struct CreatePositionDetails {
    address from;
    address to;
    uint32 swapInterval;
    uint256 amount;
    uint256 noOfSwaps;
    bytes permit;
}

/**
 * @notice Swap information about a specific pair
 * performedSwaps: How many swaps have been executed
 * nextAmountToSwap: How much of "from" token will be swapped on the next swap
 * nextToNextAmountToSwap: How much of "from" token will be swapped on the nextToNext swap
 * lastSwappedAt: Timestamp of the last swap
 */
struct SwapData {
    uint256 performedSwaps;
    uint256 nextAmountToSwap;
    uint256 nextToNextAmountToSwap;
    uint256 lastSwappedAt;
}

/**
 * @notice Information about a swap
 * @dev totalAmount of "from" tokens used is equal swappedAmount + reward + fee
 * from: The address of the "from" token
 * to: The address of the "to" token
 * swappedAmount: The actual amount of "from" tokens that were swapped
 * receivedAmount:The actual amount of "tp" tokens that were received
 * reward: The amount of "from" token that were given as rewards
 * fee: The amount of "from" token that were given as fee
 * intervalsInSwap: The different interval for which swap has taken place
 */
struct SwapInfo {
    address from;
    address to;
    uint256 swappedAmount;
    uint256 receivedAmount;
    uint256 reward;
    uint256 fee;
    bytes1 intervalsInSwap;
}

/**
 * @notice Swap Details
 * @dev Will be use in swap as input arg
 * executor: DEX's or aggregator address
 * tokenProxy: Who should we approve the tokens to (as an example: Paraswap makes you approve one address and send data to other)
 * from: The address of the "from" token
 * to: The address of the "to" token
 * amount: The amount of "from" token which will be swapped (totalSwappedAmount - feeAmount)
 * minReturnAmount: Minimum amount of "to" token which will be received from swap
 * swapCallData: call to make to the dex
 */
struct SwapDetails {
    address executor;
    address tokenProxy;
    address from;
    address to;
    uint256 amount;
    uint256 minReturnAmount;
    bytes swapCallData;
}

/**
 * @notice A pair of tokens
 * from: The address of the "from" token
 * to: The address of the "to" token
 */
struct Pair {
    address from;
    address to;
}

enum PermitType {
    PERMIT2_APPROVE,
    PERMIT2_TRANSFER_FROM,
    PERMIT
}
