// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

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
    error InvalidSpendingRebate();
    error InvalidUserAddress();
    error InvalidAmount();
    error NotRegisteredMerchant(address caller);
    error MerchantFrozen();
    error WithdrawFailed();

    /// @dev Merchant data structure
    struct Merchant {
        uint256 printQuota;         ///< Minting quota
        uint256 totalCashReceived;  ///< Total cash received
        uint256 totalHKDPRecycled;  ///< Total HKDP recycled
        uint256 spendingRebate;     ///< Merchant address
        string  merchantName;       ///< Merchant name
        bool isFreeze;              ///< Freeze status
    }

    /// @notice Maps merchant addresses to their information
    mapping(address merchant => Merchant info) public merchantInfoMap;

    /// @notice Whitelist status of merchant addresses
    mapping(address merchant => bool isWhitelisted) public isMerchant;

    /// @notice Maps merchant addresses to their index in merchantList
    mapping(uint256 index => address merchant) public merchantByIndex;

    /// @notice Total HKDP burnt
    uint256 public totalMerchants;

    /// @notice Total HKDP minted
    uint256 public totalMinted;

    /// @notice Total HKDP burnt
    uint256 public totalBurnt;

    /// @notice Event: Merchant frozen
    event MerchantFreeze(address indexed merchant);

    /// @notice Event: Merchant unfrozen
    event MerchantUnfreeze(address indexed merchant);

    /// @notice Event: Merchant added
    event MerchantAdded(address indexed merchant, string merchantName);

    /// @notice Event: HKDP minted
    event MintedToUser(address indexed merchant, address indexed user, uint256 amount);

    /// @notice Event: Payment processed
    event PaymentProcessed(address indexed merchant, address indexed user, uint256 amount);

    /// @notice Event: Spending Rebate
    event SpendingRebate(address indexed merchant, address indexed user, uint256 amount, uint256 percentage);

    /**
     * @notice Constructor
     * @dev Initializes with ERC20, and Ownable
     */
    constructor(address owner)
        ERC20("Hong Kong Decentralized Permit (S ver.)", "HKDP")
        Ownable(owner)
    {}

    /**
     * @notice Confirm merchant's ownership
     * @dev Merchants-only; to allow only registered merchants
     */
    modifier onlyMerchant() {
        if (!isMerchant[_msgSender()]) { revert NotRegisteredMerchant(_msgSender()); } _;
    }

    /**
     * @notice Add merchant
     * @dev Owner-only; adds to whitelist and info map
     * @param printQuota Minting quota
     * @param merchantName Merchant name
     */
    function addMerchant(uint256 printQuota, address merchantAddr, string memory merchantName) external onlyOwner nonReentrant {
        if (merchantAddr == address(0) || isMerchant[merchantAddr]) revert InvalidMerchantAddress();
        emit MerchantAdded(merchantAddr, merchantName);
        isMerchant[merchantAddr] = true;
        merchantByIndex[totalMerchants] = merchantAddr;
        totalMerchants += 1;
        merchantInfoMap[merchantAddr] = Merchant(printQuota, 0, 0, 0, merchantName, false);
    }

    /**
     * @notice Modify merchant state
     * @dev Owner-only; updates freeze status and quota
     * @param merchantAddr Merchant address
     * @param isFreeze Freeze status
     * @param printQuota New quota
     * @param spendingRebate Merchant Rebate Rate
     */
    function modMerchantState(address merchantAddr, bool isFreeze, uint256 printQuota, uint256 spendingRebate) external onlyOwner {
        if (spendingRebate > 10) revert InvalidSpendingRebate();
        Merchant storage m = merchantInfoMap[merchantAddr];
        if (m.isFreeze != isFreeze) {
            if (isFreeze) emit MerchantFreeze(merchantAddr);
            else emit MerchantUnfreeze(merchantAddr);
        }
        m.isFreeze = isFreeze;
        m.printQuota = printQuota;
        m.spendingRebate = spendingRebate;
    }

    /**
     * @notice Mint HKDP tokens
     * @dev Merchant-only; mints tokens for user
     * @param user Recipient address
     * @param cashAmount Amount to mint
     */
    function mintHKDP(address user, uint256 cashAmount) external onlyMerchant nonReentrant {
        if (user == address(0)) revert InvalidUserAddress();
        Merchant storage m  = merchantInfoMap[_msgSender()];
        if (cashAmount == 0 || cashAmount > m.printQuota + m.totalHKDPRecycled - m.totalCashReceived)
            revert InvalidAmount();
        if (m.isFreeze) revert MerchantFrozen();
        emit MintedToUser(_msgSender(), user, cashAmount);
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
        Merchant storage m = merchantInfoMap[_msgSender()];
        if (m.isFreeze) revert MerchantFrozen();
        emit PaymentProcessed(_msgSender(), user, amount);
        emit SpendingRebate(_msgSender(), user, (amount * m.spendingRebate / 100), m.spendingRebate);
        uint256 finalAmount = (amount * (100 - m.spendingRebate) / 100);
        _burn(user, finalAmount);
        m.totalHKDPRecycled += finalAmount;
        totalBurnt += finalAmount;
    }

    /**
     * @notice Withdraw ETH and ERC20 tokens
     * @dev Owner-only; transfers assets to owner
     * @param token ERC20 token address
     */
    function withdrawTokensAndETH(address token) external onlyOwner {
        if (token == address(0) && address(this).balance > 0) {
            (bool success, ) = payable(owner()).call{value: address(this).balance}("");
            if (!success) revert WithdrawFailed();
        } else {
            uint256 contractBalance = IERC20(token).balanceOf(address(this));
            if (contractBalance == 0) revert InvalidAmount();
            bool success = IERC20(token).transfer(owner(), contractBalance);
            if (!success) revert WithdrawFailed();
        }
    }

    /**
    * @notice Receive function for plain ETH transfers
    * @dev Allows contract to receive ETH without data
    */
    receive() external payable {}

}
