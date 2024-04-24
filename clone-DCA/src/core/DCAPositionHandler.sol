// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./../interfaces/IDCAPositionHandler.sol";
import "./../utils/Permitable.sol";
import "./DCAConfigHandler.sol";

import { UserPosition, PositionInfo, CreatePositionDetails, PermitType } from "./../common/Types.sol";
import { ZeroAddress, NotWNative, NativeTransferFailed, UnauthorizedTokens, InvalidAmount, InvalidNoOfSwaps, UnauthorizedInterval, InvalidRate, NoChanges, ZeroSwappedTokens, InvalidAmountTransferred, InvalidNativeAmount, InvalidPosition } from "./../common/Error.sol";

abstract contract DCAPositionHandler is Permitable, DCAConfigHandler, IDCAPositionHandler {
    using SafeERC20 for IERC20;

    mapping(uint256 => UserPosition) public userPositions;
    mapping(uint256 => uint256) internal _swappedBeforeModified; // positionId -> swappedAmount

    uint256 public totalCreatedPositions;

    /* ========= CONSTRUCTOR ========= */

    // solhint-disable-next-line no-empty-blocks
    constructor(address permit2_) Permitable(permit2_) {}

    /* ========= VIEWS ========= */

    function getPositionDetails(uint256 positionId_) external view returns (PositionInfo memory positionInfo) {
        UserPosition memory userPosition = userPositions[positionId_];

        uint256 performedSwaps = swapData[userPosition.from][userPosition.to][userPosition.swapIntervalMask].performedSwaps;

        positionInfo.owner = userPosition.owner;
        positionInfo.from = userPosition.from;
        positionInfo.to = userPosition.to;
        positionInfo.rate = userPosition.rate;


        positionInfo.swapsLeft = _remainingNoOfSwaps(userPosition.startingSwap, userPosition.finalSwap, performedSwaps);
        positionInfo.swapsExecuted = userPosition.finalSwap - userPosition.startingSwap - positionInfo.swapsLeft;
        positionInfo.unswapped = _calculateUnswapped(userPosition, performedSwaps);

        if (userPosition.swapIntervalMask > 0) {
            positionInfo.swapInterval = Intervals.maskToInterval(userPosition.swapIntervalMask);
            positionInfo.swapped = _calculateSwapped(positionId_, userPosition, performedSwaps);
        }
    }

    /* ========= FUNCTIONS ========= */

    function createPosition(CreatePositionDetails calldata details_) external payable whenNotPaused {
        if (details_.from == NATIVE_TOKEN && msg.value != details_.amount) revert InvalidNativeAmount();

        (uint256 positionId, bool isNative) = _create(details_);

        emit Created(_msgSender(), positionId, isNative);
    }

    function createBatchPositions(CreatePositionDetails[] calldata details_) external payable whenNotPaused {
        uint256 value = msg.value;
        bool[] memory isNative = new bool[](details_.length);

        for (uint256 i; i < details_.length; ++i) {
            if (details_[i].from == NATIVE_TOKEN) {
                if (details_[i].amount > value) revert InvalidNativeAmount();
                value -= details_[i].amount;
            }

            (, isNative[i]) = _create(details_[i]);
        }

        if (value != 0) revert InvalidNativeAmount();

        emit CreatedBatched(_msgSender(), totalCreatedPositions, details_.length, isNative);
    }

    function modifyPosition(uint256 positionId_, uint256 amount_, uint256 noOfSwaps_, bool isIncrease_, bool isNative_, bytes calldata permit_) external payable whenNotPaused {
        UserPosition memory userPosition = userPositions[positionId_];
        _assertPositionExistsAndCallerIsOwner(userPosition);

        if (amount_ == 0) {
            // only noOfSwaps is updated
            _assertTokensAreAllowed(userPosition.from, userPosition.to);
            if (msg.value != 0) revert InvalidNativeAmount();
        } else if (isIncrease_) {
            // increase
            _assertTokensAreAllowed(userPosition.from, userPosition.to);

            _deposit(isNative_, userPosition.from, amount_, permit_);
        }

        (uint256 rate, uint256 startingSwap, uint256 finalSwap) = _modify(userPosition, positionId_, amount_, noOfSwaps_, isIncrease_);

        // reduce
        if (!isIncrease_ && amount_ > 0) _pay(isNative_, userPosition.from, _msgSender(), amount_);

        emit Modified(_msgSender(), positionId_, rate, startingSwap, finalSwap, isNative_);
    }

    function terminatePosition(uint256 positionId_, address recipient_, bool isNative_) external {
        if (recipient_ == address(0)) revert ZeroAddress();

        UserPosition memory userPosition = userPositions[positionId_];
        _assertPositionExistsAndCallerIsOwner(userPosition);

        (uint256 unswapped, uint256 swapped) = _terminate(userPosition, positionId_);

        if (isNative_) {
            if (userPosition.from == address(wNative)) {
                _unwrapAndTransfer(recipient_, unswapped);
                IERC20(userPosition.to).safeTransfer(recipient_, swapped);
            } else if ((userPosition.to == address(wNative))) {
                IERC20(userPosition.from).safeTransfer(recipient_, unswapped);
                _unwrapAndTransfer(recipient_, swapped);
            } else revert NotWNative();
        } else {
            IERC20(userPosition.from).safeTransfer(recipient_, unswapped);
            IERC20(userPosition.to).safeTransfer(recipient_, swapped);
        }

        emit Terminated(_msgSender(), recipient_, positionId_, swapped, unswapped, isNative_);
    }

    function withdrawPosition(uint256 positionId_, address recipient_, bool isNative_) external {
        if (recipient_ == address(0)) revert ZeroAddress();

        UserPosition memory userPosition = userPositions[positionId_];
        _assertPositionExistsAndCallerIsOwner(userPosition);

        uint256 swapped = _withdraw(userPosition, positionId_);
        if (swapped == 0) revert ZeroSwappedTokens();

        _pay(isNative_, userPosition.to, recipient_, swapped);

        emit Withdrawn(_msgSender(), recipient_, positionId_, swapped, isNative_);
    }

    function transferPositionOwnership(uint256 positionId_, address newOwner_) external whenNotPaused {
        if (newOwner_ == address(0)) revert ZeroAddress();

        UserPosition memory userPosition = userPositions[positionId_];
        _assertPositionExistsAndCallerIsOwner(userPosition);

        userPositions[positionId_].owner = newOwner_;

        emit PositionOwnerUpdated(userPosition.owner, newOwner_, positionId_);
    }

    /* ========= INTERNAL ========= */

    function _deposit(bool isNative_, address token_, uint256 amount_, bytes calldata permit_) private {
        if (isNative_) {
            if (msg.value != amount_) revert InvalidNativeAmount();
            if (token_ != address(wNative)) revert NotWNative();
            _wrap(amount_);
        } else {
            _permitAndTransferFrom(token_, permit_, amount_);
        }
    }

    function _pay(bool isNative_, address token_, address recipient_, uint256 amount_) private {
        if (isNative_) {
            if (token_ != address(wNative)) revert NotWNative();
            _unwrapAndTransfer(recipient_, amount_);
        } else {
            IERC20(token_).safeTransfer(recipient_, amount_);
        }
    }

    function _safeNativeTransfer(address recipient_, uint256 amount_) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool sent, ) = recipient_.call{ value: amount_ }(new bytes(0));
        if (!sent) revert NativeTransferFailed();
    }
 
    function _permitAndTransferFrom(address token_, bytes calldata permit_, uint256 amount_) internal {
        (PermitType permitType, bytes memory data) = abi.decode(permit_, (PermitType, bytes)); 

        if(permitType == PermitType.PERMIT2_APPROVE)  {
            _permit2Approve(token_, data);
            IPermit2(PERMIT2).transferFrom(
                _msgSender(),
                address(this),
                uint160(amount_),
                token_
            );
        } else if (permitType == PermitType.PERMIT2_TRANSFER_FROM) {
            _permit2TransferFrom(token_, data, amount_);
        } else {
            _permit(token_, data);
            IERC20(token_).safeTransferFrom(_msgSender(), address(this), amount_);
        }
    }

    function _wrap(uint256 amount_) internal {
        if (amount_ > 0) wNative.deposit{ value: amount_ }();
    }

    function _unwrapAndTransfer(address recipient_, uint256 amount_) internal {
        if (amount_ > 0) {
            wNative.withdraw(amount_);
            _safeNativeTransfer(recipient_, amount_);
        }
    }

    // solhint-disable-next-line code-complexity
    function _create(CreatePositionDetails calldata details_) private returns (uint256 positionId, bool isNative) {
        if (details_.from == address(0) || details_.to == address(0)) revert ZeroAddress();
        if (details_.amount == 0) revert InvalidAmount();
        if (details_.noOfSwaps == 0 || details_.noOfSwaps > maxNoOfSwap) revert InvalidNoOfSwaps();

        bool isFromNative = details_.from == NATIVE_TOKEN;
        bool isToNative = details_.to == NATIVE_TOKEN;
        isNative = isFromNative || isToNative;

        address from = isFromNative ? address(wNative) : details_.from;
        address to = isToNative ? address(wNative) : details_.to;

        if (from == to) revert InvalidToken();
        _assertTokensAreAllowed(from, to);

        bytes1 swapIntervalMask = Intervals.intervalToMask(details_.swapInterval);
        if (allowedSwapIntervals & swapIntervalMask == 0) revert InvalidInterval();

        uint256 rate = _calculateRate(details_.amount, details_.noOfSwaps);
        if (rate == 0) revert InvalidRate();

        // transfer tokens
        if (isFromNative) _wrap(details_.amount);
        else _permitAndTransferFrom(from, details_.permit, details_.amount);

        positionId = ++totalCreatedPositions;
        uint256 performedSwaps = swapData[from][to][swapIntervalMask].performedSwaps;

        // updateActiveIntervals
        if (activeSwapIntervals[from][to] & swapIntervalMask == 0) activeSwapIntervals[from][to] |= swapIntervalMask;

        (uint256 startingSwap, uint256 finalSwap) = _addToDelta(from, to, swapIntervalMask, rate, performedSwaps, performedSwaps + details_.noOfSwaps
        );

        userPositions[positionId] = UserPosition({
            owner: _msgSender(), from: from, to: to, swapIntervalMask: swapIntervalMask, rate: rate, 
            swapWhereLastUpdated: performedSwaps, startingSwap: startingSwap, finalSwap: finalSwap
        });
    }

    function _modify(UserPosition memory userPosition_, uint256 positionId_, uint256 amount_, uint256 noOfSwaps_, bool isIncrease_) 
        internal returns (uint256 newRate,uint256 newStartingSwap,uint256 newFinalSwap) 
    {
        uint256 performedSwaps = swapData[userPosition_.from][userPosition_.to][userPosition_.swapIntervalMask].performedSwaps;
        uint256 remainingNoOfSwaps = _remainingNoOfSwaps(userPosition_.startingSwap, userPosition_.finalSwap, performedSwaps);
        uint256 unswapped = remainingNoOfSwaps * userPosition_.rate;
        uint256 tempUnswapped = unswapped;

        if (isIncrease_) tempUnswapped += amount_;
        else {
            if (amount_ > unswapped) revert InvalidAmount();
            tempUnswapped -= amount_;
        }

        if (tempUnswapped == unswapped && noOfSwaps_ == remainingNoOfSwaps) revert NoChanges();
        if (
            (tempUnswapped > 0 && (noOfSwaps_ == 0 || noOfSwaps_ > maxNoOfSwap)) ||
            (tempUnswapped == 0 && noOfSwaps_ > 0)
        ) revert InvalidNoOfSwaps();

        if (noOfSwaps_ > 0) newRate = _calculateRate(tempUnswapped, noOfSwaps_);
        if (newRate > 0) {
            newStartingSwap = performedSwaps;
            newFinalSwap = performedSwaps + noOfSwaps_;
        }

        // store current claimable swap tokens.
        _swappedBeforeModified[positionId_] = _calculateSwapped(positionId_, userPosition_, performedSwaps);

        // remove the prev position
        _removeFromDelta(userPosition_, performedSwaps);

        if(newRate > 0) {
            // add updated position
            (newStartingSwap, newFinalSwap) = _addToDelta(userPosition_.from, userPosition_.to, userPosition_.swapIntervalMask, newRate, newStartingSwap, newFinalSwap);

            if((activeSwapIntervals[userPosition_.from][userPosition_.to] & userPosition_.swapIntervalMask == 0)) {
                // add in activeSwapIntervals
                activeSwapIntervals[userPosition_.from][userPosition_.to] |= userPosition_.swapIntervalMask;
            }
        } else {
             // remove from activeSwapIntervals (if no other positions exist)
             SwapData memory data = swapData[userPosition_.from][userPosition_.to][userPosition_.swapIntervalMask];
             
             if (data.nextAmountToSwap == 0 && data.nextToNextAmountToSwap == 0)
                activeSwapIntervals[userPosition_.from][userPosition_.to] &= ~userPosition_.swapIntervalMask;
        }

        userPositions[positionId_].rate = newRate;
        userPositions[positionId_].swapWhereLastUpdated = performedSwaps;
        userPositions[positionId_].startingSwap = newStartingSwap;
        userPositions[positionId_].finalSwap = newFinalSwap;
    }

    function _terminate(UserPosition memory userPosition_, uint256 positionId_) private returns (uint256 unswapped, uint256 swapped){
        uint256 performedSwaps = swapData[userPosition_.from][userPosition_.to][userPosition_.swapIntervalMask].performedSwaps;

        swapped = _calculateSwapped(positionId_, userPosition_, performedSwaps);
        unswapped = _calculateUnswapped(userPosition_, performedSwaps);

        // removeFromDelta
        _removeFromDelta(userPosition_, performedSwaps);

        SwapData memory data = swapData[userPosition_.from][userPosition_.to][userPosition_.swapIntervalMask];
             
        if (data.nextAmountToSwap == 0 && data.nextToNextAmountToSwap == 0)
            activeSwapIntervals[userPosition_.from][userPosition_.to] &= ~userPosition_.swapIntervalMask;

        delete userPositions[positionId_];
        _swappedBeforeModified[positionId_] = 0;
    }

    function _withdraw(UserPosition memory userPosition_, uint256 positionId_) internal returns (uint256 swapped) {
        uint256 performedSwaps = swapData[userPosition_.from][userPosition_.to][userPosition_.swapIntervalMask].performedSwaps;

        swapped = _calculateSwapped(positionId_, userPosition_, performedSwaps);

        userPositions[positionId_].swapWhereLastUpdated = performedSwaps;
        _swappedBeforeModified[positionId_] = 0;
    }

    function _addToDelta(address from_, address to_, bytes1 swapIntervalMask_, uint256 rate_, uint256 startingSwap_, uint256 finalSwap_) internal returns (uint256, uint256) {
        (bool isPartOfNextSwap, uint256 timeUntilThreshold) = _getTimeUntilThreshold(from_, to_, swapIntervalMask_);
        SwapData storage data = swapData[from_][to_][swapIntervalMask_];

        if (isPartOfNextSwap && block.timestamp > timeUntilThreshold) {
            startingSwap_ += 1;
            finalSwap_ += 1;
            data.nextToNextAmountToSwap += rate_;
        } else {
            data.nextAmountToSwap += rate_;
        }

        swapAmountDelta[from_][to_][swapIntervalMask_][finalSwap_ + 1] += rate_;
        return (startingSwap_, finalSwap_);
    }

    function _removeFromDelta(UserPosition memory userPosition_, uint256 performedSwaps_) internal {
        if (userPosition_.finalSwap > performedSwaps_) {
            SwapData storage data = swapData[userPosition_.from][userPosition_.to][userPosition_.swapIntervalMask];

            if (userPosition_.startingSwap > performedSwaps_) {
                data.nextToNextAmountToSwap -= userPosition_.rate;
            } else {
                data.nextAmountToSwap -= userPosition_.rate;
            }
            swapAmountDelta[userPosition_.from][userPosition_.to][userPosition_.swapIntervalMask][
                userPosition_.finalSwap + 1
            ] -= userPosition_.rate;
        }
    }

    function _calculateSwapped( uint256 positionId_, UserPosition memory userPosition_, uint256 performedSwaps_) internal view returns (uint256) {
        uint256 finalNo = Math.min(performedSwaps_, userPosition_.finalSwap);

        // If last update happened after the position's final swap, then a withdraw was executed, and we just return 0
        if (userPosition_.swapWhereLastUpdated > finalNo) return 0;
        // If the last update matches the positions's final swap, then we can avoid all calculation below
        else if (userPosition_.swapWhereLastUpdated == finalNo) return _swappedBeforeModified[positionId_];

        uint256 startingNo= Math.max(userPosition_.swapWhereLastUpdated, userPosition_.startingSwap);
        uint256 avgAccumulationPrice = accumRatio[userPosition_.from][userPosition_.to][userPosition_.swapIntervalMask][finalNo] -
            accumRatio[userPosition_.from][userPosition_.to][userPosition_.swapIntervalMask][startingNo];

        return ((avgAccumulationPrice * userPosition_.rate) / tokenMagnitude[userPosition_.from]) + _swappedBeforeModified[positionId_];
    }

    function _remainingNoOfSwaps(uint256 startingSwap_, uint256 finalSwap_, uint256 performedSwaps_) private pure returns (uint256 remainingNoOfSwap) {
        uint256 noOfSwaps = finalSwap_ - startingSwap_;
        uint256 totalSwapExecutedFromStart = _subtractIfPossible(performedSwaps_, startingSwap_);
        remainingNoOfSwap = totalSwapExecutedFromStart > noOfSwaps ? 0 : noOfSwaps - totalSwapExecutedFromStart;
    }

    function _calculateUnswapped(UserPosition memory userPosition_, uint256 performedSwaps_) internal pure returns (uint256){
        return _remainingNoOfSwaps(userPosition_.startingSwap, userPosition_.finalSwap, performedSwaps_) * userPosition_.rate;
    }

    function _calculateRate(uint256 amount_, uint256 noOfSwaps_) internal pure returns (uint256) {
        return amount_ / noOfSwaps_;
    }

    function _assertTokensAreAllowed(address tokenA_, address tokenB_) internal view {
        if (!allowedTokens[tokenA_] || !allowedTokens[tokenB_]) revert UnauthorizedTokens();
    }

    function _assertPositionExistsAndCallerIsOwner(UserPosition memory userPosition_) internal view {
        if (userPosition_.swapIntervalMask == 0) revert InvalidPosition();
        if (_msgSender() != userPosition_.owner) revert UnauthorizedCaller();
    }

    function _subtractIfPossible(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ > b_ ? a_ - b_ : 0;
    }

    function _getTimeUntilThreshold(address from_, address to_, bytes1 interval_) private view returns (bool, uint256) {
        bytes1 activeIntervals = activeSwapIntervals[from_][to_];
        bytes1 mask = 0x01;
        bytes1 intervalsInSwap;
        uint256 nextSwapTimeEnd = type(uint256).max;

        while (activeIntervals >= mask && mask > 0) {
            if (activeIntervals & mask == mask || interval_ == mask) {
                SwapData memory swapDataMem = swapData[from_][to_][mask];
                uint32 swapInterval = Intervals.maskToInterval(mask);
                uint256 currSwapTime = (block.timestamp / swapInterval) * swapInterval; 
                uint256 nextSwapTime = swapDataMem.lastSwappedAt == 0
                    ? currSwapTime
                    : ((swapDataMem.lastSwappedAt / swapInterval) + 1) * swapInterval;
                
                // as swaps will only be done in current window
                // so if next window is smaller than current window then update the next window
                if(currSwapTime > nextSwapTime) nextSwapTime = currSwapTime;
                uint256 tempNextSwapTimeEnd = nextSwapTime + swapInterval;

                if (
                    (block.timestamp > nextSwapTime && block.timestamp < tempNextSwapTimeEnd) &&
                    (swapDataMem.nextAmountToSwap > 0 || mask == interval_)
                ) {
                    intervalsInSwap |= mask;
                    if (tempNextSwapTimeEnd < nextSwapTimeEnd) {
                        nextSwapTimeEnd = tempNextSwapTimeEnd;
                    }
                }
            }
            mask <<= 1;
        }
        return (intervalsInSwap & interval_ == interval_, nextSwapTimeEnd - nextToNextTimeThreshold);
    }
}
