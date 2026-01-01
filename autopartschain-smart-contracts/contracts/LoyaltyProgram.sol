// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LoyaltyProgram
 * @dev Programa de lealtad con NFTs de nivel y múltiples beneficios
 */
contract LoyaltyProgram is AccessControl, ERC721, ERC721Enumerable {
    bytes32 public constant MARKETPLACE_ROLE = keccak256("MARKETPLACE_ROLE");
    
    IERC20 public tbToken;
    
    // Estructura para los niveles de lealtad
    struct LoyaltyTier {
        string name;
        uint256 minPoints;
        uint256 minPurchasesUSD;
        uint256 discount; // En basis points (1000 = 10%)
        uint256 cashback; // En basis points (500 = 5%)
        uint256 stakingBoost; // Boost adicional para staking (1000 = 10%)
        uint256 freeShippingThreshold; // En centavos USD (0 = no aplica)
        string tokenURI; // URI del NFT para este nivel
    }
    
    // Estructura para el cliente
    struct Customer {
        uint256 totalSpentUSD;
        uint256 loyaltyPoints;
        uint256 currentTier;
        uint256 joinedAt;
        uint256 lastPurchaseAt;
        uint256 totalCashbackReceived;
        uint256 totalDiscountSaved;
        uint256 referralCount;
        uint256 referralPoints;
    }
    
    // NFTs de lealtad
    mapping(uint256 => uint256) public tokenIdToTier;
    
    LoyaltyTier[] public tiers;
    mapping(address => Customer) public customers;
    mapping(address => address) public referrerOf; // referido -> referente
    mapping(address => address[]) public referralsOf; // referente -> lista de referidos
    
    // Eventos
    event TierUpgraded(address indexed customer, uint256 oldTier, uint256 newTier);
    event PointsEarned(address indexed customer, uint256 points, uint256 purchaseAmount);
    event PointsRedeemed(address indexed customer, uint256 points, uint256 discount);
    event CashbackReceived(address indexed customer, uint256 amount);
    event ReferralRegistered(address indexed referrer, address indexed referral);
    event ReferralRewarded(address indexed referrer, address indexed referral, uint256 points);
    
    constructor(address _tbToken) ERC721("AutoPartsChain Loyalty", "APCL") {
        require(_tbToken != address(0), "Token address cannot be zero");
        tbToken = IERC20(_tbToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MARKETPLACE_ROLE, msg.sender);
        
        // Inicializar niveles de lealtad
        _addTier("Bronze", 0, 0, 0, 0, 0, 0, "ipfs://bronze");
        _addTier("Silver", 1000, 10000, 500, 200, 500, 10000, "ipfs://silver");
        _addTier("Gold", 5000, 50000, 1000, 500, 1000, 5000, "ipfs://gold");
        _addTier("Platinum", 20000, 200000, 1500, 1000, 2000, 0, "ipfs://platinum");
        _addTier("Diamond", 50000, 500000, 2000, 1500, 3000, 0, "ipfs://diamond");
    }
    
    // Añadir un nuevo nivel (solo admin)
    function addTier(
        string memory name,
        uint256 minPoints,
        uint256 minPurchasesUSD,
        uint256 discount,
        uint256 cashback,
        uint256 stakingBoost,
        uint256 freeShippingThreshold,
        string memory tokenURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addTier(name, minPoints, minPurchasesUSD, discount, cashback, stakingBoost, freeShippingThreshold, tokenURI);
    }
    
    function _addTier(
        string memory name,
        uint256 minPoints,
        uint256 minPurchasesUSD,
        uint256 discount,
        uint256 cashback,
        uint256 stakingBoost,
        uint256 freeShippingThreshold,
        string memory tokenURI
    ) internal {
        tiers.push(LoyaltyTier({
            name: name,
            minPoints: minPoints,
            minPurchasesUSD: minPurchasesUSD,
            discount: discount,
            cashback: cashback,
            stakingBoost: stakingBoost,
            freeShippingThreshold: freeShippingThreshold,
            tokenURI: tokenURI
        }));
    }
    
    // Registrar una compra (solo marketplace)
    function recordPurchase(
        address customer,
        uint256 purchaseAmountUSD,
        address referrer
    ) external onlyRole(MARKETPLACE_ROLE) returns (uint256 cashbackAmount) {
        Customer storage cust = customers[customer];
        
        // Registrar referido si es la primera compra y se proporciona un referente
        if (cust.joinedAt == 0 && referrer != address(0) && referrer != customer) {
            _registerReferral(customer, referrer);
        }
        
        // Para nuevos clientes
        if (cust.joinedAt == 0) {
            cust.joinedAt = block.timestamp;
            cust.currentTier = 0; // Bronce
            _mintLoyaltyNFT(customer, 0);
        }
        
        // Actualizar gasto total
        cust.totalSpentUSD += purchaseAmountUSD;
        cust.lastPurchaseAt = block.timestamp;
        
        // Calcular puntos (1 punto por cada dólar centavo, es decir, 100 puntos por USD)
        uint256 pointsEarned = purchaseAmountUSD; // purchaseAmountUSD está en centavos
        cust.loyaltyPoints += pointsEarned;
        
        // Recompensar al referente si existe
        if (referrerOf[customer] != address(0)) {
            address ref = referrerOf[customer];
            uint256 referralPoints = pointsEarned / 10; // 10% de los puntos del referido
            customers[ref].referralPoints += referralPoints;
            customers[ref].loyaltyPoints += referralPoints;
            
            emit ReferralRewarded(ref, customer, referralPoints);
        }
        
        // Verificar upgrade de nivel
        uint256 newTier = getTierForCustomer(customer);
        if (newTier > cust.currentTier) {
            uint256 oldTier = cust.currentTier;
            cust.currentTier = newTier;
            
            // Actualizar NFT si el nivel cambió
            _updateLoyaltyNFT(customer, newTier);
            
            emit TierUpgraded(customer, oldTier, newTier);
        }
        
        // Calcular cashback según nivel actual
        LoyaltyTier memory tier = tiers[cust.currentTier];
        cashbackAmount = (purchaseAmountUSD * tier.cashback) / 10000;
        
        if (cashbackAmount > 0) {
            cust.totalCashbackReceived += cashbackAmount;
            emit CashbackReceived(customer, cashbackAmount);
        }
        
        emit PointsEarned(customer, pointsEarned, purchaseAmountUSD);
        return cashbackAmount;
    }
    
    // Registrar un referido
    function _registerReferral(address referral, address referrer) internal {
        require(referrerOf[referral] == address(0), "Already referred");
        require(referrer != referral, "Cannot refer yourself");
        
        referrerOf[referral] = referrer;
        referralsOf[referrer].push(referral);
        customers[referrer].referralCount++;
        
        emit ReferralRegistered(referrer, referral);
    }
    
    // Acuñar NFT de lealtad
    function _mintLoyaltyNFT(address customer, uint256 tier) internal {
        uint256 tokenId = uint256(uint160(customer)); // Usar la dirección como tokenId
        _safeMint(customer, tokenId);
        tokenIdToTier[tokenId] = tier;
    }
    
    // Actualizar NFT de lealtad (quemar el viejo y acuñar nuevo)
    function _updateLoyaltyNFT(address customer, uint256 newTier) internal {
        uint256 tokenId = uint256(uint160(customer));
        
        // Quemar el NFT viejo
        _burn(tokenId);
        
        // Acuñar nuevo NFT con el nuevo nivel
        _safeMint(customer, tokenId);
        tokenIdToTier[tokenId] = newTier;
    }
    
    // Obtener nivel basado en puntos y gasto
    function getTierForCustomer(address customer) public view returns (uint256) {
        Customer memory cust = customers[customer];
        
        for (uint256 i = tiers.length; i > 0; i--) {
            uint256 index = i - 1;
            if (cust.loyaltyPoints >= tiers[index].minPoints && 
                cust.totalSpentUSD >= tiers[index].minPurchasesUSD) {
                return index;
            }
        }
        return 0;
    }
    
    // Canjear puntos por descuento
    function redeemPoints(uint256 points) external {
        Customer storage cust = customers[msg.sender];
        require(cust.loyaltyPoints >= points, "Insufficient points");
        
        // 100 puntos = 1% de descuento en próxima compra
        uint256 discountPercent = points / 100;
        require(discountPercent <= 5000, "Max 50% discount");
        
        cust.loyaltyPoints -= points;
        cust.totalDiscountSaved += discountPercent;
        
        emit PointsRedeemed(msg.sender, points, discountPercent);
    }
    
    // Obtener descuento actual del cliente
    function getCustomerDiscount(address customer) external view returns (uint256) {
        uint256 tier = getTierForCustomer(customer);
        return tiers[tier].discount;
    }
    
    // Obtener boost de staking
    function getStakingBoost(address customer) external view returns (uint256) {
        uint256 tier = getTierForCustomer(customer);
        return tiers[tier].stakingBoost;
    }
    
    // Obtener umbral de envío gratis
    function getFreeShippingThreshold(address customer) external view returns (uint256) {
        uint256 tier = getTierForCustomer(customer);
        return tiers[tier].freeShippingThreshold;
    }
    
    // Obtener información del cliente
    function getCustomerInfo(address customer) 
        external 
        view 
        returns (
            Customer memory,
            uint256 currentTier,
            string memory tierName,
            uint256 nextTierPointsNeeded,
            uint256 nextTierSpendNeeded
        ) 
    {
        Customer memory cust = customers[customer];
        uint256 tier = getTierForCustomer(customer);
        string memory tierNameStr = tiers[tier].name;
        
        // Calcular requisitos para el siguiente nivel
        uint256 nextTierPoints = 0;
        uint256 nextTierSpend = 0;
        if (tier < tiers.length - 1) {
            nextTierPoints = tiers[tier + 1].minPoints - cust.loyaltyPoints;
            nextTierSpend = tiers[tier + 1].minPurchasesUSD - cust.totalSpentUSD;
        }
        
        return (cust, tier, tierNameStr, nextTierPoints, nextTierSpend);
    }
    
    // Obtener referidos de un cliente
    function getCustomerReferrals(address customer) 
        external 
        view 
        returns (address[] memory) 
    {
        return referralsOf[customer];
    }
    
    // Funciones de soporte para ERC721Enumerable
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        
        // Los NFTs de lealtad no son transferibles (excepto por quema/acuñación)
        require(from == address(0) || to == address(0), "Loyalty NFTs are non-transferable");
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    
    function tokenURI(uint256 tokenId) 
        public 
        view 
        override 
        returns (string memory) 
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(_exists(tokenId), "Token does not exist");
        uint256 tier = tokenIdToTier[tokenId];
        return tiers[tier].tokenURI;
    }
}
