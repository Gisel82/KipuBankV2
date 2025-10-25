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
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract KipuBank is AccessControl, ReentrancyGuard{
    using SafeERC20 for IERC20;
  
    // ======================
    //         ROLES
    // ======================

    bytes32 public constant BANK_MANAGER_ROLE = keccak256("BANK_MANAGER_ROLE");
    
    // =============================
    // IMMUTABLE/CONSTANT VARIABLES
    // =============================
    

    /// @notice Máximo permitido por transacción de retiro.
    uint256 public immutable maxWithdrawal;

    /// @notice Capacidad total del banco en ETH.
    uint256 public immutable totalBankCapacityUSD;

    ///@notice Oraculo chailink ETH/USD
    AggregatorV3Interface public immutable ethUsdFeed;
    
    
    // ==============================
    //        ESTADO MAPPINGS
    // ==============================

    mapping(address => AggregatorV3Interface) public priceFeedForToken; 
    
    /// @notice User balances stored in the vault.
    mapping(address => mapping (address => uint256)) private vaultBalance;

    /// @notice Number of deposits made by each user.
    mapping(address => uint256) public depositCount;

    /// @notice Number of withdrawals made by each user.
    mapping(address => uint256) public withdrawalCount;


    address[] private supportedTokens; //Supported tokens
    mapping(address => bool) private isTokenSupported;

    // ============================
    //           TOTALES
    // ============================

    /// @notice Total actual de todos los depósitos en el contrato.

    uint256 public totalDepositsUSD; //USDC-like (6 decimals)
    
   
    // ===============================
    //             EVENTS
    // ===============================


    /// @notice Emitted when a user deposits an ETh or token into the contract.
    /// @param user is the user's address. 
    /// @param amount Amount of ETH deposited.
    /// @param token what token it was.
    /// @param usdValue6 its equivalent value in USD (with 6 decimal places).

    event DepositMade(address indexed user, address indexed token, uint256 amount, uint256 usdValue6);
    
    /// @notice It is issued when the user makes a successful withdrawal.
    /// @param user the user's address 
    /// @param amount Amount of ETH withdrawn.
    
    event WithdrawalMade(address indexed user, address indexed token, uint256 amount, uint256 usdValue6);
    
    /// @notice Emitted when an administrator (BANK_MANAGER_ROLE) adds support for a new ERC-20 token
    event TokenSupported(address indexed  token);
    
    /// @notice Emitted when support for a previously accepted token is removed.
    event TokenUnsupported(address indexed token);

    /// @notice It is issued when a new oracle is assigned to a token, used to obtain its price in USD
    event PriceFeedSet(address indexed token, address indexed feed);

    /// @notice Emitted when the oracle associated with a token is deleted.
    event PriceFeedRemoved(address indexed token);

    /// @notice Emitted when the bank's main parameters are updated:
    event ParamentersUpdated(uint256 newMaxWithdrawalWei, uint256 newCapacityUSD);
    
    // ==============================
    //         CUSTOM ERRORS
    // ==============================

    /// @notice It is launched when a deposit exceeds the global banking capacity.
    ///error MaxDepositExceeded();
     
    /// @notice When a withdrawal exceeds the transaction limit.
    error MaxWithdrawalExceeded();

    /// @notice When a user tries to withdraw more than their balance
    error InsufficientBalance();

    /// @notice When trying to deposit 0 ETH.
    error ZeroDepositNotAllowed();

    /// @notice Thrown if you try to send ETH directly to the contract.
    error DirectTransferNotAllowed();
    
    /// @notice It is thrown if someone calls the contract with incorrect data.
    error DirectCallNotAllowed();

    /// @notice It is thrown if the token used is not supported by the bank
    error TokenNotSupported();

    /// @notice Thrown if the maxRetiro value in the constructor is invalid.
    error MaximumWithdrawalInvalid();
    
    /// @notice Thrown if an ETH or token transfer fails
    error TransferFailed();
    
    /// @notice Thrown if the bank capacity in the constructor is invalid.
    error InvalidBankCapacity();
    
    /// @notice It is raised when the amount sent or requested is invalid
    error InvalidAmount();
    
    /// @notice It is thrown if the oracle address
    error InvalidOracle();
    
    ///@notice It is thrown if the Bank Cap Exceeded
    error BankCapExceeded();

   
    // ==============================
    //          CONSTRUCTOR
    // ==============================

    /// @notice Initializes the contract with the specified limits.
    /// @param _maxWithdrawal Maximum withdrawal limit per transaction.
    /// @param _totalCapacityUSD Total ETH capacity of the bank in USD.
    
    constructor(uint256 _maxWithdrawal, uint256 _totalCapacityUSD, address _ethUsdFeed) {
        if (_maxWithdrawal == 0) revert MaximumWithdrawalInvalid();
        if (_totalCapacityUSD == 0) revert InvalidBankCapacity();
        if (_ethUsdFeed == address(0)) revert InvalidOracle(); 

        maxWithdrawal = _maxWithdrawal;
        totalBankCapacityUSD = _totalCapacityUSD;
        ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);

        // Otorga roles al deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BANK_MANAGER_ROLE, msg.sender);
    }

    // ======================================================
    //              ADMINISTRATIVE FUNCTIONS
    // ======================================================

    /// @notice Agrega soporte para un token ERC20 
    function supportToken(address token, address feed) external onlyRole(BANK_MANAGER_ROLE) {
        if (token == address(0)) revert TokenNotSupported();
        if (!isTokenSupported[token]) {
            supportedTokens.push(token);
            isTokenSupported[token] = true;
            emit TokenSupported(token);
        }
        if (feed != address(0)) {
            priceFeedForToken[token] = AggregatorV3Interface(feed);
            emit PriceFeedSet(token, feed);
        }
    }
    
    /// @notice The function marks a token as unsupported and can only be executed by a user with the BANK_MANAGER_ROLE role, preventing any user from disabling support for a token.
    function unsupportToken(address token) external onlyRole(BANK_MANAGER_ROLE) {
        if (!isTokenSupported[token]) revert TokenNotSupported();
        isTokenSupported[token] = false;
       
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[supportedTokens.length - 1];
                supportedTokens.pop();
                break;
            }
        }
        delete priceFeedForToken[token];
        emit TokenUnsupported(token);
        emit PriceFeedRemoved(token);
    }

    function setPriceFeed(address token, address feed) external onlyRole(BANK_MANAGER_ROLE) {
        if (token == address(0)) revert InvalidOracle(); // ETH feed viene del ethUsdFeed inmutable
        priceFeedForToken[token] = AggregatorV3Interface(feed);
        emit PriceFeedSet(token, feed);
    }


    // ==============================
    //           DEPOSITS
    // ==============================

    /// @notice Deposits ETH into the user's personal vault.
    /// @dev Check global limit and record deposit.
    /// @dev allows a user to deposit ETH or a token.
    /// @dev updates their balance and total in USD.
    /// @dev emits a deposit event.
    
    function deposit(address token, uint256 amount) external payable nonReentrant {
        uint256 usdValue6;
        if (token == address(0)) {
           if (msg.value == 0) revert ZeroDepositNotAllowed();
            usdValue6 = _convertEthToUSD(msg.value);
            vaultBalance[msg.sender][address(0)] += msg.value;
        }else{
           if (!isTokenSupported[token]) revert TokenNotSupported();
           if (amount == 0) revert ZeroDepositNotAllowed();
           IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
           usdValue6 = _convertTokenToUSD(token, amount);
           vaultBalance[msg.sender][token] += amount; 
        }
        
        uint256 newTotalUSD = totalDepositsUSD + usdValue6;
        if (newTotalUSD > totalBankCapacityUSD) revert BankCapExceeded();
        totalDepositsUSD = newTotalUSD;
        depositCount[msg.sender]++;

        emit DepositMade(msg.sender, token, token == address(0) ? msg.value : amount, usdValue6);
    }

    // ==============================
    //           WITHDRAW
    // ==============================

    /// @notice Withdraws a specified amount of ETH from the user's vault.
    /// @param amount The amount of ETH to withdraw and uses secure transfers and custom errors.
    /// @dev user to withdraw ETH or token.
    /// @dev check limits and balance. 
    /// @dev update balances and total in USD and perform the secure transfer.
    /// @dev issue a withdrawal event.
    
   function withdraw(address token, uint256 amount) external nonReentrant {
        
        if(amount == 0) revert InvalidAmount();
        if(amount > maxWithdrawal) revert MaxWithdrawalExceeded();
        
        uint256 balance = vaultBalance[msg.sender][token];
        if (balance < amount) revert InsufficientBalance();
        
        uint256 usdValue6 = token == address(0) ? _convertEthToUSD(amount) : _convertTokenToUSD(token, amount);

        vaultBalance[msg.sender][token] = balance - amount;
        totalDepositsUSD -= usdValue6;
        withdrawalCount[msg.sender]++;
        
        if (token == address(0)) {
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit WithdrawalMade(msg.sender, token, amount, usdValue6);
    }

    //===========================
    // FUNCIONES DE CONSULTA
    //===========================
    
    /// @notice Returns the current vault balance of a given user.
    /// @param user Address of the user to query.
    /// @return The ETH balance of the user in the vault.

      
    function getUserBalance(address user, address token) external view returns (uint256) {
        return vaultBalance[user][token];
    }
    
    function getSupportedTokens() external  view returns(address[] memory){
        return supportedTokens;
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

    
    // ===========================
    //    ORACULO DE CHAINLINK
    // ===========================

     function getLatestEthPrice() public view returns (uint256) {
        (, int256 price, , , ) = ethUsdFeed.latestRoundData();
        // price viene con 8 decimales
        return uint256(price);
    }

    
    //@notice Convierte ETH depositado a USD (según Chainlink).
    
    function getTotalDepositsInUSD(address user) external view returns (uint256 totalUSD){
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            uint256 balance = vaultBalance[user][token];
            if (balance > 0) totalUSD += _convertTokenToUSD(token, balance);
        }

        totalUSD += _convertEthToUSD(vaultBalance[user][address(0)]);
    }
    
    // =========================
    //     INTERNAL HELPERS
    // =========================
    
    function _convertEthToUSD(uint256 amount) internal view returns (uint256) {
        uint256 price = getLatestEthPrice(); // 8 decimales
        return (amount * price) / 1e8; // USD 6 decimales
    }

    function _convertTokenToUSD(address token, uint256 amount) internal view returns (uint256) {
        AggregatorV3Interface feed = priceFeedForToken[token];
        if (address(feed) == address(0)) revert InvalidOracle();
        (, int256 price, , , ) = feed.latestRoundData();
        uint8 decimals = IERC20Metadata(token).decimals();
        uint256 normalized = _normalizeToUSDCDecimals(amount, decimals);
        return (normalized * uint256(price)) / 1e8;
    }
    
    // ================================
    //    NORMALIZACION DE DECIMALES
    // ================================
     
    /// @notice Convierte montos con distintos decimales a los de USDC (6 decimales).
     
    function _normalizeToUSDCDecimals(uint256 amount, uint8 tokenDecimals) internal pure returns (uint256){
        if (tokenDecimals > 6) {
            return amount / (10 ** (tokenDecimals - 6));
        } else if (tokenDecimals < 6) {
            return amount * (10 ** (6 - tokenDecimals));
        } else {
            return amount;
        }
    }
  
    // ================================
    //        RECEPCION DE ETH
    // ================================

    receive() external payable {
        revert DirectTransferNotAllowed();
    }

    fallback() external payable {
        revert DirectCallNotAllowed();
    }
}