// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title HKDP Stablecoin
 * @notice HKDP is a merchant-backed stablecoin system.
 * @dev This contract allows merchants to mint HKDP and process payments.
 * @custom:security-contact security@example.com
 */
contract HKDP is ERC20, ERC20Permit, Ownable, ReentrancyGuard {
    
    /// @dev Custom errors for gas optimization
    error InvalidMerchantAddress();
    error MerchantAlreadyWhitelisted();
    error MerchantNotFound();
    error NotAuthorizedMerchant();
    error InvalidUserAddress();
    error InvalidAmount();
    error NotRegisteredMerchant();

    /// @dev Struct to store merchant details
    struct Merchant {
        uint256 totalCashReceived;
        uint256 totalHKDPReceived;
        string name;
        address merchantAddress;
        bool isImbalanced;
    }

    /// @dev Mapping of merchants with named parameters
    mapping(address merchantAddress => Merchant merchantInfo) public merchants;
    mapping(address merchantAddress => bool isWhitelisted) public merchantWhitelist;

    /// @dev List of merchants for iteration
    address[] public merchantList;

    /// @dev Events for state changes
    event MerchantAdded(address indexed merchant, string name);
    event MerchantRemoved(address indexed merchant);
    event MintedByMerchant(address indexed merchant, address indexed user, uint256 cashAmount, uint256 hkdpMinted, bool isImbalanced);
    event PaymentProcessed(address indexed merchant, address indexed user, uint256 amount);

    /**
     * @notice Contract constructor.
     * @dev Initializes ERC20, ERC20Permit, and Ownable.
     * @param initialOwner The address of the contract owner.
     */
    constructor(address initialOwner)
        ERC20("HKDP", "HKDP")
        ERC20Permit("HKDP")
        Ownable(initialOwner)
    {}

    /**
     * @notice Adds a merchant to the whitelist.
     * @dev Only the contract owner can add merchants.
     * @param merchant The merchant's address.
     * @param name The merchant's name.
     */
    function addMerchant(address merchant, string memory name) external onlyOwner {
        if (merchant == address(0)) revert InvalidMerchantAddress();
        if (merchantWhitelist[merchant]) revert MerchantAlreadyWhitelisted();

        merchantWhitelist[merchant] = true;
        merchants[merchant] = Merchant(0, 0, name, merchant, false);
        merchantList.push(merchant);

        emit MerchantAdded(merchant, name);
    }

    /**
     * @notice Removes a merchant from the whitelist.
     * @dev Uses gas-efficient `swap and pop` technique.
     * @param merchant The merchant's address to remove.
     */
    function removeMerchant(address merchant) external onlyOwner {
        if (!merchantWhitelist[merchant]) revert MerchantNotFound();

        merchantWhitelist[merchant] = false;
        delete merchants[merchant];

        // Gas-efficient removal using `swap and pop`
        uint256 length = merchantList.length;
        for (uint256 i = 0; i < length; ++i) {
            if (merchantList[i] == merchant) {
                merchantList[i] = merchantList[length - 1];
                merchantList.pop();
                break;
            }
        }

        emit MerchantRemoved(merchant);
    }

    /**
     * @notice Mints HKDP tokens for a user.
     * @dev Only whitelisted merchants can mint tokens.
     * @param user The user receiving the HKDP tokens.
     * @param cashAmount The amount of HKDP to mint.
     */
    function mintHKDP(address user, uint256 cashAmount) external nonReentrant {
        if (!merchantWhitelist[_msgSender()]) revert NotAuthorizedMerchant();
        if (user == address(0)) revert InvalidUserAddress();
        if (cashAmount == 0) revert InvalidAmount();

        _mint(user, cashAmount);

        Merchant storage merchant = merchants[_msgSender()];
        merchant.totalCashReceived += cashAmount;
        merchant.isImbalanced = merchant.totalCashReceived > merchant.totalHKDPReceived;

        emit MintedByMerchant(_msgSender(), user, cashAmount, cashAmount, merchant.isImbalanced);
    }

    /**
     * @notice Allows a merchant to receive HKDP from a user.
     * @dev User must approve HKDP transfer before calling this function.
     * @param user The user paying the merchant.
     * @param amount The amount of HKDP to transfer.
     */
    function payMerchant(address user, uint256 amount) external nonReentrant {
        if (!merchantWhitelist[_msgSender()]) revert NotRegisteredMerchant();
        if (amount == 0 || balanceOf(user) < amount) revert InvalidAmount();

        _transfer(user, _msgSender(), amount);

        Merchant storage merchant = merchants[_msgSender()];
        merchant.totalHKDPReceived += amount;
        merchant.isImbalanced = merchant.totalCashReceived > merchant.totalHKDPReceived;

        emit PaymentProcessed(_msgSender(), user, amount);
    }

    /**
     * @notice Returns a list of merchants with cash inflows exceeding HKDP received.
     * @return An array of merchant addresses with imbalances.
     */
    function getImbalancedMerchants() external view returns (address[] memory) {
        uint256 count;
        uint256 length = merchantList.length; // Cache array length

        // First pass: count merchants with imbalances
        for (uint256 i = 0; i < length; ++i) {
            if (merchants[merchantList[i]].isImbalanced) {
                ++count;
            }
        }

        // Second pass: collect imbalanced merchants
        address[] memory imbalancedMerchants = new address[](count);
        uint256 index;

        for (uint256 i = 0; i < length; ++i) {
            if (merchants[merchantList[i]].isImbalanced) {
                imbalancedMerchants[index] = merchantList[i];
                ++index;
            }
        }

        return imbalancedMerchants;
    }
}
