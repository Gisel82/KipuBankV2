// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30; 

/// @title KipuBank - It is a deposit vault contract with a transaction limit and total capacity, and also allows users to deposit and withdraw ETH with restrictions.
///@dev Use standard security practices such as custom errors, checks-effects-interactions patterns, and events.

// =================
//      IMPORT
// =================

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract KipuBank is AccessControl, ReentrancyGuard{
    using SafeERC20 for IERC20;
  
    // ==============
    //     ROLES
    // ==============

    bytes32 public constant BANK_MANAGER_ROLE = keccak256("BANK_MANAGER_ROLE");
    
    // ====================
    // IMMUTABLE VARIABLES
    // ====================
    

    /// @notice Máximo permitido por transacción de retiro.
    uint256 public immutable maxWithdrawal;

    /// @notice Capacidad total del banco en ETH.
    uint256 public immutable totalBankCapacity;

    
    // ==================
    // STORAGE VARIABLES
    // ==================

    /// @notice Total actual de todos los depósitos en el contrato.
    uint256 public totalDeposits;

   
    // ==============================
    // MAPPINGS
    // ==============================


    /// @notice User balances stored in the vault.
    mapping(address => uint256) private vaultBalance;

    /// @notice Number of deposits made by each user.
    mapping(address => uint256) public depositCount;

    /// @notice Number of withdrawals made by each user.
    mapping(address => uint256) public withdrawalCount;


    // =======
    // EVENTS
    // =======


    /// @notice It is issued when the user makes a successful deposit.
    /// @param user is the user's address 
    ///@param  amount Amount of ETH deposited.

    event DepositMade(address indexed user, uint256 amount);
    
    /// @notice It is issued when the user makes a successful withdrawal.
    /// @param user the user's address 
   ///@param amount Amount of ETH withdrawn.
    

    event WithdrawalMade(address indexed user, uint256 amount);


    // ==============================
    // CUSTOM ERRORS
    // ==============================

    /// @notice It is launched when a deposit exceeds the global banking capacity.
    error MaxDepositExceeded();

    /// @notice When a withdrawal exceeds the transaction limit.
    error MaxWithdrawalExceeded();

    /// @notice When a user tries to withdraw more than their balance
    error InsufficientBalance();

    /// @notice When trying to deposit 0 ETH.
    error ZeroDepositNotAllowed();

    /// @notice Thrown if you try to send ETH directly to the contract.
    error DirectTransferNotAllowed();

    /// @notice Thrown if the maxRetiro value in the constructor is invalid.
    error MaximumWithdrawalInvalid();

    /// @notice Thrown if the bank capacity in the constructor is invalid.
    error InvalidBankCapacity();

   
    // ==============================
    // CONSTRUCTOR
    // ==============================

    /// @notice Initializes the contract with the specified limits.
    /// @param _maxWithdrawal Maximum withdrawal limit per transaction.
    /// @param _totalCapacity Total ETH capacity of the bank.
    
    constructor(uint256 _maxWithdrawal, uint256 _totalCapacity) {
        if (_maxWithdrawal == 0) revert MaximumWithdrawalInvalid();
        if (_totalCapacity == 0) revert InvalidBankCapacity();

        maxWithdrawal = _maxWithdrawal;
        totalBankCapacity = _totalCapacity;
    }

    // ==============================
    // MODIFIERS
    // ==============================


    /// @notice Verify that the amount sent is greater than 0.
      
    modifier nonZeroDeposit() {
        if (msg.value == 0) revert ZeroDepositNotAllowed();
        _;
    }
    
    /// @notice Check that the withdrawal is within the maximum allowed.
    /// @param amount Amount to withdraw.
    
    modifier withinWithdrawalLimit(uint256 amount) {
        if (amount > maxWithdrawal) revert MaxWithdrawalExceeded();
        _;
    }

    // ==============================
    //  EXTERNAL PAYABLE FUNCTIONS
    // ==============================

    /// @notice Deposits ETH into the user's personal vault.
    /// @dev Check global limit and record deposit.
    
    function deposit() external payable nonZeroDeposit {
        if (totalDeposits + msg.value > totalBankCapacity) {
            revert MaxDepositExceeded();
        }

        vaultBalance[msg.sender] += msg.value;
        totalDeposits += msg.value;
        depositCount[msg.sender]++;

        emit DepositMade(msg.sender, msg.value);
    }

    /// @notice Withdraws a specified amount of ETH from the user's vault.
    /// @param amount The amount of ETH to withdraw and uses secure transfers and custom errors.
   
   function withdraw(uint256 amount) external withinWithdrawalLimit(amount) {
        uint256 balance = vaultBalance[msg.sender];
        if (balance < amount) revert InsufficientBalance();

        unchecked {
            vaultBalance[msg.sender] = balance - amount;
            totalDeposits -= amount;
        }

        withdrawalCount[msg.sender]++;
        _safeTransfer(msg.sender, amount);

        emit WithdrawalMade(msg.sender, amount);
    }

    //===========================
    // EXTERNAL  VIEW FUNCTIONS
    //===========================
    
    /// @notice Returns the current vault balance of a given user.
    /// @param user Address of the user to query.
    /// @return The ETH balance of the user in the vault.

      
    function getBalance(address user) external view returns (uint256) {
        return vaultBalance[user];
    }

    // ==================
    // PRIVATE FUNCTIONS
    // ==================


    /// @dev Handles secure ETH transfer.
    /// @param recipient Address to which the ETH will be sent 
    ///@param amount Amount of ETH to be transferred.

    function _safeTransfer(address recipient, uint256 amount) private {
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert();
    }

    // ==================
    // RECEIVE FUNCTION
    // ==================

    /// @notice Rejects direct ETH transfers.
    receive() external payable {
        revert DirectTransferNotAllowed();
    }
}