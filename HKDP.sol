// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract HKDP is ERC20, ERC20Permit, Ownable, ReentrancyGuard {

    struct Merchant {
        uint256 totalCashReceived;
        uint256 totalHKDPReceived;
        string name;
        address merchantAddress;
        bool isImbalanced;
    }

    mapping(address => Merchant) public merchants;
    mapping(address => bool) public merchantWhitelist;
    address[] public merchantList; // **新增商戶列表，用於遍歷**
    event MerchantAdded(address indexed merchant, string name);
    event MerchantRemoved(address indexed merchant);
    event MintedByMerchant(address indexed merchant, address indexed user, uint256 cashAmount, uint256 hkdpMinted, bool isImbalanced);
    event PaymentProcessed(address indexed merchant, address indexed user, uint256 amount);

    constructor(address initialOwner)
        ERC20("HKDP", "HKDP")
        ERC20Permit("HKDP")
        Ownable(initialOwner)
    {}

    /// @dev Owner 增加商戶至白名單
    function addMerchant(address merchant, string memory name) external onlyOwner {
        require(merchant != address(0), "Invalid merchant address");
        require(!merchantWhitelist[merchant], "Merchant already whitelisted");
        merchantWhitelist[merchant] = true;
        merchants[merchant] = Merchant(0, 0, name, merchant, false);
        merchantList.push(merchant); // **加入商戶列表**
        emit MerchantAdded(merchant, name);
    }

    /// @dev Owner 移除商戶，並從商戶列表中刪除
    function removeMerchant(address merchant) external onlyOwner {
        require(merchantWhitelist[merchant], "Merchant not found");
        merchantWhitelist[merchant] = false;
        delete merchants[merchant];
        // **移除商戶地址 (swap and pop 來節省 gas)**
        for (uint256 i = 0; i < merchantList.length; i++) {
            if (merchantList[i] == merchant) {
                merchantList[i] = merchantList[merchantList.length - 1];
                merchantList.pop();
                break;
            }
        }
        emit MerchantRemoved(merchant);
    }

    /// @dev 商戶發起增值交易 (mint HKDP)
    function mintHKDP(address user, uint256 cashAmount) external nonReentrant {
        require(merchantWhitelist[msg.sender], "Not authorized merchant");
        require(user != address(0), "Invalid user address");
        require(cashAmount > 0, "Invalid amount");
        _mint(user, cashAmount);
        Merchant storage merchant = merchants[msg.sender];
        merchant.totalCashReceived += cashAmount;
        merchant.isImbalanced = merchant.totalCashReceived > merchant.totalHKDPReceived;
        emit MintedByMerchant(msg.sender, user, cashAmount, cashAmount, merchant.isImbalanced);
    }

    /// @dev 商戶幫用戶支付 HKDP (用戶需先 `approve`)
    function payMerchant(address user, uint256 amount) external nonReentrant {
        require(merchantWhitelist[msg.sender], "Not a registered merchant");
        require(amount > 0 && balanceOf(user) > amount, "Invalid amount");
        _transfer(user, msg.sender, amount);
        Merchant storage merchant = merchants[msg.sender];
        merchant.totalHKDPReceived += amount;
        merchant.isImbalanced = merchant.totalCashReceived > merchant.totalHKDPReceived;
        emit PaymentProcessed(msg.sender, user, amount);
    }

    /// @notice 查詢哪些商戶的現金收入多於收到的 HKDP
    /// @return 商戶地址陣列
    function getImbalancedMerchants() external view returns (address[] memory) {
        uint256 count = 0;
        // **第一輪遍歷：計算符合條件的商戶數量**
        for (uint256 i = 0; i < merchantList.length; i++) {
            if (merchants[merchantList[i]].isImbalanced) {
                count++;
            }
        }
        // **第二輪遍歷：收集符合條件的商戶**
        address[] memory imbalancedMerchants = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < merchantList.length; i++) {
            if (merchants[merchantList[i]].isImbalanced) {
                imbalancedMerchants[index] = merchantList[i];
                index++;
            }
        }
        return imbalancedMerchants;
    }
}
