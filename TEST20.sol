// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;



import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";



/**
 * @title TEST Token
 * @dev An ERC20 token with a built-in liquidity pool mechanism, claimable airdrops, and Pay-to-Earn functionality.
 *      This contract allows users to buy and sell TEST tokens with ETH, claim airdrops, and earn rewards through payments.
 *      Built on OpenZeppelin's ERC20 and ReentrancyGuard for security and reliability.
 */
contract TEST is ERC20, ReentrancyGuard {



    /**
     * @dev Events to log important actions on-chain within the TEST ecosystem.
     */
    event TESTClaimed (address indexed claimer,uint256 tokenAmount);
    event TESTBought  (address indexed buyer,  uint256 ethAmount,   uint256 tokenAmount);
    event TESTSold    (address indexed seller, uint256 tokenAmount, uint256 ethAmount  );



    /**
     * @dev Constructor to mint initial token supply.
     *      - 50% of the total supply is allocated to the TEST team and partners.
     *      - 50% is reserved in the contract for liquidity and transactions.
     */
    constructor() ERC20("TEST", "TEST") {
        // TESTDAO - Team & Partners Foundation Reserve
        _mint(_msgSender(), 850000 * 10 ** decimals()); // 85% of total supply for team and our partners 
        // TESTDAO - Internal Swapping Pool Reserve
        _mint(address(this), 150000 * 10 ** decimals());
    }



    /**
     * @dev Public state variables tracking token circulation, claimable supply, and slippage percentage.
     * 計算 TEST 在合約儲備外的流通總量 ( 對照預發非合約帳戶代幣儲備數量 )
     * Calculate the circulation of TEST outsdie the main contract LP.
     */
    uint256 public circulatingSupply = 850000 * 10 ** decimals();
    uint256 public claimable = 10000 * 10 ** decimals();
    uint256 public slippage = 1;



    /**
     * @notice Calculates the amount of TEST tokens a user will receive when purchasing with 1 ETH.
     * @return The number of TEST tokens the user will receive after applying slippage.
     */
    function calculatePurchaseAmount() public view returns (uint256) {

        // 計算購買金額，包含 slippage 的費用
        // Calculate purchase amount including a slippage fee
        // 1ETH for 0.1% remaining tokens in LP
        return (1 * balanceOf(address(this)) * (100 - slippage)) / ((10 ** decimals()) * 100000);
    }



    /**
     * @dev Calculates the amount of ETH that will be received when selling each TEST.
     * @return The amount of ETH the seller will receive.
     */
    function calculateSellAmount() public view returns (uint256) {

        // 確保池中有TEST代幣
        // Ensure there is ETH in the pool
        require( address(this).balance > 0, "No ETH in pool");

        // 計算賣出金額，為了確保合約內的所有 coin 能夠提取，提取並沒有手續費
        // Calculate sell amount without slippage
        return (1 * 10 ** decimals() * address(this).balance) / circulatingSupply;
    }



    /**
     * @dev Allows a user to sell TEST tokens in exchange for ETH.
     * @param tokenAmount The amount of TEST tokens to sell.
     */
    function sellTEST(uint256 tokenAmount) public nonReentrant {

        // 確保賣家有足夠的TEST代幣
        // Ensure the seller has sufficient TEST balance
        require(balanceOf(_msgSender()) >= tokenAmount * 10 ** decimals(), "Insufficient TEST balance");
        uint256 ethAmount = tokenAmount * calculateSellAmount();

        // 確保合約有足夠的ETH儲備
        // Ensure there is sufficient ETH in the reserve
        require(ethAmount <= address(this).balance, "Insufficient ETH in the reserve");

        // 轉移TEST代幣給合約
        // Transfer TEST tokens to the contract
        circulatingSupply -= tokenAmount * 10 ** decimals();
        _transfer(_msgSender(), address(this), tokenAmount * 10 ** decimals());

        // 使用call方法傳送ETH給賣家，取代transfer方法
        // Use call method to send ETH to the seller, replacing transfer
        (bool sent, ) = payable(_msgSender()).call{value: ethAmount}("");
        require(sent, "Failed to send ETH");

        // 觸發銷售事件
        // Trigger the sale event
        emit TESTSold(_msgSender(), tokenAmount * 10 ** decimals(), ethAmount);
    }



    /**
     * @dev Allows a user to claim a TEST airdrop, with an optional referral bonus.
     * @param friend The address of the referrer, if any.
     */
    function claimTEST(address friend) public nonReentrant {
        
        // 確保仍有可領取的 TEST 代幣  
        // Ensure there are still TEST tokens available for claim  
        require(claimable > 0, "No more tokens for claim.");

        // 每次領取 0.01% 的可領取總量  
        // Each claim grants 0.01% of the claimable pool  
        uint256 amount = claimable / 10000;
        
        // 確保領取數量有效  
        // Ensure the claim amount is not too small  
        require(amount > 0, "Claim amount is too small");

        // 如果提供了推薦好友，且不是自己  
        // If a referral friend is provided and is not the caller  
        if (friend != address(0) && friend != _msgSender()) {

            // 計算推薦好友獎勵 (10% 額外獎勵)  
            // Calculate referral reward (10% extra bonus)  
            uint256 friendBonus = (amount * 10) / 100;

            // 轉移 10% 獎勵給推薦人  
            // Transfer 10% reward to the referrer  
            _transfer(address(this), friend, friendBonus);

            // 轉移領取者的代幣，包含 10% 額外獎勵  
            // Transfer claimed tokens to the claimer, including a 10% bonus  
            _transfer(address(this), _msgSender(), amount * 11 / 10);

            // 更新可領取數量  
            // Update claimable supply  
            claimable -= (amount * 11 / 10 + friendBonus);
            
            // 更新流通供應量  
            // Update circulating supply  
            circulatingSupply += (amount * 11 / 10 + friendBonus);

            // 觸發領取事件，記錄推薦人獲得的獎勵  
            // Emit event to log the referral bonus  
            emit TESTClaimed(friend, friendBonus);
            
        } else {

            // 如果沒有推薦人，則只發送基礎領取金額  
            // If no referrer, transfer only the base claim amount  
            _transfer(address(this), _msgSender(), amount);

            // 更新可領取數量  
            // Update claimable supply  
            claimable -= amount;

            // 更新流通供應量  
            // Update circulating supply  
            circulatingSupply += amount;
        }

        // 觸發領取事件，記錄領取人獲得的數量  
        // Emit event to log the claimed amount  
        emit TESTClaimed(_msgSender(), amount);
    }



    /**
     * @dev Allows users to buy TEST tokens with ETH, with an optional referral bonus.
     * @param friend The referrer address, if applicable.
     */
    function buyTEST(address friend) public payable nonReentrant {

        // 確保合約池內仍有 TEST 代幣可供購買  
        // Ensure there are still TEST tokens available in the contract pool  
        require(balanceOf(address(this)) > 0, "No more tokens available.");

        // 限制單筆交易金額不得超過 99 ETH  
        // Limit each transaction to a maximum of 99 ETH  
        require(msg.value <= 99 * 10 ** decimals(), "Each tx can't be >99 ETH.");

        // 計算購買的 TEST 數量，包含滑點調整 ( 1 native coin => 0.1% total supply - slippage )
        // Calculate the amount of TEST to be bought, considering slippage  
        uint256 amount = msg.value * calculatePurchaseAmount();

        // 計算推薦人獎勵 (10%)  
        // Calculate referral bonus (10%)  
        uint256 friendBonus = (amount * 10) / 100;

        // 如果提供了推薦人，且不是自己  
        // If a referral friend is provided and is not the caller  
        if (friend != address(0) && friend != _msgSender()) {

            // 更正增加獎賞以後的購買總量，在這裏改動可以顧及函數尾部的廣播指令
            // The changes here consider the broadcast instructions at the end of the function.
            amount = amount * 11 / 10;

            // 更新流通供應量  
            // Update circulating supply  
            circulatingSupply += amount + friendBonus;

            // 更新可領取數量  
            // Update claimable supply  
            claimable -= friendBonus * 2;

            // 轉移推薦人獎勵  
            // Transfer referral bonus to the referrer  
            _transfer(address(this), friend, friendBonus);

            // 轉移購買者的 TEST 代幣，包含 10% 額外獎勵  
            // Transfer TEST tokens to the buyer, including a 10% bonus  
            _transfer(address(this), _msgSender(), amount);

            // 觸發領取事件，記錄推薦人獎勵  
            // Emit event to log the referral bonus  
            emit TESTClaimed(friend, friendBonus);

        } else {

            // 如果沒有推薦人，則只發送基礎購買金額  
            // If no referrer, transfer only the base purchase amount  
            _transfer(address(this), _msgSender(), amount);

            // 更新流通供應量  
            // Update circulating supply  
            circulatingSupply += amount;
        }

        // 觸發購買事件，記錄購買者和購買金額  
        // Emit event to log the buyer and the purchase amount  
        emit TESTBought(_msgSender(), msg.value, amount);
    }



    /**
     * @dev Fallback function to handle direct ETH transfers and issue TEST in return.
     * Receive函數，同樣處理接收ETH並傳送TEST，each Ethereum -> 0.1% with slippage of the contract supply
     * Receive function, similarly handling receiving ETH and sending TEST
     */
    fallback() external payable nonReentrant {
        uint256 amount = msg.value * calculatePurchaseAmount();
        _transfer(address(this), _msgSender(), amount);
        circulatingSupply += amount;
        emit TESTBought(_msgSender(), msg.value, amount);
    }



    /**
     * @dev Fallback function to handle direct ETH transfers and issue TEST in return.
     * Receive函數，同樣處理接收ETH並傳送TEST，each Ethereum -> 0.1% with slippage of the contract supply
     * Receive function, similarly handling receiving ETH and sending TEST
     */
    receive() external payable nonReentrant {
        uint256 amount = msg.value * calculatePurchaseAmount();
        _transfer(address(this), _msgSender(), amount);
        circulatingSupply += amount;
        emit TESTBought(_msgSender(), msg.value, amount);
    }
}



// Copyright © 2025 TEST x RWAY CLUB. All rights reserved.
