// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Superposition Coin (C01N)
 * @notice This contract allows users to mint C01N tokens by Proof of Reserve (PoR) stakes of USDC and TOKEN.
 *         Users will not approve or transfer their tokens; instead, they declare the amounts when stake and unstake,
 *         and based on that, they can earn C01N rewards over time.
 * @dev The contract inherits from ERC20 for standard token functionality and ReentrancyGuard to prevent reentrancy attacks.
 *      It tracks staking via a declaration-based system rather than actual token transfers, which may introduce risks if not validated externally.
 * @custom:security-contact hopeallgood.unadvised619@passinbox.com
 */
contract C01N is ERC20, ReentrancyGuard {

    /// @notice Thrown when a user tries to stake / unstake but has insufficient C01N balance
    /// @dev Replaces require statements to save gas and improve readability
    error InsufficientC01NBalance();

    /// @notice Thrown when a user tries to stake / unstake but has insufficient USDC balance
    /// @dev Replaces require statements to save gas and improve readability
    error InsufficientUSDCBalance();

    /// @notice Thrown when a user tries to stake / unstake but has insufficient TOKEN balance
    /// @dev Replaces require statements to save gas and improve readability
    error InsufficientTOKENBalance();

    /// @notice Address of the TOKEN contract used for staking
    /// @dev Hardcoded address; ensure it is correct and immutable across deployments
    address public constant TOKEN = address(0xa1B68A58B1943Ba90703645027a10F069770ED39);

    /// @notice Address of the USDC contract used for staking
    /// @dev Hardcoded address; verify compatibility with the USDC ERC20 interface
    address public constant USDC = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    /// @notice Total number of unique stakers in the contract
    /// @dev Incremented when a new user stakes, decremented when they unstake
    uint256 public totalStaker;

    /// @notice Total amount of TOKEN staked across all users
    /// @dev Tracks declared TOKEN staking amounts, not actual transfers
    uint256 public totalStakingTOKEN;

    /// @notice Total amount of USDC staked across all users
    /// @dev Tracks declared USDC staking amounts, not actual transfers
    uint256 public totalStakingUSDC;

    /// @notice Total amount of C01N staked across all users
    /// @dev Tracks declared C01N staking amounts for reward calculation
    uint256 public totalStakingC01N;

    /**
     * @notice Struct to store staking details for each user
     * @dev Used in the stakingInfo mapping to track individual staking state
     */
    struct Superposition {
        /// @notice Indicates whether the user is currently staking
        bool isStaking;
        /// @notice Timestamp when staking began
        uint256 stakeTime;
        /// @notice Amount of TOKEN declared as staked
        uint256 TOKEN_staking;
        /// @notice Amount of USDC declared as staked
        uint256 USDC_staking;
        /// @notice Amount of C01N declared as staked
        uint256 C01N_staking;
        /// @notice Total C01N minted as rewards for this user
        uint256 C01N_minted;
    }

    /// @notice Mapping of user addresses to their staking information
    /// @dev Stores staking details for each user, accessible publicly
    mapping(address User => Superposition State) public stakingInfo;

    /**
     * @notice Emitted when a user stakes tokens
     * @param user The address of the user who staked
     * @param C01N_amount Amount of C01N declared as staked
     * @param USDC_amount Amount of USDC declared as staked
     * @param TOKEN_amount Amount of TOKEN declared as staked
     */
    event Staked(address indexed user, uint256 C01N_amount, uint256 USDC_amount, uint256 TOKEN_amount);

    /**
     * @notice Emitted when a user unstakes tokens and receives rewards
     * @param user The address of the user who unstaked
     * @param C01N_amount Amount of C01N unstaked
     * @param USDC_amount Amount of USDC unstaked
     * @param TOKEN_amount Amount of TOKEN unstaked
     * @param reward Amount of C01N minted as a reward
     */
    event Unstaked(address indexed user, uint256 C01N_amount, uint256 USDC_amount, uint256 TOKEN_amount, uint256 reward);

    /**
     * @notice Constructor to initialize the C01N token contract
     * @dev Sets up the ERC20 token with name "Superposition Coin" and symbol "C01N".
     *      The owner parameter is currently unused and could be removed for clarity.
     */
    constructor() ERC20("Superposition Coin", "C01N"){}

    /**
     * @notice Allows a user to stake or unstake tokens and mint rewards
     * @dev If the user is not staking, this function stakes the declared amounts.
     *      If the user is already staking, it unstakes and calculates/mints rewards.
     *      Uses nonReentrant modifier to prevent reentrancy attacks.
     *      Note: Tokens are not transferred to the contract; amounts are only declared.
     * @param C01N_amount Amount of C01N to stake or unstake
     * @param USDC_amount Amount of USDC to stake or unstake
     * @param TOKEN_amount Amount of TOKEN to stake or unstake
     */
    function PoR_staking(uint256 C01N_amount, uint256 USDC_amount, uint256 TOKEN_amount) external nonReentrant {
        
        uint256 C01N_balance  = balanceOf(_msgSender());
        uint256 USDC_balance  = IERC20(USDC).balanceOf(_msgSender());
        uint256 TOKEN_balance = IERC20(TOKEN).balanceOf(_msgSender());
        Superposition storage state = stakingInfo[_msgSender()];

        if (state.isStaking) {

            // Unstaking logic
            if (C01N_balance  < state.C01N_staking ) revert InsufficientC01NBalance();
            if (USDC_balance  < state.USDC_staking ) revert InsufficientUSDCBalance();
            if (TOKEN_balance < state.TOKEN_staking) revert InsufficientTOKENBalance();

            uint256 stakingDuration = block.timestamp - state.stakeTime;
            uint256 reward = calculateReward(state.C01N_staking, state.USDC_staking, state.TOKEN_staking, stakingDuration);
            emit Unstaked(_msgSender(), state.C01N_staking, state.USDC_staking, state.TOKEN_staking, reward);
            state.isStaking     = false;
            state.C01N_minted  += reward;
            state.C01N_staking  = 0;
            state.USDC_staking  = 0;
            state.TOKEN_staking = 0;
            totalStaker        -= 1;
            totalStakingTOKEN  -= TOKEN_amount;
            totalStakingUSDC   -= USDC_amount;
            totalStakingC01N   -= C01N_amount;
            _mint(_msgSender(), reward);

        } else {

            // Staking logic
            if (C01N_balance  < C01N_amount ) revert InsufficientC01NBalance();
            if (USDC_balance  < USDC_amount ) revert InsufficientUSDCBalance();
            if (TOKEN_balance < TOKEN_amount) revert InsufficientTOKENBalance();
            
            state.isStaking     = true;
            state.stakeTime     = block.timestamp;
            state.C01N_staking  = C01N_amount;
            state.USDC_staking  = USDC_amount;
            state.TOKEN_staking = TOKEN_amount;
            totalStaker        += 1;
            totalStakingTOKEN  += TOKEN_amount;
            totalStakingUSDC   += USDC_amount;
            totalStakingC01N   += C01N_amount;
            emit Staked(_msgSender(), C01N_amount, USDC_amount, TOKEN_amount);

        }
    }

    /**
     * @notice Calculates the reward for staking based on duration and staked amounts
     * @dev Uses a simple linear reward formula with different rates for C01N (4%), USDC (8%), and TOKEN (12%) per year.
     *      Rewards are proportional to staking duration and normalized by seconds in a year (365 days).
     * @param C01N_staking Amount of C01N staked
     * @param USDC_staking Amount of USDC staked
     * @param TOKEN_staking Amount of TOKEN staked
     * @param stakingDuration Duration of staking in seconds
     * @return uint256 The total reward in C01N tokens
     */
    function calculateReward(uint256 C01N_staking, uint256 USDC_staking, uint256 TOKEN_staking, uint256 stakingDuration) 
        public 
        pure 
        returns (uint256) 
    {
        uint256 secondsInYear   = 31536000; // 365 days
        uint256 rewardFromC01N  = (C01N_staking  * stakingDuration * 4)  / (100 * secondsInYear);
        uint256 rewardFromUSDC  = (USDC_staking  * stakingDuration * 8)  / (100 * secondsInYear);
        uint256 rewardFromTOKEN = (TOKEN_staking * stakingDuration * 12) / (100 * secondsInYear);
        return  rewardFromC01N  + rewardFromUSDC + rewardFromTOKEN;
    }
}
