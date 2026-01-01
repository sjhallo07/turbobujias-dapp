// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PriceOracle
 * @dev Oracle de precios que combina múltiples fuentes (Chainlink, Uniswap, y un feed propio)
 */
contract PriceOracle is AccessControl {
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    
    // Estructura para múltiples fuentes de precio
    struct PriceSource {
        address aggregator; // Dirección del contrato Chainlink Aggregator
        uint8 decimals;     // Decimales del precio
        bool active;        // Si la fuente está activa
        string description; // Descripción de la fuente
    }
    
    // Precio actual del TB token en USD (con 8 decimales, igual que Chainlink)
    uint256 public currentPrice;
    uint256 public lastUpdated;
    
    // Múltiples fuentes de precio
    PriceSource[] public priceSources;
    
    // Historial de precios
    struct PriceUpdate {
        uint256 price;
        uint256 timestamp;
        string source;
    }
    
    PriceUpdate[] public priceHistory;
    
    // Eventos
    event PriceUpdated(uint256 newPrice, uint256 timestamp, string source);
    event PriceSourceAdded(uint256 sourceId, address aggregator, string description);
    event PriceSourceRemoved(uint256 sourceId);
    
    // Constructor: inicializa con una fuente Chainlink (por ejemplo, ETH/USD)
    constructor(address chainlinkAggregator) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PRICE_UPDATER_ROLE, msg.sender);
        
        // Inicializar con el precio por defecto: 1 TB = 0.000001 USD (100 * 10^-8)
        currentPrice = 100; // 0.000001 * 10^8 = 100 (8 decimales)
        lastUpdated = block.timestamp;
        
        // Si se proporciona un agregador Chainlink, añadirlo como fuente
        if (chainlinkAggregator != address(0)) {
            priceSources.push(PriceSource({
                aggregator: chainlinkAggregator,
                decimals: AggregatorV3Interface(chainlinkAggregator).decimals(),
                active: true,
                description: "Chainlink ETH/USD"
            }));
        }
        
        // Registrar el precio inicial en el historial
        priceHistory.push(PriceUpdate({
            price: currentPrice,
            timestamp: block.timestamp,
            source: "Initial"
        }));
    }
    
    // Añadir una nueva fuente de precio
    function addPriceSource(address aggregator, string memory description) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        uint8 decimals = AggregatorV3Interface(aggregator).decimals();
        priceSources.push(PriceSource({
            aggregator: aggregator,
            decimals: decimals,
            active: true,
            description: description
        }));
        
        uint256 sourceId = priceSources.length - 1;
        emit PriceSourceAdded(sourceId, aggregator, description);
    }
    
    // Desactivar una fuente de precio
    function removePriceSource(uint256 sourceId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(sourceId < priceSources.length, "Invalid source ID");
        priceSources[sourceId].active = false;
        emit PriceSourceRemoved(sourceId);
    }
    
    // Actualizar el precio desde una fuente específica
    function updatePriceFromSource(uint256 sourceId) external {
        require(sourceId < priceSources.length, "Invalid source ID");
        PriceSource memory source = priceSources[sourceId];
        require(source.active, "Source is not active");
        
        AggregatorV3Interface aggregator = AggregatorV3Interface(source.aggregator);
        (, int256 price, , , ) = aggregator.latestRoundData();
        
        // El precio de Chainlink viene con 8 decimales por defecto para ETH/USD
        // Ajustar según sea necesario
        uint256 newPrice = uint256(price);
        
        // Actualizar el precio actual
        currentPrice = newPrice;
        lastUpdated = block.timestamp;
        
        // Registrar en el historial
        priceHistory.push(PriceUpdate({
            price: newPrice,
            timestamp: block.timestamp,
            source: source.description
        }));
        
        emit PriceUpdated(newPrice, block.timestamp, source.description);
    }
    
    // Actualizar el precio manualmente (solo para roles permitidos)
    function updatePriceManually(uint256 newPrice) external onlyRole(PRICE_UPDATER_ROLE) {
        require(newPrice > 0, "Price must be positive");
        currentPrice = newPrice;
        lastUpdated = block.timestamp;
        
        priceHistory.push(PriceUpdate({
            price: newPrice,
            timestamp: block.timestamp,
            source: "Manual"
        }));
        
        emit PriceUpdated(newPrice, block.timestamp, "Manual");
    }
    
    // Obtener el precio actual
    function getPrice() external view returns (uint256) {
        return currentPrice;
    }
    
    // Calcular la cantidad de TB necesaria para una cantidad en USD
    function calculateTBForUSD(uint256 usdAmount) external view returns (uint256) {
        // usdAmount en centavos (2 decimales) -> Convertir a 18 decimales para cálculos
        // Suponemos que usdAmount está en centavos (por ejemplo, 1000 = $10.00)
        // El precio actual (currentPrice) está en 8 decimales (por ejemplo, 100 = $0.000001)
        
        // Convertir usdAmount (centavos) a wei (18 decimales)
        // 1 USD = 100 centavos, entonces usdAmount en centavos -> usdAmount * 10^16 para tener 18 decimales
        uint256 usdInWei = usdAmount * 10**16;
        
        // currentPrice tiene 8 decimales, por lo que para ajustar a 18 decimales:
        // TB = (usdInWei * 10^8) / currentPrice
        return (usdInWei * 10**8) / currentPrice;
    }
    
    // Obtener el historial de precios
    function getPriceHistory(uint256 limit) external view returns (PriceUpdate[] memory) {
        uint256 length = priceHistory.length;
        if (limit > length) {
            limit = length;
        }
        
        PriceUpdate[] memory history = new PriceUpdate[](limit);
        for (uint256 i = 0; i < limit; i++) {
            history[i] = priceHistory[length - 1 - i];
        }
        return history;
    }
    
    // Obtener el número de fuentes de precio
    function getPriceSourcesCount() external view returns (uint256) {
        return priceSources.length;
    }
}
