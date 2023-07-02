// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Vesting {
    //============== Errors ===================//

    error Vesting__alreadyLockedTokens();
    error Vesting__expirationMustBeInTheFuture();
    error Vesting__TransferFailed();
    error Vesting__TokensNotLocked();
    error Vesting__tokensAlreadyClaimed();
    error Vesting__tokenLockNotExpired();

    //============== STATE VARIABLES ===================//

    IERC20 public immutable token;
    address public receiver;
    uint256 public amount;
    uint256 public expiry;
    bool public locked;
    bool public claimed;

    //============== EVENTS ===================//

    event Locked(address indexed from, address indexed receiver, uint256 indexed amount, uint256 expiry);
    event Claimed(address indexed receiver, uint256 indexed amount);

    //============== CONSTRUCTOR ===================//

    constructor(IERC20 _token) {
        token = _token;
    }

    //============== EXTERNAL FUNCTIONS ===================//

    /**
     * @notice Locks tokens for a receiver
     * @dev Can only be called once per expiration period
     * @dev receiver needs be msg.sender or to have transfered tokens to msg.sender
     * @dev msg.sender needs to approve this contract to transfer tokens
     *
     * @param _receiver receiver of the locked tokens after expiration
     * @param _amount amount of tokens to lock
     * @param _expiry time after which the tokens can be claimed (unix timestamp)
     */
    function lock(address _receiver, uint256 _amount, uint256 _expiry) external {
        if (locked) {
            revert Vesting__alreadyLockedTokens();
        }
        if (_expiry <= block.timestamp) {
            revert Vesting__expirationMustBeInTheFuture();
        }

        locked = true;
        claimed = false;
        receiver = _receiver;
        amount = _amount;
        expiry = _expiry;
        emit Locked(msg.sender, _receiver, _amount, _expiry);

        bool success = token.transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert Vesting__TransferFailed();
        }
    }

    /**
     * @notice Allows anyone to claim the locked tokens and transfers them to the receiver
     * @dev Can only be called once per expiration period and only be called after the expiration period
     * @dev Tokens must be locked first
     */
    function claim() external {
        if (claimed) {
            revert Vesting__tokensAlreadyClaimed();
        }
        if (!locked) {
            revert Vesting__TokensNotLocked();
        }
        if (block.timestamp < expiry) {
            revert Vesting__tokenLockNotExpired();
        }

        claimed = true;
        locked = false;
        emit Claimed(receiver, amount);

        bool success = token.transfer(receiver, amount);
        if (!success) {
            revert Vesting__TransferFailed();
        }
    }

    //============== VIEW FUNCTIONS ===================//

    /**
     * @notice Returns the current time (unix timestamp)
     * @dev Used for testing purposes
     */
    function getTime() external view returns (uint256) {
        return block.timestamp;
    }
}
