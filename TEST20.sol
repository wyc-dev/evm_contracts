// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Custom errors for gas savings and clarity
error NoEthInPool();
error InsufficientTESTBalance();
error InsufficientETHInReserve();
error FailedToSendETH();
error NoMoreTokensForClaim();
error ClaimAmountTooSmall();
error NoMoreTokensAvailable();
error TransactionExceedsLimit();

/**
 * @title TEST Token
 * @dev An ERC20 token with a built-in liquidity pool mechanism, claimable airdrops, and Pay-to-Earn functionality.
 *      This contract allows users to buy and sell TEST tokens with ETH, claim airdrops, and earn rewards through payments.
 *      Built on OpenZeppelin's ERC20 and ReentrancyGuard for security and reliability.
 * @custom:security-contact wyc.emote732@passinbox.com
 */
contract TEST is ERC20, ReentrancyGuard {

    /**
     * @dev Emitted when a TEST token purchase is executed.
     * @param buyer The address of the buyer.
     * @param ethAmount The amount of ETH spent.
     * @param tokenAmount The amount of TEST tokens purchased.
     */
    event TESTBought(address indexed buyer, uint256 ethAmount, uint256 tokenAmount);

    /**
     * @dev Emitted when a TEST token sale is executed.
     * @param seller The address of the seller.
     * @param tokenAmount The amount of TEST tokens sold.
     * @param ethAmount The amount of ETH received.
     */
    event TESTSold(address indexed seller, uint256 tokenAmount, uint256 ethAmount);

    /**
     * @dev Emitted when a TEST token airdrop or referral bonus is claimed.
     * @param claimer The address that claimed the tokens.
     * @param tokenAmount The amount of tokens claimed.
     */
    event TESTClaimed(address indexed claimer, uint256 tokenAmount);

    /**
     * @dev Emitted whenever the circulating supply or claimable supply is updated.
     * @param circulatingSupply The updated circulating supply.
     * @param claimable The updated claimable token amount.
     */
    event SupplyUpdated(uint256 indexed circulatingSupply, uint256 indexed claimable);

    /**
     * @dev Public state variable tracking the circulating supply of TEST tokens.
     *      Represents tokens outside the main contract liquidity pool.
     */
    uint256 public circulatingSupply = 850000 * 10 ** decimals();

    /**
     * @dev Public state variable tracking the claimable amount of TEST tokens.
     */
    uint256 public claimable = 10000 * 10 ** decimals();

    /**
     * @dev Public constant state variable representing the SILPPAGE percentage.
     */
    uint256 public constant SILPPAGE = 1;

    /**
     * @dev Constructor to mint the initial token supply.
     *      - 85% of the total supply is allocated to the TEST team and partners.
     *      - 15% is reserved in the contract for liquidity and transactions.
     */
    constructor() ERC20("TEST", "TEST") {
        // TESTDAO - Team & Partners Foundation Reserve
        _mint(_msgSender(), 850000 * 10 ** decimals());
        // TESTDAO - Internal Swapping Pool Reserve
        _mint(address(this), 150000 * 10 ** decimals());
    }

    /**
     * @notice Calculates the amount of TEST tokens a user will receive when purchasing with 1 ETH.
     * @return The number of TEST tokens the user will receive after applying SILPPAGE.
     */
    function calculatePurchaseAmount() public view returns (uint256) {
        // Perform all multiplications before any division to reduce precision loss.
        uint256 tokenBalance = balanceOf(address(this));
        uint256 numerator = tokenBalance * (100 - SILPPAGE);
        uint256 denominator = (10 ** decimals()) * 100000;
        return numerator / denominator;
    }

    /**
     * @notice Calculates the amount of ETH that will be received when selling 1 TEST token.
     * @return The amount of ETH the seller will receive.
     */
    function calculateSellAmount() public view returns (uint256) {
        // Ensure there is ETH in the pool.
        if (address(this).balance == 0) revert NoEthInPool();
        // Multiply first to reduce loss of precision.
        uint256 numerator = (10 ** decimals()) * address(this).balance;
        return numerator / circulatingSupply;
    }

    /**
     * @notice Sells a specified amount of TEST tokens in exchange for ETH.
     * @dev Transfers TEST tokens from the seller to the contract and sends ETH in return.
     *      Emits a {TESTSold} event and a {SupplyUpdated} event.
     * @param tokenAmount The amount of TEST tokens to sell (in token units, not considering decimals).
     */
    function sellTEST(uint256 tokenAmount) external nonReentrant {
        uint256 tokenAmountWithDecimals = tokenAmount * (10 ** decimals());
        // Ensure the seller has sufficient TEST balance.
        if (balanceOf(_msgSender()) < tokenAmountWithDecimals) revert InsufficientTESTBalance();
        uint256 ethAmount = tokenAmount * calculateSellAmount();
        // Ensure there is sufficient ETH in the reserve.
        if (ethAmount > address(this).balance) revert InsufficientETHInReserve();
        // Update circulating supply before token transfer.
        circulatingSupply -= tokenAmountWithDecimals;
        emit SupplyUpdated(circulatingSupply, claimable);
        // Transfer TEST tokens from seller to contract.
        _transfer(_msgSender(), address(this), tokenAmountWithDecimals);
        // Transfer ETH to seller using call method.
        (bool sent, ) = payable(_msgSender()).call{value: ethAmount}("");
        if (!sent) revert FailedToSendETH();
        // Emit sale event.
        emit TESTSold(_msgSender(), tokenAmountWithDecimals, ethAmount);
    }

    /**
     * @notice Claims a TEST token airdrop, optionally with a referral bonus.
     * @dev Transfers tokens from the contract to the claimer and optionally rewards the referrer.
     *      Emits {TESTClaimed} events and a {SupplyUpdated} event.
     * @param friend The address of the referrer, if any.
     */
    function claimTEST(address friend) external nonReentrant {
        // Ensure tokens are available for claim.
        if (claimable == 0) revert NoMoreTokensForClaim();
        // Each claim grants 0.01% of the claimable pool.
        uint256 amount = claimable / 10000;
        // Ensure the claim amount is valid.
        if (amount == 0) revert ClaimAmountTooSmall();
        if (friend != address(0) && friend != _msgSender()) {
            // Calculate referral bonus (10%).
            uint256 friendBonus = (amount * 10) / 100;
            // Transfer referral bonus to the friend.
            _transfer(address(this), friend, friendBonus);
            emit TESTClaimed(friend, friendBonus);
            // Transfer claimed tokens (base amount + 10% bonus) to the claimer.
            uint256 totalClaim = (amount * 11) / 10;
            _transfer(address(this), _msgSender(), totalClaim);
            // Update claimable and circulating supply.
            claimable -= (totalClaim + friendBonus);
            circulatingSupply += (totalClaim + friendBonus);
            emit SupplyUpdated(circulatingSupply, claimable);
        } else {
            // Transfer only the base claim amount.
            _transfer(address(this), _msgSender(), amount);
            claimable -= amount;
            circulatingSupply += amount;
            emit SupplyUpdated(circulatingSupply, claimable);
        }
        // Emit claim event for the claimer.
        emit TESTClaimed(_msgSender(), amount);
    }

    /**
     * @notice Buys TEST tokens using ETH, optionally including a referral bonus.
     * @dev Calculates token amount considering SILPPAGE, transfers tokens, and updates state.
     *      Emits a {TESTBought} event and a {SupplyUpdated} event.
     * @param friend The referrer address, if applicable.
     */
    function buyTEST(address friend) external payable nonReentrant {
        // Ensure tokens are available for purchase in the contract pool.
        if (balanceOf(address(this)) == 0) revert NoMoreTokensAvailable();
        // Limit each transaction to a maximum of 99 ETH.
        if (msg.value > 99 * (10 ** decimals())) revert TransactionExceedsLimit();
        // Calculate the amount of TEST tokens to be bought considering SILPPAGE.
        uint256 amount = msg.value * calculatePurchaseAmount();
        uint256 friendBonus = (amount * 10) / 100;
        if (friend != address(0) && friend != _msgSender()) {
            // Include referral bonus by increasing purchase amount by 10%.
            amount = (amount * 11) / 10;
            circulatingSupply += (amount + friendBonus);
            claimable -= friendBonus * 2;
            // Transfer referral bonus to the friend.
            _transfer(address(this), friend, friendBonus);
            emit TESTClaimed(friend, friendBonus);
        } else {
            circulatingSupply += amount;
        }
        emit SupplyUpdated(circulatingSupply, claimable);
        // Transfer purchased tokens to the buyer.
        _transfer(address(this), _msgSender(), amount);
        // Emit purchase event.
        emit TESTBought(_msgSender(), msg.value, amount);
    }

    /**
     * @notice Fallback function to handle direct ETH transfers and issue TEST tokens in return.
     * @dev Transfers tokens based on the ETH sent and updates circulating supply.
     *      Emits a {TESTBought} event and a {SupplyUpdated} event.
     */
    fallback() external payable nonReentrant {
        uint256 amount = msg.value * calculatePurchaseAmount();
        _transfer(address(this), _msgSender(), amount);
        circulatingSupply += amount;
        emit SupplyUpdated(circulatingSupply, claimable);
        emit TESTBought(_msgSender(), msg.value, amount);
    }

    /**
     * @notice Receive function to handle direct ETH transfers and issue TEST tokens in return.
     * @dev Similar to fallback; triggered when ETH is sent without data.
     *      Emits a {TESTBought} event and a {SupplyUpdated} event.
     */
    receive() external payable nonReentrant {
        uint256 amount = msg.value * calculatePurchaseAmount();
        _transfer(address(this), _msgSender(), amount);
        circulatingSupply += amount;
        emit SupplyUpdated(circulatingSupply, claimable);
        emit TESTBought(_msgSender(), msg.value, amount);
    }
}

// Copyright © 2025 TEST x RWAY CLUB. All rights reserved.
