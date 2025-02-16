// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Custom errors for gas savings and clarity
error NoEthInPool();
error InsufficientVoltBalance();
error InsufficientETHInReserve();
error FailedToSendETH();
error NoMoreTokensForClaim();
error ClaimAmountTooSmall();
error NoMoreTokensAvailable();
error TransactionExceedsLimit();
error InsufficientStakedBalance();
error NoStakedTokens();
error NotEnoughETHForUnstake();

/**
 * @title Volt Token
 * @dev An ERC20 token with a built-in liquidity pool mechanism, claimable airdrops, and Pay-to-Earn functionality.
 *      This contract allows users to buy and sell Volt tokens with ETH, claim airdrops, and earn rewards through payments.
 *      Built on OpenZeppelin's ERC20 and ReentrancyGuard for security and reliability.
 * @custom:security-contact wyc.emote732@passinbox.com
 */
contract Volt is ERC20, ERC20Permit, ReentrancyGuard, Ownable {

    /**
     * @dev Emitted when a Volt token purchase is executed.
     * @param buyer The address of the buyer.
     * @param ethAmount The amount of ETH spent.
     * @param tokenAmount The amount of Volt tokens purchased.
     */
    event VoltBought(address indexed buyer, uint256 ethAmount, uint256 tokenAmount);

    /**
     * @dev Emitted when a Volt token sale is executed.
     * @param seller The address of the seller.
     * @param tokenAmount The amount of Volt tokens sold.
     * @param ethAmount The amount of ETH received.
     */
    event VoltSold(address indexed seller, uint256 tokenAmount, uint256 ethAmount);

    /**
     * @dev Emitted when a Volt token airdrop or referral bonus is claimed.
     * @param claimer The address that claimed the tokens.
     * @param tokenAmount The amount of tokens claimed.
     */
    event VoltClaimed(address indexed claimer, uint256 tokenAmount);

    /**
     * @dev Emitted whenever the circulating supply or claimable supply is updated.
     * @param circulatingSupply The updated circulating supply.
     */
    event SupplyUpdated(uint256 indexed circulatingSupply);

    /**
     * @dev Emitted when a user stakes Volt tokens.
     */
    event VoltStaked(address indexed staker, uint256 amount);

    /**
     * @dev Emitted when a user unstakes and withdraws ETH.
     */
    event VoltUnstaked(address indexed unstaker, uint256 tokenAmount, uint256 ethAmount);

    /**
     * @dev Public state variable tracking the circulating supply of Volt tokens.
     *      Represents tokens outside the main contract liquidity pool.
     */
    uint256 public circulatingSupply = 100000 * 10 ** decimals();

    /**
     * @dev Public state variable tracking the claimable amount of Volt tokens.
     */
    uint256 public claimable = 10000 * 10 ** decimals();

    /**
     * @dev Public constant state variable representing the SILPPAGE percentage.
     */
    uint256 public constant SILPPAGE = 1;

    /**
     * @dev Total amount of Volt tokens staked in the contract.
     */
    uint256 public totalStaked;

    /**
     * @dev Mapping to track each user's staked Volt balance.
     */
    mapping(address staker => uint256 balance) public stakedBalance;

    /**
     * @dev Constructor for the Volt token contract.
     *
     * This constructor initializes the token by doing the following:
     * - Passes the token name ("Volt") and symbol ("Volt") to the ERC20 base contract.
     * - Initializes ERC20Permit with the token name "Volt" to enable gasless approvals.
     * - Sets the initial owner of the contract by passing the provided `initialOwner` address to the Ownable base contract.
     * @param initialOwner The address that will become the owner of the contract.
     */
    constructor(address initialOwner)
        ERC20("Volt", "Volt")
        ERC20Permit("Volt")
        Ownable(initialOwner)
    {
        // Mint tokens for the Permit team and partners.
        _mint(_msgSender(), 100000 * 10 ** decimals());
        // Mint tokens reserved for the internal swapping pool.
        _mint(address(this), 900000 * 10 ** decimals());
    }

    /**
     * @notice Calculates the amount of Volt tokens a user will receive when purchasing with 1 ETH.
     * @return The number of Volt tokens the user will receive after applying SILPPAGE.
     */
    function calculatePurchaseAmount() public view returns (uint256) {
        // Perform all multiplications before any division to reduce precision loss.
        uint256 tokenBalance = balanceOf(address(this));
        uint256 numerator = tokenBalance * (100 - SILPPAGE);
        uint256 denominator = (10 ** decimals()) * 100000;
        return numerator / denominator;
    }

    /**
     * @notice Calculates the amount of ETH that will be received when selling 1 Volt token.
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
     * @notice Sells a specified amount of Volt tokens in exchange for ETH.
     * @dev Transfers Volt tokens from the seller to the contract and sends ETH in return.
     *      Emits a {VoltSold} event and a {SupplyUpdated} event.
     * @param tokenAmount The amount of Volt tokens to sell (in token units, not considering decimals).
     */
    function sellVolt(uint256 tokenAmount) external nonReentrant {
        uint256 tokenAmountWithDecimals = tokenAmount * (10 ** decimals());
        // Ensure the seller has sufficient Volt balance.
        if (balanceOf(_msgSender()) < tokenAmountWithDecimals) revert InsufficientVoltBalance();
        uint256 ethAmount = tokenAmount * calculateSellAmount();
        // Ensure there is sufficient ETH in the reserve.
        if (ethAmount > address(this).balance) revert InsufficientETHInReserve();
        // Update circulating supply before token transfer.
        circulatingSupply -= tokenAmountWithDecimals;
        emit SupplyUpdated(circulatingSupply);
        // Transfer Volt tokens from seller to contract.
        _transfer(_msgSender(), address(this), tokenAmountWithDecimals);
        // Transfer ETH to seller using call method.
        (bool sent, ) = payable(_msgSender()).call{value: ethAmount}("");
        if (!sent) revert FailedToSendETH();
        // Emit sale event.
        emit VoltSold(_msgSender(), tokenAmountWithDecimals, ethAmount);
    }

    /**
     * @notice Claims a Volt token airdrop, optionally with a referral bonus.
     * @dev Transfers tokens from the contract to the claimer and optionally rewards the referrer.
     *      Emits {VoltClaimed} events and a {SupplyUpdated} event.
     * @param friend The address of the referrer, if any.
     */
    function claimVolt(address friend) external nonReentrant {
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
            emit VoltClaimed(friend, friendBonus);
            // Transfer claimed tokens (base amount + 10% bonus) to the claimer.
            uint256 totalClaim = (amount * 11) / 10;
            _transfer(address(this), _msgSender(), totalClaim);
            // Update claimable and circulating supply.
            claimable -= (totalClaim + friendBonus);
            circulatingSupply += (totalClaim + friendBonus);
            emit SupplyUpdated(circulatingSupply);
        } else {
            // Transfer only the base claim amount.
            _transfer(address(this), _msgSender(), amount);
            claimable -= amount;
            circulatingSupply += amount;
            emit SupplyUpdated(circulatingSupply);
        }
        // Emit claim event for the claimer.
        emit VoltClaimed(_msgSender(), amount);
    }

    /**
     * @notice Buys Volt tokens using ETH, optionally including a referral bonus.
     * @dev Calculates token amount considering SILPPAGE, transfers tokens, and updates state.
     *      Emits a {VoltBought} event and a {SupplyUpdated} event.
     * @param friend The referrer address, if applicable.
     */
    function buyVolt(address friend) external payable nonReentrant {
        // Ensure tokens are available for purchase in the contract pool.
        if (balanceOf(address(this)) == 0) revert NoMoreTokensAvailable();
        // Limit each transaction to a maximum of 99 ETH.
        if (msg.value > 99 * (10 ** decimals())) revert TransactionExceedsLimit();
        // Calculate the amount of Volt tokens to be bought considering SILPPAGE.
        uint256 amount = msg.value * calculatePurchaseAmount();
        uint256 friendBonus = (amount * 10) / 100;
        if (friend != address(0) && friend != _msgSender()) {
            // Include referral bonus by increasing purchase amount by 10%.
            amount = (amount * 11) / 10;
            circulatingSupply += (amount + friendBonus);
            claimable -= friendBonus * 2;
            // Transfer referral bonus to the friend.
            _transfer(address(this), friend, friendBonus);
            emit VoltClaimed(friend, friendBonus);
        } else {
            circulatingSupply += amount;
        }
        emit SupplyUpdated(circulatingSupply);
        // Transfer purchased tokens to the buyer.
        _transfer(address(this), _msgSender(), amount);
        // Emit purchase event.
        emit VoltBought(_msgSender(), msg.value, amount);
    }

    /**
     * @notice Allows users to stake Volt tokens into the contract.
     * @param amount The number of Volt tokens to stake (without decimals).
     */
    function stakeVolt(uint256 amount) external nonReentrant {
        uint256 tokenAmount = amount * (10 ** decimals());
        if (balanceOf(_msgSender()) < tokenAmount) revert InsufficientVoltBalance();
        // Transfer Volt from user to contract
        _transfer(_msgSender(), address(this), tokenAmount);
        // Update staking data
        stakedBalance[_msgSender()] += tokenAmount;
        totalStaked += tokenAmount;
        emit VoltStaked(_msgSender(), tokenAmount);
    }

    /**
     * @notice Allows users to unstake their Volt tokens and receive ETH in exchange.
     * @param amount The number of Volt tokens to unstake (without decimals).
     */
    function unstakeVolt(uint256 amount) external nonReentrant {
        uint256 tokenAmount = amount * (10 ** decimals());
        if (stakedBalance[_msgSender()] < tokenAmount) revert InsufficientStakedBalance();
        if (totalStaked == 0) revert NoStakedTokens();
        // Calculate ETH amount based on staking percentage
        uint256 ethAmount = (address(this).balance * tokenAmount) / totalStaked;
        if (ethAmount > address(this).balance) revert NotEnoughETHForUnstake();
        // Update staking balances
        stakedBalance[_msgSender()] -= tokenAmount;
        totalStaked -= tokenAmount;
        circulatingSupply -= amount;
        // Burn the unstaked Volt tokens
        _burn(address(this), tokenAmount);
        // Send ETH to user
        (bool sent, ) = payable(_msgSender()).call{value: ethAmount}("");
        if (!sent) revert FailedToSendETH();
        emit SupplyUpdated(circulatingSupply);
        emit VoltUnstaked(_msgSender(), tokenAmount, ethAmount);
    }

    /**
     * @notice Fallback function to handle direct ETH transfers and issue Volt tokens in return.
     * @dev Transfers tokens based on the ETH sent and updates circulating supply.
     *      Emits a {VoltBought} event and a {SupplyUpdated} event.
     */
    fallback() external payable nonReentrant {
        uint256 amount = msg.value * calculatePurchaseAmount();
        _transfer(address(this), _msgSender(), amount);
        circulatingSupply += amount;
        emit SupplyUpdated(circulatingSupply);
        emit VoltBought(_msgSender(), msg.value, amount);
    }

    /**
     * @notice Receive function to handle direct ETH transfers and issue Volt tokens in return.
     * @dev Similar to fallback; triggered when ETH is sent without data.
     *      Emits a {VoltBought} event and a {SupplyUpdated} event.
     */
    receive() external payable nonReentrant {
        uint256 amount = msg.value * calculatePurchaseAmount();
        _transfer(address(this), _msgSender(), amount);
        circulatingSupply += amount;
        emit SupplyUpdated(circulatingSupply);
        emit VoltBought(_msgSender(), msg.value, amount);
    }
}
