// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./../interfaces/IDCASwapHandler.sol";
import "./DCAConfigHandler.sol";

import { SwapInfo, Pair, SwapDetails } from "./../common/Types.sol";
import { InvalidLength, NoAvailableSwap, InvalidSwapAmount, InvalidReturnAmount, SwapCallFailed, InvalidBlankSwap } from "./../common/Error.sol";

abstract contract DCASwapHandler is DCAConfigHandler, IDCASwapHandler {
    using SafeERC20 for IERC20;

    /* ========= VIEWS ========= */

    function secondsUntilNextSwap(Pair[] calldata pairs_) external view returns (uint256[] memory) {
        uint256[] memory secondsArr = new uint256[](pairs_.length);
        for (uint256 i; i < pairs_.length; i++) secondsArr[i] = _secondsUntilNextSwap(pairs_[i].from, pairs_[i].to);
        return secondsArr;
    }

    function getNextSwapInfo(Pair[] calldata pairs_) external view returns (SwapInfo[] memory) {
        SwapInfo[] memory swapInformation = new SwapInfo[](pairs_.length);

        for (uint256 i; i < pairs_.length; ++i) {
            Pair memory pair = pairs_[i];

            (uint256 amountToSwap, bytes1 intervalsInSwap, uint256 swapperReward, uint256 platformFee) = _getTotalAmountsToSwap(pair.from, pair.to);

            swapInformation[i] = SwapInfo(pair.from, pair.to, amountToSwap, 0, swapperReward, platformFee, intervalsInSwap);
        }

        return swapInformation;
    }

    /* ========= PUBLIC ========= */

    function swap(SwapDetails[] calldata data_, address rewardRecipient_) external onlySwapper whenNotPaused {
        if (data_.length == 0) revert InvalidLength();
        SwapInfo[] memory swapInfo = new SwapInfo[](data_.length);

        for (uint256 i; i < data_.length; ++i) {
            SwapDetails memory data = data_[i];
            (uint256 amountToSwap, bytes1 intervalsInSwap, uint256 swapperReward, uint256 platformFee) = _getTotalAmountsToSwap(data.from, data.to);

            if (amountToSwap == 0 || intervalsInSwap == 0) revert NoAvailableSwap();
            if (data.amount != amountToSwap) revert InvalidSwapAmount();

            // execute Swap
            uint256 returnAmount = _executeSwap(data);

            if (returnAmount < data.minReturnAmount) revert InvalidReturnAmount();

            // register swap
            _registerSwap(data.from, data.to, amountToSwap, returnAmount, intervalsInSwap);

            swapInfo[i] = SwapInfo(data.from, data.to, amountToSwap, returnAmount, swapperReward, platformFee, intervalsInSwap);

            // transfer reward and fee
            if (platformFee > 0) IERC20(data.from).safeTransfer(feeVault, platformFee);
            if (swapperReward > 0) IERC20(data.from).safeTransfer(rewardRecipient_, swapperReward);
        }
        emit Swapped(_msgSender(), rewardRecipient_, swapInfo);
    }

    /**
        wont come under this until it all positions have a blank swap active
        dont update lastSwappedAt;
         swapAmountDelta:
            in create in will be grater than swapDataMem.performSwap + 1
            in modify if will have been updated
    */
    function blankSwap(address from_, address to_, bytes1 maskedInterval_) external onlySwapper whenNotPaused {
        SwapData storage data = swapData[from_][to_][maskedInterval_];
        
        if (data.nextAmountToSwap > 0 || data.nextToNextAmountToSwap == 0) revert InvalidBlankSwap();
        // require(data.nextAmountToSwap == 0 && data.nextToNextAmountToSwap > 0, "InvalidBlankSwap");

        accumRatio[from_][to_][maskedInterval_][data.performedSwaps + 1] = accumRatio[from_][to_][maskedInterval_][data.performedSwaps];

        data.nextAmountToSwap += data.nextToNextAmountToSwap;
        data.nextToNextAmountToSwap = 0;
        data.performedSwaps += 1;

        emit BlankSwapped(_msgSender(), from_, to_, maskedInterval_);
    }

    /* ========= INTERNAL ========= */

    function _executeSwap(SwapDetails memory data_) private returns (uint256 returnAmount) {
        uint256 balanceBefore = IERC20(data_.to).balanceOf(address(this));
        IERC20(data_.from).approve(data_.tokenProxy, data_.amount);

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = data_.executor.call(data_.swapCallData);
        if (!success) revert SwapCallFailed();

        returnAmount = IERC20(data_.to).balanceOf(address(this)) - balanceBefore;
    }

    function _getSwapAmountAndFee(uint256 amount_, uint256 fee_) private pure returns (uint256, uint256) {
        uint256 feeAmount = (amount_ * fee_) / BPS_DENOMINATOR;
        return (amount_ - feeAmount, feeAmount);
    }

    function _getTotalAmountsToSwap(address from_, address to_) private view 
        returns (uint256 amountToSwap, bytes1 intervalsInSwap, uint256 swapperReward, uint256 platformFee) 
    {
        bytes1 activeIntervalsMem = activeSwapIntervals[from_][to_];
        bytes1 mask = 0x01;

        while (activeIntervalsMem >= mask && mask > 0) {
            if (activeIntervalsMem & mask != 0) {
                SwapData memory swapDataMem = swapData[from_][to_][mask];
                uint32 swapInterval = Intervals.maskToInterval(mask);

                // Note: this 'break' is both an optimization and a search for more CoW. Since this loop starts with the smaller intervals, it is
                // highly unlikely that if a small interval can't be swapped, a bigger interval can. It could only happen when a position was just
                // created for a new swap interval. At the same time, by adding this check, we force intervals to be swapped together.
                if (((swapDataMem.lastSwappedAt / swapInterval) + 1) * swapInterval > block.timestamp) break;

                if (swapDataMem.nextAmountToSwap > 0) {
                    intervalsInSwap |= mask;
                    (uint256 amountToSwapForInterval, uint256 feeAmount) = _getSwapAmountAndFee(swapDataMem.nextAmountToSwap, _swapFeeMap[mask]);
                    (uint256 reward, uint256 fee) = _getSwapAmountAndFee(feeAmount, platformFeeRatio);

                    amountToSwap += amountToSwapForInterval;
                    swapperReward += reward;
                    platformFee += fee;
                }
            }

            mask <<= 1;
        }

        if (amountToSwap == 0) intervalsInSwap = 0;
    }

    function _registerSwap(address tokenA_, address tokenB_,uint256 amountToSwap_, uint256 totalReturnAmount_, bytes1 intervalsInSwap_) private {
        bytes1 mask = 0x01;
        bytes1 activeIntervals = activeSwapIntervals[tokenA_][tokenB_];

        while (activeIntervals >= mask && mask != 0) {
            // nextAmountToSwap > 0. 
            // nextAmountToSwap > 0. nextToNext > 0
            SwapData memory swapDataMem = swapData[tokenA_][tokenB_][mask];

            if (intervalsInSwap_ & mask != 0 && swapDataMem.nextAmountToSwap > 0) {
                (uint256 amountToSwapForIntervalWithoutFee, ) = _getSwapAmountAndFee(swapDataMem.nextAmountToSwap, _swapFeeMap[mask]);
                uint256 returnAmountForInterval = totalReturnAmount_ * amountToSwapForIntervalWithoutFee * tokenMagnitude[tokenA_] / amountToSwap_;
                uint256 swapPrice = returnAmountForInterval / swapDataMem.nextAmountToSwap;

                // accumRatio[currSwapNo] = accumRatio[prevSwapNo] + swapPriceForInterval
                accumRatio[tokenA_][tokenB_][mask][swapDataMem.performedSwaps + 1] = accumRatio[tokenA_][tokenB_][mask][swapDataMem.performedSwaps] + swapPrice;

                // nextAmountToSwap = nextAmountToSwap - amounts for position which have to finished
                swapData[tokenA_][tokenB_][mask] = SwapData(
                    swapDataMem.performedSwaps + 1,
                    swapDataMem.nextAmountToSwap +
                        swapDataMem.nextToNextAmountToSwap -
                        swapAmountDelta[tokenA_][tokenB_][mask][swapDataMem.performedSwaps + 2],
                    0,
                    block.timestamp
                );

                // remove swapInterval from  activeSwapIntervals if all swaps for it are been executed
                if (swapData[tokenA_][tokenB_][mask].nextAmountToSwap == 0) activeSwapIntervals[tokenA_][tokenB_] &= ~mask;

                delete swapAmountDelta[tokenA_][tokenB_][mask][swapDataMem.performedSwaps + 2];
            } else if (swapDataMem.nextAmountToSwap == 0 && swapDataMem.nextToNextAmountToSwap > 0) {
                // nextAmountToSwap = 0. nextToNext > 0
                SwapData storage data = swapData[tokenA_][tokenB_][mask];

                accumRatio[tokenA_][tokenB_][mask][swapDataMem.performedSwaps + 1] = accumRatio[tokenA_][tokenB_][mask][swapDataMem.performedSwaps];

                data.nextAmountToSwap = swapDataMem.nextAmountToSwap + swapDataMem.nextToNextAmountToSwap;
                data.nextToNextAmountToSwap = 0;
                data.performedSwaps += 1;

                // emit BlankSwapped(_msgSender(), tokenA_, tokenB_, mask);
            }
            mask <<= 1;
        }
    }

    function _secondsUntilNextSwap(address from_, address to_) private view returns (uint256) {
        bytes1 activeIntervals = activeSwapIntervals[from_][to_];
        bytes1 mask = 0x01;
        uint256 smallerIntervalBlocking;

        while (activeIntervals >= mask && mask > 0) {
            if (activeIntervals & mask == mask) {
                SwapData memory swapDataMem = swapData[from_][to_][mask];
                uint32 swapInterval = Intervals.maskToInterval(mask);
                uint256 nextAvailable = ((swapDataMem.lastSwappedAt / swapInterval) + 1) * swapInterval;

                if (swapDataMem.nextAmountToSwap > 0) {
                    if (nextAvailable <= block.timestamp) return smallerIntervalBlocking;
                    else return nextAvailable - block.timestamp;
                } else if (nextAvailable > block.timestamp) {
                    smallerIntervalBlocking = smallerIntervalBlocking == 0 ? nextAvailable - block.timestamp : smallerIntervalBlocking;
                }
            }
            mask <<= 1;
        }
        return type(uint256).max;
    }
}
