// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./IWNative.sol";

interface IDCAConfigHandler {
    /* ========= EVENTS ========= */

    event AdminAdded(address[] accounts);

    event AdminRemoved(address[] accounts);

    event SwapExecutorAdded(address[] accounts);

    event SwapExecutorRemoved(address[] accounts);

    event SwapLimitUpdated(uint256 noOfSwaps);

    event SwapThresholdUpdated(uint256 threshold);

    event TokensAdded(address[] tokens);

    event TokensRemoved(address[] tokens);

    event SwapIntervalsAdded(uint32[] swapIntervals);

    event SwapIntervalsRemoved(uint32[] swapIntervals);

    event FeeVaultUpdated(address feeVault);

    event SwapFeeUpdated(uint32[] intervals, uint256[] swapFee);

    event PlatformFeeRatioUpdated(uint256 platformFeeRatio);

    /* ========= VIEWS ========= */

    /// @notice Returns a byte that represents allowed swap intervals
    function allowedSwapIntervals() external view returns (bytes1);

    /// @notice Returns if a token is currently allowed or not
    function allowedTokens(address token_) external view returns (bool);

    /// @notice Returns token's magnitude (10**decimals)
    function tokenMagnitude(address token_) external view returns (uint256);

    /**
     * @notice Returns whether account is admin or not
     * @param account_ account to check
     */
    function admins(address account_) external view returns (bool);

    /**
     * @notice Returns whether account is a swap executors or not
     * @param account_ account to check
     */
    function swapExecutors(address account_) external view returns (bool);

    /// @notice Returns address of wNative token
    function wNative() external view returns (IWNative);

    /// @notice Returns the address of vault where platform fee will be deposited
    function feeVault() external view returns (address);

    /**
     * @notice Returns the address which will be used for Native tokens
     * @dev Cannot be modified
     * @return Native token
     */
    // solhint-disable-next-line func-name-mixedcase
    function NATIVE_TOKEN() external view returns (address);

    /// @notice Returns the percent of fee that will be charged on swaps
    function getSwapFee(uint32 interval_) external view returns (uint256);

    /// @notice Returns the percent of swapFee that platform will take
    function platformFeeRatio() external view returns (uint256);

    /**
     * @notice Returns the max fee that can be set for swaps
     * @dev Cannot be modified
     * @return The maximum possible fee
     */
    // solhint-disable-next-line func-name-mixedcase
    function MAX_FEE() external view returns (uint256);

    /**
     * @notice Returns the max fee ratio that can be set
     * @dev Cannot be modified
     * @return The maximum possible value
     */
    // solhint-disable-next-line func-name-mixedcase
    function MAX_PLATFORM_FEE_RATIO() external view returns (uint256);

    /**
     * @notice Returns the BPS denominator to be used
     * @dev Cannot be modified
     * @dev swapFee and platformFeeRatio need to use the precision used by BPS_DENOMINATOR
     */
    // solhint-disable-next-line func-name-mixedcase
    function BPS_DENOMINATOR() external view returns (uint256);

    /* ========= RESTRICTED FUNCTIONS ========= */

    /// @notice Pauses all swaps and deposits
    function pause() external;

    /// @notice UnPauses if contract is paused
    function unpause() external;

    /**
     * @notice @notice Add admins which can set allowed tokens and intervals
     * @dev Can be called by governance
     * @param accounts_ array of accounts
     */
    function addAdmins(address[] calldata accounts_) external;

    /**
     * @notice @notice Remove admins
     * @dev Can be called by governance
     * @param accounts_ array of accounts
     */
    function removeAdmins(address[] calldata accounts_) external;

    /**
     * @notice @notice Add executors which can do swaps
     * @dev Can be called by governance
     * @param executor_ array of accounts
     */
    function addSwapExecutors(address[] calldata executor_) external;

    /**
     * @notice @notice Remove executors
     * @dev Can be called by governance
     * @param executor_ array of accounts
     */
    function removeSwapExecutors(address[] calldata executor_) external;

    /**
     * @notice Adds new tokens to the allowed list
     * @dev Can be called by governance or admins
     * @param tokens_ array of tokens
     */
    function addAllowedTokens(address[] calldata tokens_) external;

    /**
     * @notice Removes tokens from the allowed list
     * @dev Can be called by governance or admins
     * @param tokens_ array of tokens
     */
    function removeAllowedTokens(address[] calldata tokens_) external;

    /**
     * @notice Adds new swap intervals to the allowed list
     * @dev Can be called by governance or admins
     * @param swapIntervals_ The new swap intervals
     */
    function addSwapIntervalsToAllowedList(uint32[] calldata swapIntervals_) external;

    /**
     * @notice Removes some swap intervals from the allowed list
     * @dev Can be called by governance or admins
     * @param swapIntervals_ The swap intervals to remove
     */
    function removeSwapIntervalsFromAllowedList(uint32[] calldata swapIntervals_) external;

    /**
     * @notice Sets a the fee vault address
     * @dev Can be called by governance
     * @param newVault_ New vault address
     */
    function setFeeVault(address newVault_) external;

    /**
     * @notice Sets a swap fee for different interval
     * @dev Can be called by governance
     * @dev Will revert with HighFee if the fee is higher than the maximum
     * @dev set it in multiple of 100 (1.5% = 150)
     * @param intervals_ Array of intervals
     * @param swapFee_ Array of fees in respect to intervals
     */
    function setSwapFee(uint32[] calldata intervals_, uint256[] calldata swapFee_) external;

    /**
     * @notice Sets a new platform fee ratio
     * @dev Can be called by governance
     * @dev Will revert with HighPlatformFeeRatio if given ratio is too high
     * @dev set it in multiple of 100 (1.5% = 150)
     * @param platformFeeRatio_ The new ratio
     */
    function setPlatformFeeRatio(uint256 platformFeeRatio_) external;
}
