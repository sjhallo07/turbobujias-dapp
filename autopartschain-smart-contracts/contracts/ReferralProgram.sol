// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ReferralProgram
 * @dev Programa de referidos con múltiples niveles y comisiones
 */
contract ReferralProgram is AccessControl {
    bytes32 public constant MARKETPLACE_ROLE = keccak256("MARKETPLACE_ROLE");
    
    IERC20 public tbToken;
    
    struct ReferralInfo {
        address referrer;
        uint256 totalEarned;
        uint256 totalReferred;
        uint256[] referralLevels; // Comisiones por nivel (basis points)
    }
    
    mapping(address => ReferralInfo) public referrals;
    mapping(address => address) public referrerOf;
    mapping(address => address[]) public referralsOf;
    
    // Comisiones por nivel (por defecto: 5% nivel 1, 3% nivel 2, 1% nivel 3)
    uint256[] public levelCommissions = [500, 300, 100];
    
    // Eventos
    event ReferralRegistered(address indexed referrer, address indexed referral);
    event ReferralReward(
        address indexed referrer, 
        address indexed referral, 
        uint256 amount, 
        uint256 level
    );
    event CommissionsUpdated(uint256[] newCommissions);
    
    constructor(address _tbToken) {
        require(_tbToken != address(0), "Token address cannot be zero");
        tbToken = IERC20(_tbToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MARKETPLACE_ROLE, msg.sender);
    }
    
    // Registrar un referido
    function registerReferral(address referral, address referrer) 
        external 
        onlyRole(MARKETPLACE_ROLE) 
    {
        require(referrerOf[referral] == address(0), "Already referred");
        require(referrer != referral, "Cannot refer yourself");
        require(referrer != address(0), "Invalid referrer");
        
        referrerOf[referral] = referrer;
        referralsOf[referrer].push(referral);
        
        // Inicializar información del referente si no existe
        if (referrals[referrer].referrer == address(0)) {
            referrals[referrer] = ReferralInfo({
                referrer: address(0), // Se establecerá si hay un referente del referente
                totalEarned: 0,
                totalReferred: 0,
                referralLevels: levelCommissions
            });
        }
        
        referrals[referrer].totalReferred++;
        
        // Si el referente tiene un referente, registrar la relación
        if (referrals[referrer].referrer == address(0) && referrerOf[referrer] != address(0)) {
            referrals[referrer].referrer = referrerOf[referrer];
        }
        
        emit ReferralRegistered(referrer, referral);
    }
    
    // Distribuir recompensas de referidos
    function distributeReferralRewards(
        address customer, 
        uint256 purchaseAmountUSD
    ) external onlyRole(MARKETPLACE_ROLE) returns (uint256 totalRewards) {
        address currentReferrer = referrerOf[customer];
        uint256 totalDistributed = 0;
        
        for (uint256 level = 0; level < levelCommissions.length; level++) {
            if (currentReferrer == address(0)) break;
            
            uint256 commission = (purchaseAmountUSD * levelCommissions[level]) / 10000;
            
            if (commission > 0) {
                referrals[currentReferrer].totalEarned += commission;
                totalDistributed += commission;
                
                // Enviar recompensa en TB tokens
                tbToken.transfer(currentReferrer, commission);
                
                emit ReferralReward(currentReferrer, customer, commission, level + 1);
            }
            
            // Moverse al siguiente nivel
            currentReferrer = referrals[currentReferrer].referrer;
        }
        
        return totalDistributed;
    }
    
    // Actualizar comisiones por nivel
    function updateLevelCommissions(uint256[] memory newCommissions) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newCommissions.length <= 5, "Max 5 levels allowed");
        
        for (uint256 i = 0; i < newCommissions.length; i++) {
            require(newCommissions[i] <= 1000, "Commission cannot exceed 10%");
        }
        
        levelCommissions = newCommissions;
        
        emit CommissionsUpdated(newCommissions);
    }
    
    // Obtener información de referidos
    function getReferralInfo(address user) 
        external 
        view 
        returns (
            address referrer,
            uint256 totalEarned,
            uint256 totalReferred,
            address[] memory referralsList
        ) 
    {
        ReferralInfo memory info = referrals[user];
        return (
            info.referrer,
            info.totalEarned,
            info.totalReferred,
            referralsOf[user]
        );
    }
    
    // Obtener el árbol de referidos hasta cierto nivel
    function getReferralTree(address user, uint256 maxLevel) 
        external 
        view 
        returns (address[] memory tree, uint256[] memory levels) 
    {
        address[] memory tempTree = new address[](maxLevel);
        uint256[] memory tempLevels = new uint256[](maxLevel);
        
        address current = user;
        for (uint256 i = 0; i < maxLevel; i++) {
            address referrer = referrals[current].referrer;
            if (referrer == address(0)) break;
            
            tempTree[i] = referrer;
            tempLevels[i] = i + 1;
            current = referrer;
        }
        
        return (tempTree, tempLevels);
    }
}
