// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title HKDC Stablecoin
 * @notice HKDC 是一個商戶支持的穩定幣系統。
 * @dev 此合約允許商戶鑄造 HKDC 並處理支付。
 * @custom:security-contact wyc.emote732@passinbox.com
 */
contract HKDC is ERC20, ERC20Permit, Ownable, ReentrancyGuard {

    /// @dev 自訂錯誤，以節省 Gas
    error InvalidMerchantAddress();
    error MerchantNotFound();
    error NotAuthorizedMerchant();
    error InvalidUserAddress();
    error InvalidAmount();
    error NotRegisteredMerchant();
    error MerchantFrozen();  // 新增錯誤: 商戶已被雪藏

    /// @dev 商戶結構
    struct Merchant {
        uint256 totalCashReceived;  ///< 商戶收到的現金總額
        uint256 totalHKDCRecycled;  ///< 商戶回收的 HKDC 總額
        string name;                ///< 商戶名稱
        address merchantAddress;    ///< 商戶地址
        bool isImbalanced;          ///< 是否發生現金與 HKDC 不匹配的狀況
        bool isFreeze;              ///< 是否被雪藏
    }

    /// @notice 儲存商戶資料的映射
    mapping(address merchantAddress => Merchant merchantInfo) public merchants;

    /// @notice 商戶白名單
    mapping(address merchantAddress => bool isWhitelisted) public merchantWhitelist;

    /// @dev 商戶列表（用於迭代）
    address[] public merchantList;

    /// @notice 已鑄造的 HKDC 總額
    uint256 public totalMinted;
    
    /// @notice 已銷毀的 HKDC 總額
    uint256 public totalBurnt;

    /// @notice 事件: 新增商戶
    event MerchantAdded(address indexed merchant, string name);

    /// @notice 事件: 移除商戶
    event MerchantRemoved(address indexed merchant);

    /// @notice 事件: 商戶鑄造 HKDC
    event MintedByMerchant(
        address indexed merchant, 
        address indexed user, 
        uint256 cashAmount, 
        uint256 HKDCMinted, 
        bool isImbalanced
    );

    /// @notice 事件: 用戶支付 HKDC 給商戶
    event PaymentProcessed(address indexed merchant, address indexed user, uint256 amount);

    /// @notice 事件: 商戶被雪藏
    event MerchantFreeze(address indexed merchant);

    /// @notice 事件: 商戶被解凍
    event MerchantUnfreeze(address indexed merchant);

    /**
     * @notice 建構函數
     * @param initialOwner 合約擁有者
     */
    constructor(address initialOwner)
        ERC20("Hong Kong Decentralized Currency", "HKDC")
        ERC20Permit("Hong Kong Decentralized Currency")
        Ownable(initialOwner)
    {}

    /**
     * @notice 添加或更新商戶
     */
    function addMerchant(address merchant, string memory name) external onlyOwner {
        if (merchant == address(0)) revert InvalidMerchantAddress();
        merchantWhitelist[merchant] = true;
        merchants[merchant] = Merchant(0, 0, name, merchant, false, false);
        bool found;
        uint256 length = merchantList.length;
        for (uint256 i; i < length; ++i) {
            if (merchantList[i] == merchant) {
                found = true;
                break;
            }
        }
        if (!found) {
            merchantList.push(merchant);
        }
        emit MerchantAdded(merchant, name);
    }

    /**
     * @notice 移除商戶
     */
    function removeMerchant(address merchant) external onlyOwner {
        if (!merchantWhitelist[merchant]) revert MerchantNotFound();
        merchantWhitelist[merchant] = false;
        delete merchants[merchant];
        // Gas-efficient removal
        uint256 length = merchantList.length;
        for (uint256 i; i < length; ++i) {
            if (merchantList[i] == merchant) {
                merchantList[i] = merchantList[length - 1];
                merchantList.pop();
                break;
            }
        }
        emit MerchantRemoved(merchant);
    }

    /**
     * @notice 鑄造 HKDC
     */
    function mintHKDC(address user, uint256 cashAmount) external nonReentrant {
        if (!merchantWhitelist[_msgSender()]) revert NotAuthorizedMerchant();
        if (user == address(0)) revert InvalidUserAddress();
        if (cashAmount == 0) revert InvalidAmount();
        Merchant storage merchant = merchants[_msgSender()];
        if (merchant.isFreeze) revert MerchantFrozen();  // 檢查商戶是否雪藏
        _mint(user, cashAmount);
        merchant.totalCashReceived += cashAmount;
        merchant.isImbalanced = merchant.totalCashReceived > merchant.totalHKDCRecycled;
        totalMinted += cashAmount;
        emit MintedByMerchant(_msgSender(), user, cashAmount, cashAmount, merchant.isImbalanced);
    }

    /**
     * @notice 用戶支付 HKDC 給商戶
     */
    function payMerchant(address user, uint256 amount) external nonReentrant {
        if (!merchantWhitelist[_msgSender()]) revert NotRegisteredMerchant();
        if (amount == 0 || balanceOf(user) < amount) revert InvalidAmount();
        Merchant storage merchant = merchants[_msgSender()];
        if (merchant.isFreeze) revert MerchantFrozen();  // 檢查商戶是否雪藏
        _burn(user, amount);
        merchant.totalHKDCRecycled += amount;
        merchant.isImbalanced = merchant.totalCashReceived > merchant.totalHKDCRecycled;
        totalBurnt += amount;
        emit PaymentProcessed(_msgSender(), user, amount);
    }

    /**
     * @notice 雪藏商戶，使其無法鑄造和接收 HKDC。
     * @dev 只能由合約擁有者呼叫
     */
    function freezeMerchant(address merchant) external onlyOwner {
        if (!merchantWhitelist[merchant]) revert MerchantNotFound();
        merchants[merchant].isFreeze = true;
        emit MerchantFreeze(merchant);
    }

    /**
     * @notice 解凍商戶，使其恢復正常運營。
     * @dev 只能由合約擁有者呼叫
     */
    function unfreezeMerchant(address merchant) external onlyOwner {
        if (!merchantWhitelist[merchant]) revert MerchantNotFound();
        merchants[merchant].isFreeze = false;
        emit MerchantUnfreeze(merchant);
    }

    /**
     * @notice `fallback` 允許合約接收 ETH，並自動轉帳給 `owner`
     */
    fallback() external payable {
        _forwardETH();
    }

    /**
     * @notice `receive` 允許接收 ETH，並自動轉帳給 `owner`
     */
    receive() external payable {
        _forwardETH();
    }

    /**
     * @notice 內部函數：將收到的 ETH 自動轉帳到 `owner`
     */
    function _forwardETH() internal {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(owner()).call{value: balance}("");
            require(success, "ETH transfer failed");
        }
    }

    /**
     * @notice 允許任何人將 ERC20 代幣轉入，並立即自動轉帳給 `owner`
     * @param token ERC20 代幣地址
     */
    function forwardERC20(address token) external onlyOwner {
        if (token == address(0)) revert InvalidMerchantAddress();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert InvalidAmount();
        bool success = IERC20(token).transfer(owner(), balance);
        if (!success) revert("ERC20 transfer failed");
    }
}
