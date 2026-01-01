const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AutoPartsMarketplaceV2", function () {
    let TBToken, PriceOracle, LoyaltyProgram, AutoPartsMarketplaceV2;
    let tbToken, priceOracle, loyaltyProgram, marketplace;
    let owner, addr1, addr2, addrs;

    beforeEach(async function () {
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

        // Desplegar TBToken
        TBToken = await ethers.getContractFactory("TBToken");
        tbToken = await TBToken.deploy(
            owner.address,
            owner.address,
            owner.address
        );
        await tbToken.deployed();

        // Desplegar PriceOracle
        PriceOracle = await ethers.getContractFactory("PriceOracle");
        priceOracle = await PriceOracle.deploy(ethers.constants.AddressZero); // Sin Chainlink para pruebas
        await priceOracle.deployed();

        // Desplegar LoyaltyProgram
        LoyaltyProgram = await ethers.getContractFactory("LoyaltyProgram");
        loyaltyProgram = await LoyaltyProgram.deploy(tbToken.address);
        await loyaltyProgram.deployed();

        // Desplegar Marketplace
        AutoPartsMarketplaceV2 = await ethers.getContractFactory("AutoPartsMarketplaceV2");
        marketplace = await AutoPartsMarketplaceV2.deploy(
            tbToken.address,
            priceOracle.address,
            loyaltyProgram.address,
            owner.address
        );
        await marketplace.deployed();

        // Configurar roles
        await tbToken.grantRole(await tbToken.MINTER_ROLE(), marketplace.address);
        await tbToken.grantRole(await tbToken.MINTER_ROLE(), loyaltyProgram.address);
        await loyaltyProgram.grantRole(await loyaltyProgram.MARKETPLACE_ROLE(), marketplace.address);

        // Configurar precio
        await priceOracle.updatePriceManually(100); // 1 TB = 0.000001 USD

        // Habilitar trading en TBToken
        await tbToken.enableTrading();

        // Dar tokens a addr1 para pruebas
        await tbToken.transfer(addr1.address, ethers.utils.parseUnits("1000000", 18));
        await tbToken.connect(addr1).approve(marketplace.address, ethers.constants.MaxUint256);
    });

    describe("Product Management", function () {
        it("Should list a new product", async function () {
            const tx = await marketplace.listProduct(
                "TEST-001",
                "Test Product",
                "Test Description",
                "Test Category",
                "Test Brand",
                "Test Vehicle",
                "123456",
                ["ipfs://test1"],
                1000, // $10.00
                500,  // $5.00 cost
                100,  // stock
                1,    // min order
                10,   // max order
                1000, // weight
                [],
                false,
                ""
            );

            await expect(tx)
                .to.emit(marketplace, "ProductListed")
                .withArgs(1, "TEST-001", "Test Product", 1000, 100);

            const product = await marketplace.products(1);
            expect(product.sku).to.equal("TEST-001");
            expect(product.name).to.equal("Test Product");
            expect(product.priceUSD).to.equal(1000);
            expect(product.stock).to.equal(100);
        });

        it("Should update product stock", async function () {
            await marketplace.listProduct(
                "TEST-001",
                "Test Product",
                "Test Description",
                "Test Category",
                "Test Brand",
                "Test Vehicle",
                "123456",
                ["ipfs://test1"],
                1000,
                500,
                100,
                1,
                10,
                1000,
                [],
                false,
                ""
            );

            await marketplace.updateStock(1, 150, "Restocked");

            const product = await marketplace.products(1);
            expect(product.stock).to.equal(150);
        });
    });

    describe("Cart Management", function () {
        beforeEach(async function () {
            await marketplace.listProduct(
                "TEST-001",
                "Test Product",
                "Test Description",
                "Test Category",
                "Test Brand",
                "Test Vehicle",
                "123456",
                ["ipfs://test1"],
                1000,
                500,
                100,
                1,
                10,
                1000,
                [],
                false,
                ""
            );
        });

        it("Should add product to cart", async function () {
            await marketplace.connect(addr1).addToCart(1, 2);

            const cart = await marketplace.userCarts(addr1.address);
            expect(cart.productIds.length).to.equal(1);
            expect(cart.productIds[0]).to.equal(1);
            expect(cart.quantities[0]).to.equal(2);
        });

        it("Should remove product from cart", async function () {
            await marketplace.connect(addr1).addToCart(1, 2);
            await marketplace.connect(addr1).removeFromCart(1);

            const cart = await marketplace.userCarts(addr1.address);
            expect(cart.productIds.length).to.equal(0);
        });
    });

    describe("Order Management", function () {
        beforeEach(async function () {
            await marketplace.listProduct(
                "TEST-001",
                "Test Product",
                "Test Description",
                "Test Category",
                "Test Brand",
                "Test Vehicle",
                "123456",
                ["ipfs://test1"],
                1000, // $10.00
                500,
                100,
                1,
                10,
                1000,
                [],
                false,
                ""
            );

            await marketplace.connect(addr1).addToCart(1, 2);
        });

        it("Should create order from cart", async function () {
            const tx = await marketplace.connect(addr1).createOrderFromCart(
                "123 Test St",
                "Standard",
                "Test notes",
                "",
                false,
                ethers.constants.AddressZero,
                ""
            );

            await expect(tx)
                .to.emit(marketplace, "OrderCreated")
                .withArgs(1, addr1.address, 2000, anyValue); // $20.00 = 2000 cents

            const order = await marketplace.orders(1);
            expect(order.customer).to.equal(addr1.address);
            expect(order.totalUSD).to.equal(2000);
            expect(order.status).to.equal(0); // CART status
        });

        it("Should pay for order", async function () {
            // Create order
            await marketplace.connect(addr1).createOrderFromCart(
                "123 Test St",
                "Standard",
                "Test notes",
                "",
                false,
                ethers.constants.AddressZero,
                ""
            );

            // Pay order
            const tx = await marketplace.connect(addr1).payOrder(1);

            await expect(tx)
                .to.emit(marketplace, "OrderPaid")
                .withArgs(1, addr1.address, anyValue);

            const order = await marketplace.orders(1);
            expect(order.status).to.equal(2); // PAID status

            const product = await marketplace.products(1);
            expect(product.stock).to.equal(98); // 100 - 2
        });
    });

    describe("Discount Management", function () {
        it("Should create and apply discount", async function () {
            // Create product
            await marketplace.listProduct(
                "TEST-001",
                "Test Product",
                "Test Description",
                "Test Category",
                "Test Brand",
                "Test Vehicle",
                "123456",
                ["ipfs://test1"],
                1000,
                500,
                100,
                1,
                10,
                1000,
                [],
                false,
                ""
            );

            // Create discount
            await marketplace.createDiscount(
                "TEST10",
                1000, // 10%
                500,  // Max $5 discount
                1000, // Min $10 purchase
                100,  // Usage limit
                Math.floor(Date.now() / 1000) - 3600,
                Math.floor(Date.now() / 1000) + 3600
            );

            // Add to cart
            await marketplace.connect(addr1).addToCart(1, 2); // $20 total

            // Create order with discount
            const tx = await marketplace.connect(addr1).createOrderFromCart(
                "123 Test St",
                "Standard",
                "Test notes",
                "TEST10",
                false,
                ethers.constants.AddressZero,
                ""
            );

            await expect(tx)
                .to.emit(marketplace, "DiscountApplied")
                .withArgs(1, "TEST10", 200); // 10% of $20 = $2 = 200 cents

            const order = await marketplace.orders(1);
            expect(order.totalUSD).to.equal(1800); // $20 - $2 = $18
        });
    });
});

// Helper para cualquier valor
function anyValue() {
    return true;
}
