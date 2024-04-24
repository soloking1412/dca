// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import "./DCAParameters.sol";
import "./../utils/Governable.sol";
import "./../libraries/Intervals.sol";
import "../interfaces/IDCAConfigHandler.sol";
import "./../interfaces/IWNative.sol";

import { ZeroAddress, InvalidInterval, HighFee, HighPlatformFeeRatio, InvalidToken, InvalidNoOfSwaps, InvalidLength } from "./../common/Error.sol";

abstract contract DCAConfigHandler is DCAParameters, Governable, Pausable, IDCAConfigHandler {
    bytes1 public allowedSwapIntervals;

    mapping(address => bool) public allowedTokens;
    mapping(address => uint256) public tokenMagnitude;
    mapping(address => bool) public admins;
    mapping(address => bool) public swapExecutors;
    mapping(bytes1 => uint256) internal _swapFeeMap;

    IWNative public immutable wNative;
    address public feeVault;

    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 public maxNoOfSwap;
    uint256 public nextToNextTimeThreshold = 10 minutes;
    uint256 public platformFeeRatio;
    uint256 public constant MAX_FEE = 1000; // 10%
    uint256 public constant MAX_PLATFORM_FEE_RATIO = 10000; // 100%
    uint256 public constant BPS_DENOMINATOR = 10000; // 2 point precision

    /* ========= CONSTRUCTOR ========= */

    constructor(address governor_, address wNative_, address feeVault_, uint256 maxNoOfSwap_) Governable(governor_) {
        if (feeVault_ == address(0) || wNative_ == address(0)) revert ZeroAddress();
        if (maxNoOfSwap_ < 2) revert InvalidNoOfSwaps(); 

        wNative = IWNative(wNative_);
        feeVault = feeVault_;
        maxNoOfSwap = maxNoOfSwap_;
    }

    /* ========== MODIFIERS ==========  */

    modifier onlyAdminOrGovernor() {
        if (!admins[_msgSender()] && _msgSender() != governance()) revert UnauthorizedCaller();
        _;
    }

    modifier onlySwapper() {
        if (!swapExecutors[_msgSender()]) revert UnauthorizedCaller();
        _;
    }

    /* ========= VIEWS ========= */

    function getSwapFee(uint32 interval_) external view returns (uint256) {
        return _swapFeeMap[Intervals.intervalToMask(interval_)];
    }

    /* ========= RESTRICTED FUNCTIONS ========= */

    function pause() external onlyGovernance {
        _pause();
    }

    function unpause() external onlyGovernance {
        _unpause();
    }

    function addAdmins(address[] calldata accounts_) external onlyGovernance {
        _setAdmin(accounts_, true);
        emit AdminAdded(accounts_);
    }

    function removeAdmins(address[] calldata accounts_) external onlyGovernance {
        _setAdmin(accounts_, false);
        emit AdminRemoved(accounts_);
    }

    function addSwapExecutors(address[] calldata executor_) external onlyGovernance {
        _setSwapExecutor(executor_, true);
        emit SwapExecutorAdded(executor_);
    }

    function removeSwapExecutors(address[] calldata executor_) external onlyGovernance {
        _setSwapExecutor(executor_, false);
        emit SwapExecutorRemoved(executor_);
    }

    function addAllowedTokens(address[] calldata tokens_) external onlyAdminOrGovernor {
        _setAllowedTokens(tokens_, true);
        emit TokensAdded(tokens_);
    }

    function removeAllowedTokens(address[] calldata tokens_) external onlyAdminOrGovernor {
        _setAllowedTokens(tokens_, false);
        emit TokensRemoved(tokens_);
    }

    function addSwapIntervalsToAllowedList(uint32[] calldata swapIntervals_) external onlyAdminOrGovernor {
        for (uint256 i; i < swapIntervals_.length; ++i) {
            allowedSwapIntervals |= Intervals.intervalToMask(swapIntervals_[i]);
        }
        emit SwapIntervalsAdded(swapIntervals_);
    }

    function removeSwapIntervalsFromAllowedList(uint32[] calldata swapIntervals_) external onlyAdminOrGovernor {
        for (uint256 i; i < swapIntervals_.length; ++i) {
            allowedSwapIntervals &= ~Intervals.intervalToMask(swapIntervals_[i]);
        }
        emit SwapIntervalsRemoved(swapIntervals_);
    }

    function updateMaxSwapLimit(uint256 maxNoOfSwap_) external onlyAdminOrGovernor {
        if (maxNoOfSwap_ < 2) revert InvalidNoOfSwaps();
        maxNoOfSwap = maxNoOfSwap_;
        emit SwapLimitUpdated(maxNoOfSwap_);
    }

    function updateSwapTimeThreshold(uint256 nextToNextTimeThreshold_) external onlyAdminOrGovernor {
        nextToNextTimeThreshold = nextToNextTimeThreshold_;
        emit SwapThresholdUpdated(nextToNextTimeThreshold_);
    }

    function setFeeVault(address newVault_) external onlyGovernance {
        if (newVault_ == address(0)) revert ZeroAddress();
        feeVault = newVault_;
        emit FeeVaultUpdated(newVault_);
    }

    function setSwapFee(uint32[] calldata intervals_, uint256[] calldata swapFee_) external onlyGovernance {
        if (intervals_.length != swapFee_.length) revert InvalidLength();
        for (uint256 i; i < intervals_.length; i++) {
            if (swapFee_[i] > MAX_FEE) revert HighFee();

            _swapFeeMap[Intervals.intervalToMask(intervals_[i])] = swapFee_[i];
        }

        emit SwapFeeUpdated(intervals_, swapFee_);
    }

    function setPlatformFeeRatio(uint256 platformFeeRatio_) external onlyGovernance {
        if (platformFeeRatio_ > MAX_PLATFORM_FEE_RATIO) revert HighPlatformFeeRatio();
        platformFeeRatio = platformFeeRatio_;
        emit PlatformFeeRatioUpdated(platformFeeRatio_);
    }

    /* ========= INTERNAL/PRIVATE FUNCTIONS ========= */

    function _setAllowedTokens(address[] calldata tokens_, bool allowed_) private {
        for (uint256 i; i < tokens_.length; ++i) {
            address token = tokens_[i];
            if (token == address(0) || token == NATIVE_TOKEN) revert InvalidToken();
            allowedTokens[token] = allowed_;
            if (tokenMagnitude[token] == 0) {
                tokenMagnitude[token] = 10**IERC20Metadata(token).decimals();
            }
        }
    }

    function _setAdmin(address[] calldata accounts_, bool state_) private {
        for (uint256 i; i < accounts_.length; i++) {
            if (accounts_[i] == address(0)) revert ZeroAddress();
            admins[accounts_[i]] = state_;
        }
    }

    function _setSwapExecutor(address[] calldata accounts_, bool state_) private {
        for (uint256 i; i < accounts_.length; i++) {
            if (accounts_[i] == address(0)) revert ZeroAddress();
            swapExecutors[accounts_[i]] = state_;
        }
    }
}
