// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { PositionInfo, CreatePositionDetails } from "./../common/Types.sol";

interface IDCAPositionHandler {
    /* ========= EVENTS ========= */

    event Created(address indexed user, uint256 positionId, bool isNative);

    event CreatedBatched(address indexed user, uint256 finalIndex, uint256 noOfPositions, bool[] isNative);

    event Modified(address indexed user, uint256 positionId, uint256 rate, uint256 startingSwap, uint256 finalSwap, bool isNative);
    event Terminated(address indexed user, address indexed recipient, uint256 positionId, uint256 unswapped, uint256 swapped, bool isNative);
    event Withdrawn(address indexed user, address indexed recipient, uint256 positionId, uint256 swapped, bool isNative);
    event PositionOwnerUpdated(address indexed oldOwner, address indexed newOwner, uint256 positionId);

    /* ========= VIEWS ========= */

    /*
     * @notice Returns user position info
     * @param positionId_ The information about the user position
     */
    function userPositions(uint256 positionId_) external view returns (address owner, address from, address to, bytes1 swapIntervalMask, uint256 rate, uint256 swapWhereLastUpdated, uint256 startingSwap, uint256 finalSwap);

    /// @notice Returns total positions that have been created
    function totalCreatedPositions() external view returns (uint256);

    /*
     * @notice Returns position info
     * @dev swapsExecuted, swapsLeft, swapped, unswapped are also returned here
     * @param positionId_ The information about the position
     */
    function getPositionDetails(uint256 positionId_) external view returns (PositionInfo memory positionInfo);

    /* ========= USER FUNCTIONS ========= */

    /*
     * @notice Creates a new position
     * @dev can only be call if contract is not pause
     * @dev to use positions with native tokens use NATIVE_TOKEN as address
     * @dev native token will be internally wrapped to wNative tokens
     * @param details_ details for position creation
     */
    function createPosition(CreatePositionDetails calldata details_) external payable;

    /*
     * @notice Creates multiple new positions
     * @dev can only be call if contract is not pause
     * @dev to use positions with native tokens use NATIVE_TOKEN as address
     * @dev native token will be internally wrapped to wNative tokens
     * @param details_ array of details for position creation
     */
    function createBatchPositions(CreatePositionDetails[] calldata details_) external payable;

    /*
     * @notice Modify(increase/reduce/changeOnlyNoOfSwaps) position
     * @dev can only be call if contract is not pause
     * @param positionId_ The position's id
     * @param amount_ Amount of funds to add or remove to the position
     * @param noOfSwaps_ The new no of swaps
     * @param isIncrease_ Set it as true for increasing
     * @param isNative_ Set it as true for increasing/reducing using native token
     * @param permit_ permit calldata, erc20Permit, daiPermit, and permit2 both can be used here
     */
    function modifyPosition(uint256 positionId_, uint256 amount_, uint256 noOfSwaps_, bool isIncrease_, bool isNative_, bytes calldata permit_) external payable;

    /*
     * @notice Terminate a position and withdraw swapped and unswapped tokens
     * @param positionId_ The position's id
     * @param recipient_ account where tokens will be transferred
     * @param isNative_ Set it as true unwrap wNative to native token
     */
    function terminatePosition(uint256 positionId_, address recipient_, bool isNative_) external;

    /*
     * @notice Withdraw swapped tokens
     * @param positionId_ The position's id
     * @param recipient_ account where tokens will be transferred
     * @param isNative_ Set it as true unwrap wNative to native token
     */
    function withdrawPosition(uint256 positionId_, address recipient_, bool isNative_) external;

    /*
     * @notice Transfer position ownership to other account
     * @dev can only be call if contract is not pause
     * @param positionId_ The position's id
     * @param newOwner_ New owner to set
     */
    function transferPositionOwnership(uint256 positionId_, address newOwner_) external;
}
