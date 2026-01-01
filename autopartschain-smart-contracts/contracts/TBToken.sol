// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title TBToken - AutoPartsChain Native Token
 * @dev ERC-20 token with:
 * - Snapshot capability for airdrops/rewards
 * - Burnable functionality
 * - Permit for gasless approvals (EIP-2612)
 * - Role-based access control
 * - Pausable transfers for emergencies
 */
contract TBToken is 
    ERC20, 
    ERC20Burnable, 
    ERC20Snapshot, 
    AccessControl, 
    Pausable,
    ERC20Permit 
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18; // 1B tokens
    uint256 public constant INITIAL_SUPPLY = 500_000_000 * 10**18; // 500M initial
    
    // Anti-whale protection
    uint256 public maxTransferAmount;
    mapping(address => bool) public isExcludedFromLimits;
    
    // Trading restrictions
    bool public tradingEnabled = false;
    uint256 public tradingEnabledTime;
    
    // Fee structure (basis points: 100 = 1%)
    uint256 public buyFee = 300; // 3%
    uint256 public sellFee = 300; // 3%
    uint256 public transferFee = 100; // 1%
    
    address public treasuryWallet;
    address public liquidityWallet;
    address public marketingWallet;
    
    // Mapping for automated market maker pairs
    mapping(address => bool) public automatedMarketMakerPairs;
    
    // Events
    event MaxTransferAmountUpdated(uint256 newAmount);
    event TradingEnabled(uint256 timestamp);
    event FeesUpdated(uint256 buyFee, uint256 sellFee, uint256 transferFee);
    event WalletsUpdated(address treasury, address liquidity, address marketing);
    event AutomatedMarketMakerPairSet(address indexed pair, bool indexed value);
    event TokensRecovered(address token, uint256 amount);
    
    constructor(
        address _treasuryWallet,
        address _liquidityWallet,
        address _marketingWallet
    ) 
        ERC20("AutoPartsChain Token", "TBC") 
        ERC20Permit("AutoPartsChain Token")
    {
        require(_treasuryWallet != address(0), "Treasury wallet cannot be zero");
        require(_liquidityWallet != address(0), "Liquidity wallet cannot be zero");
        require(_marketingWallet != address(0), "Marketing wallet cannot be zero");
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(SNAPSHOT_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        
        treasuryWallet = _treasuryWallet;
        liquidityWallet = _liquidityWallet;
        marketingWallet = _marketingWallet;
        
        maxTransferAmount = MAX_SUPPLY / 100; // 1% max transfer
        isExcludedFromLimits[msg.sender] = true;
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromLimits[_treasuryWallet] = true;
        isExcludedFromLimits[_liquidityWallet] = true;
        isExcludedFromLimits[_marketingWallet] = true;
        
        // Mint initial supply to treasury
        _mint(_treasuryWallet, INITIAL_SUPPLY);
    }
    
    /**
     * @dev Creates a new snapshot and returns its id
     */
    function snapshot() public onlyRole(SNAPSHOT_ROLE) returns (uint256) {
        return _snapshot();
    }
    
    /**
     * @dev Pause all token transfers
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause token transfers
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Mint new tokens (for staking rewards, partnerships, etc.)
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }
    
    /**
     * @dev Enable trading - can only be done once
     */
    function enableTrading() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!tradingEnabled, "Trading already enabled");
        tradingEnabled = true;
        tradingEnabledTime = block.timestamp;
        emit TradingEnabled(block.timestamp);
    }
    
    /**
     * @dev Set automated market maker pair status
     */
    function setAutomatedMarketMakerPair(address pair, bool value) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(pair != address(0), "Pair cannot be zero address");
        automatedMarketMakerPairs[pair] = value;
        emit AutomatedMarketMakerPairSet(pair, value);
    }
    
    /**
     * @dev Update fee structure
     */
    function updateFees(uint256 _buyFee, uint256 _sellFee, uint256 _transferFee) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_buyFee <= 1000, "Buy fee cannot exceed 10%");
        require(_sellFee <= 1000, "Sell fee cannot exceed 10%");
        require(_transferFee <= 500, "Transfer fee cannot exceed 5%");
        
        buyFee = _buyFee;
        sellFee = _sellFee;
        transferFee = _transferFee;
        
        emit FeesUpdated(_buyFee, _sellFee, _transferFee);
    }
    
    /**
     * @dev Update wallet addresses
     */
    function updateWallets(
        address _treasuryWallet,
        address _liquidityWallet,
        address _marketingWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasuryWallet != address(0), "Treasury wallet cannot be zero");
        require(_liquidityWallet != address(0), "Liquidity wallet cannot be zero");
        require(_marketingWallet != address(0), "Marketing wallet cannot be zero");
        
        treasuryWallet = _treasuryWallet;
        liquidityWallet = _liquidityWallet;
        marketingWallet = _marketingWallet;
        
        emit WalletsUpdated(_treasuryWallet, _liquidityWallet, _marketingWallet);
    }
    
    /**
     * @dev Update max transfer amount
     */
    function updateMaxTransferAmount(uint256 newAmount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newAmount >= totalSupply() / 1000, "Cannot be less than 0.1%");
        maxTransferAmount = newAmount;
        emit MaxTransferAmountUpdated(newAmount);
    }
    
    /**
     * @dev Exclude/include address from transfer limits
     */
    function setExcludedFromLimits(address account, bool excluded) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        isExcludedFromLimits[account] = excluded;
    }
    
    /**
     * @dev Calculate fee for a transfer
     */
    function calculateFee(
        address sender, 
        address recipient, 
        uint256 amount
    ) public view returns (uint256) {
        if (isExcludedFromLimits[sender] || isExcludedFromLimits[recipient]) {
            return 0;
        }
        
        if (automatedMarketMakerPairs[sender]) {
            // Buying from DEX
            return (amount * buyFee) / 10000;
        } else if (automatedMarketMakerPairs[recipient]) {
            // Selling to DEX
            return (amount * sellFee) / 10000;
        } else {
            // Regular transfer
            return (amount * transferFee) / 10000;
        }
    }
    
    /**
     * @dev Distribute fees to wallets
     */
    function _distributeFees(uint256 feeAmount) internal {
        uint256 treasuryShare = (feeAmount * 40) / 100; // 40% to treasury
        uint256 liquidityShare = (feeAmount * 40) / 100; // 40% to liquidity
        uint256 marketingShare = feeAmount - treasuryShare - liquidityShare; // 20% to marketing
        
        if (treasuryShare > 0) _transfer(address(this), treasuryWallet, treasuryShare);
        if (liquidityShare > 0) _transfer(address(this), liquidityWallet, liquidityShare);
        if (marketingShare > 0) _transfer(address(this), marketingWallet, marketingShare);
    }
    
    /**
     * @dev Hook that is called before any transfer
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Snapshot) whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
        
        // Only check limits if trading is enabled
        if (tradingEnabled) {
            if (!isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
                require(
                    amount <= maxTransferAmount,
                    "Transfer amount exceeds max transfer amount"
                );
            }
        } else if (from != address(0) && to != address(0)) {
            // Allow transfers before trading enabled only for excluded addresses
            require(
                isExcludedFromLimits[from] || isExcludedFromLimits[to],
                "Trading is not enabled yet"
            );
        }
    }
    
    /**
     * @dev Hook that is called after any transfer
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._afterTokenTransfer(from, to, amount);
        
        // Apply fees (except for mint/burn)
        if (from != address(0) && to != address(0) && !isExcludedFromLimits[from]) {
            uint256 feeAmount = calculateFee(from, to, amount);
            if (feeAmount > 0) {
                // Transfer fee to contract first
                super._transfer(to, address(this), feeAmount);
                // Distribute fees
                _distributeFees(feeAmount);
            }
        }
    }
    
    /**
     * @dev Recover tokens accidentally sent to this contract
     */
    function recoverTokens(address tokenAddress, uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(tokenAddress != address(this), "Cannot recover native token");
        IERC20(tokenAddress).transfer(msg.sender, amount);
        emit TokensRecovered(tokenAddress, amount);
    }
    
    /**
     * @dev Get current circulating supply
     */
    function circulatingSupply() public view returns (uint256) {
        return totalSupply() - balanceOf(treasuryWallet);
    }
}
