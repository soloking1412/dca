// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { ZeroAddress, InvalidPermit, InvalidPermitData, InvalidPermitSender } from "./../common/Error.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "./../interfaces/IDAIPermit.sol";

import "./../interfaces/IPermit2.sol";

abstract contract Permitable {
    // solhint-disable-next-line var-name-mixedcase
    address public immutable PERMIT2;

    constructor(address permit2_) {
        if (permit2_ == address(0)) revert ZeroAddress();
        PERMIT2 = permit2_;
    }

    function _permit2Approve(address token_, bytes memory data_) internal {
        if(data_.length > 0) {
            (uint160 allowanceAmount, uint48 nonce, uint48 expiration, uint256 sigDeadline, bytes memory signature) = abi.decode(data_, (uint160, uint48, uint48, uint256, bytes));
            IPermit2(PERMIT2).permit(
                msg.sender, 
                IPermit2.PermitSingle(
                    IPermit2.PermitDetails(
                        token_,
                        allowanceAmount, 
                        expiration, 
                        nonce
                    ),
                    address(this),
                    sigDeadline
                ),
                signature
            );
        }
    }

    function _permit2TransferFrom(address token_, bytes memory data_, uint256 amount_) internal {
        (uint256 nonce, uint256 deadline, bytes memory signature) = abi.decode(data_, (uint256, uint256, bytes));
        IPermit2(PERMIT2).permitTransferFrom(
            IPermit2.PermitTransferFrom(
                IPermit2.TokenPermissions(token_, amount_),
                nonce,
                deadline
            ),
            IPermit2.SignatureTransferDetails(address(this), amount_),
            msg.sender,
            signature
        );
    }

    function _permit(address token_, bytes memory data_) internal {
        if (data_.length > 0) {
            bool success;
            
            if (data_.length == 32 * 7) {
                (success, ) = token_.call(abi.encodePacked(IERC20Permit.permit.selector, data_));
            } else if (data_.length == 32 * 8) {
                (success, ) = token_.call(abi.encodePacked(IDAIPermit.permit.selector, data_));
            } else {
                revert InvalidPermitData();
            }
            if (!success) revert InvalidPermit();
        }
    }
}
