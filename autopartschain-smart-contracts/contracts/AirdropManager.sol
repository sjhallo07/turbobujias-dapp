// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title AirdropManager
 * @dev Gestor de airdrops con múltiples campañas y verificación Merkle Proof
 */
contract AirdropManager is AccessControl {
    bytes32 public constant AIRDROP_MANAGER_ROLE = keccak256("AIRDROP_MANAGER_ROLE");
    
    IERC20 public tbToken;
    
    struct AirdropCampaign {
        uint256 id;
        string name;
        bytes32 merkleRoot;
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 startTime;
        uint256 endTime;
        bool active;
        mapping(address => bool) claimed;
    }
    
    uint256 public campaignCount;
    mapping(uint256 => AirdropCampaign) public campaigns;
    
    // Eventos
    event CampaignCreated(
        uint256 indexed campaignId, 
        string name, 
        uint256 totalAmount, 
        uint256 startTime, 
        uint256 endTime
    );
    event AirdropClaimed(
        uint256 indexed campaignId, 
        address indexed user, 
        uint256 amount
    );
    event CampaignUpdated(uint256 indexed campaignId, bool active);
    
    constructor(address _tbToken) {
        require(_tbToken != address(0), "Token address cannot be zero");
        tbToken = IERC20(_tbToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AIRDROP_MANAGER_ROLE, msg.sender);
    }
    
    // Crear una nueva campaña de airdrop
    function createCampaign(
        string memory name,
        bytes32 merkleRoot,
        uint256 totalAmount,
        uint256 startTime,
        uint256 endTime
    ) external onlyRole(AIRDROP_MANAGER_ROLE) returns (uint256) {
        require(totalAmount > 0, "Total amount must be positive");
        require(startTime < endTime, "Invalid time range");
        require(merkleRoot != bytes32(0), "Merkle root cannot be zero");
        
        campaignCount++;
        uint256 newCampaignId = campaignCount;
        
        AirdropCampaign storage campaign = campaigns[newCampaignId];
        campaign.id = newCampaignId;
        campaign.name = name;
        campaign.merkleRoot = merkleRoot;
        campaign.totalAmount = totalAmount;
        campaign.claimedAmount = 0;
        campaign.startTime = startTime;
        campaign.endTime = endTime;
        campaign.active = true;
        
        // Transferir los tokens al contrato
        require(
            tbToken.transferFrom(msg.sender, address(this), totalAmount),
            "Token transfer failed"
        );
        
        emit CampaignCreated(newCampaignId, name, totalAmount, startTime, endTime);
        return newCampaignId;
    }
    
    // Reclamar airdrop
    function claimAirdrop(
        uint256 campaignId,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external {
        AirdropCampaign storage campaign = campaigns[campaignId];
        
        require(campaign.active, "Campaign is not active");
        require(block.timestamp >= campaign.startTime, "Campaign has not started");
        require(block.timestamp <= campaign.endTime, "Campaign has ended");
        require(!campaign.claimed[msg.sender], "Already claimed");
        require(
            campaign.claimedAmount + amount <= campaign.totalAmount,
            "Insufficient campaign funds"
        );
        
        // Verificar Merkle Proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        require(
            MerkleProof.verify(merkleProof, campaign.merkleRoot, leaf),
            "Invalid proof"
        );
        
        // Marcar como reclamado
        campaign.claimed[msg.sender] = true;
        campaign.claimedAmount += amount;
        
        // Transferir tokens
        require(tbToken.transfer(msg.sender, amount), "Token transfer failed");
        
        emit AirdropClaimed(campaignId, msg.sender, amount);
    }
    
    // Actualizar estado de la campaña
    function updateCampaignStatus(uint256 campaignId, bool active) 
        external 
        onlyRole(AIRDROP_MANAGER_ROLE) 
    {
        require(campaignId <= campaignCount, "Invalid campaign ID");
        campaigns[campaignId].active = active;
        
        emit CampaignUpdated(campaignId, active);
    }
    
    // Recuperar tokens no reclamados después de que termine la campaña
    function recoverUnclaimedTokens(uint256 campaignId) 
        external 
        onlyRole(AIRDROP_MANAGER_ROLE) 
    {
        AirdropCampaign storage campaign = campaigns[campaignId];
        
        require(block.timestamp > campaign.endTime, "Campaign has not ended");
        
        uint256 unclaimedAmount = campaign.totalAmount - campaign.claimedAmount;
        if (unclaimedAmount > 0) {
            campaign.totalAmount = campaign.claimedAmount;
            require(
                tbToken.transfer(msg.sender, unclaimedAmount),
                "Token transfer failed"
            );
        }
    }
    
    // Verificar si un usuario ha reclamado en una campaña
    function hasClaimed(uint256 campaignId, address user) 
        external 
        view 
        returns (bool) 
    {
        return campaigns[campaignId].claimed[user];
    }
    
    // Obtener información de la campaña
    function getCampaignInfo(uint256 campaignId)
        external
        view
        returns (
            string memory name,
            uint256 totalAmount,
            uint256 claimedAmount,
            uint256 startTime,
            uint256 endTime,
            bool active
        )
    {
        AirdropCampaign storage campaign = campaigns[campaignId];
        return (
            campaign.name,
            campaign.totalAmount,
            campaign.claimedAmount,
            campaign.startTime,
            campaign.endTime,
            campaign.active
        );
    }
}
