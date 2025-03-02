// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title HKDP Stablecoin
 * @notice Decentralized stablecoin for merchant management and payments
 * @dev Implements merchant whitelist, minting/burning, and payments using OpenZeppelin
 * @custom:security-contact hopeallgood.unadvised619@passinbox.com
 */
contract HKDP is ERC20, Ownable, ReentrancyGuard {
    
    /// @dev Custom errors for gas efficiency
    error InvalidMerchantAddress();
    error MerchantNotFound();
    error InvalidUserAddress();
    error InvalidAmount();
    error NotRegisteredMerchant(address caller);
    error MerchantFrozen();
    error ETHTransferFailed();
    error ERC20TransferFailed();

    /// @dev Merchant data structure
    struct Merchant {
        uint256 printQuota;         ///< Minting quota
        uint256 totalCashReceived;  ///< Total cash received
        uint256 totalHKDPRecycled;  ///< Total HKDP recycled
        string  merchantName;        ///< Merchant name
        address merchantAddress;    ///< Merchant address
        bool isFreeze;              ///< Freeze status
    }

    /// @notice Maps merchant addresses to their information
    mapping(address merchantAddress => Merchant info) public merchantInfoMap;

    /// @notice Maps merchant addresses to their index in merchantList
    mapping(address merchantAddress => uint256 index) public merchantIndex;

    /// @notice Whitelist status of merchant addresses
    mapping(address merchantAddress => bool isWhitelisted) public isMerchant;

    /// @notice List of merchant addresses
    address[] public merchantList;

    /// @notice Total HKDP minted
    uint256 public totalMinted;

    /// @notice Total HKDP burnt
    uint256 public totalBurnt;

    /// @notice Event: Merchant frozen
    event MerchantFreeze(address indexed merchant);

    /// @notice Event: Merchant unfrozen
    event MerchantUnfreeze(address indexed merchant);

    /// @notice Event: Merchant removed
    event MerchantRemoved(address indexed merchant);

    /// @notice Event: Merchant added
    event MerchantAdded(address indexed merchant, string merchantName);

    /// @notice Event: HKDP minted
    event MintedToUser(address indexed merchant, address indexed user, uint256 amount);

    /// @notice Event: Payment processed
    event PaymentProcessed(address indexed merchant, address indexed user, uint256 amount);

    /**
     * @notice Constructor
     * @dev Initializes with ERC20, ERC20Permit, and Ownable
     */
    constructor(address owner)
        ERC20("Hong Kong Decentralized Permit", "HKDP")
        Ownable(owner)
    {}

    /**
     * @notice Confirm merchant's ownership
     * @dev Merchants-only; to allow only registered merchants
     */
    modifier onlyMerchant() {
        if (!isMerchant[msg.sender]) { revert NotRegisteredMerchant(msg.sender); } _;
    }

    /**
     * @notice Transfer contract ownership to a new address
     * @dev Owner-only; updates contract owner and emits event
     * @param newOwner Address of the new owner
     */
    function transferContractOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidUserAddress();
        emit OwnershipTransferred(owner(), newOwner);
        transferOwnership(newOwner);
    }

    /**
     * @notice Add merchant
     * @dev Owner-only; adds to whitelist and info map
     * @param printQuota Minting quota
     * @param merchantAddr Merchant address
     * @param merchantName Merchant name
     */
    function addMerchant(uint256 printQuota, address merchantAddr, string memory merchantName) external onlyOwner nonReentrant {
        if (merchantAddr == address(0)) revert InvalidMerchantAddress();
        isMerchant[merchantAddr] = true;
        merchantInfoMap[merchantAddr] = Merchant(printQuota, 0, 0, merchantName, merchantAddr, false);
        if (!isMerchant[merchantAddr]) {
            merchantIndex[merchantAddr] = merchantList.length;
            merchantList.push(merchantAddr);
        }
        emit MerchantAdded(merchantAddr, merchantName);
    }

    /**
     * @notice Remove merchant
     * @dev Owner-only; removes from whitelist and info map
     * @param merchantAddr Merchant address
     */
    function removeMerchant(address merchantAddr) external onlyOwner {
        if (!isMerchant[merchantAddr]) revert MerchantNotFound();
        emit MerchantRemoved(merchantAddr);
        uint256 index = merchantIndex[merchantAddr];
        address lastAddr = merchantList[merchantList.length - 1];
        merchantList[index] = lastAddr;
        merchantIndex[lastAddr] = index;
        merchantList.pop();
        delete merchantIndex[merchantAddr];
        delete merchantInfoMap[merchantAddr];
        isMerchant[merchantAddr] = false;
        emit MerchantRemoved(merchantAddr);
    }

    /**
     * @notice Mint HKDP tokens
     * @dev Merchant-only; mints tokens for user
     * @param user Recipient address
     * @param cashAmount Amount to mint
     */
    function mintHKDP(address user, uint256 cashAmount) external onlyMerchant nonReentrant {
        if (user == address(0)) revert InvalidUserAddress();
        Merchant storage m  = merchantInfoMap[msg.sender];
        if (cashAmount == 0 || cashAmount > m.printQuota + m.totalHKDPRecycled - m.totalCashReceived)
            revert InvalidAmount();
        if (m.isFreeze) revert MerchantFrozen();
        emit MintedToUser(msg.sender, user, cashAmount);
        _mint(user, cashAmount);
        m.totalCashReceived += cashAmount;
        totalMinted += cashAmount;
    }

    /**
     * @notice Process payment
     * @dev Merchant-only; burns user’s HKDP
     * @param user Payer address
     * @param amount Amount to pay
     */
    function payMerchant(address user, uint256 amount) external onlyMerchant nonReentrant {
        if (amount == 0 || balanceOf(user) < amount) revert InvalidAmount();
        Merchant storage m = merchantInfoMap[msg.sender];
        if (m.isFreeze) revert MerchantFrozen();
        emit PaymentProcessed(msg.sender, user, amount);
        _burn(user, amount);
        m.totalHKDPRecycled += amount;
        totalBurnt += amount;
    }

    /**
     * @notice Modify merchant state
     * @dev Owner-only; updates freeze status and quota
     * @param merchantAddr Merchant address
     * @param isFreeze Freeze status
     * @param printQuota New quota
     */
    function modMerchantState(address merchantAddr, bool isFreeze, uint256 printQuota) external onlyOwner {
        if (!isMerchant[merchantAddr]) revert MerchantNotFound();
        Merchant storage m = merchantInfoMap[merchantAddr];
        m.isFreeze = isFreeze;
        if (isFreeze) emit MerchantFreeze(merchantAddr);
        else emit MerchantUnfreeze(merchantAddr);
        m.printQuota = printQuota;
    }

    /**
     * @notice Forward ERC20 tokens
     * @dev Owner-only; transfers ERC20 to owner
     * @param token ERC20 token address
     */
    function forwardERC20(address token) external onlyOwner {
        if (token == address(0)) revert InvalidMerchantAddress();
        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        if (contractBalance == 0) revert InvalidAmount();
        bool success = IERC20(token).transfer(owner(), contractBalance);
        if (!success) revert ERC20TransferFailed();
    }

    /**
     * @notice Withdraw ETH function
     * @dev Handles ETH transfers
     */
    function withdrawETH() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        if (contractBalance > 0) {
            (bool success, ) = payable(owner()).call{value: contractBalance}("");
            if (!success) revert ETHTransferFailed();
        }
    }

    fallback() external payable {}
    receive() external payable {}
}
