const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TBToken", function () {
    let TBToken;
    let tbToken;
    let owner;
    let addr1;
    let addr2;
    let addrs;

    beforeEach(async function () {
        TBToken = await ethers.getContractFactory("TBToken");
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

        tbToken = await TBToken.deploy(
            owner.address,
            owner.address,
            owner.address
        );
        await tbToken.waitForDeployment();
    });

    describe("Deployment", function () {
        it("Should set the right owner", async function () {
            expect(await tbToken.hasRole(await tbToken.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
        });

        it("Should assign the initial supply to treasury", async function () {
            const treasuryBalance = await tbToken.balanceOf(owner.address);
            expect(treasuryBalance).to.equal(ethers.utils.parseUnits("500000000", 18));
        });

        it("Should have correct name and symbol", async function () {
            expect(await tbToken.name()).to.equal("AutoPartsChain Token");
            expect(await tbToken.symbol()).to.equal("TBC");
        });

        it("Should have max supply of 1 billion", async function () {
            expect(await tbToken.MAX_SUPPLY()).to.equal(ethers.utils.parseUnits("1000000000", 18));
        });
    });

    describe("Transactions", function () {
        it("Should transfer tokens between accounts", async function () {
            // Enable trading first
            await tbToken.enableTrading();

            // Transfer 100 tokens from owner to addr1
            await tbToken.transfer(addr1.address, 100);
            const addr1Balance = await tbToken.balanceOf(addr1.address);
            expect(addr1Balance).to.equal(100);

            // Transfer 50 tokens from addr1 to addr2
            await tbToken.connect(addr1).transfer(addr2.address, 50);
            const addr2Balance = await tbToken.balanceOf(addr2.address);
            expect(addr2Balance).to.equal(50);
        });

        it("Should fail if sender doesn't have enough tokens", async function () {
            const initialOwnerBalance = await tbToken.balanceOf(owner.address);

            // Try to send 1 token from addr1 (0 tokens) to owner
            await expect(
                tbToken.connect(addr1).transfer(owner.address, 1)
            ).to.be.revertedWith("ERC20: transfer amount exceeds balance");

            // Owner balance shouldn't have changed
            expect(await tbToken.balanceOf(owner.address)).to.equal(initialOwnerBalance);
        });

        it("Should update balances after transfers", async function () {
            const initialOwnerBalance = await tbToken.balanceOf(owner.address);

            // Enable trading and transfer
            await tbToken.enableTrading();
            await tbToken.transfer(addr1.address, 100);
            await tbToken.transfer(addr2.address, 50);

            const finalOwnerBalance = await tbToken.balanceOf(owner.address);
            expect(finalOwnerBalance).to.equal(initialOwnerBalance.sub(150));

            const addr1Balance = await tbToken.balanceOf(addr1.address);
            expect(addr1Balance).to.equal(100);

            const addr2Balance = await tbToken.balanceOf(addr2.address);
            expect(addr2Balance).to.equal(50);
        });
    });

    describe("Fees", function () {
        beforeEach(async function () {
            // Enable trading
            await tbToken.enableTrading();

            // Exclude addresses from limits for testing
            await tbToken.setExcludedFromLimits(addr1.address, true);
            await tbToken.setExcludedFromLimits(addr2.address, true);

            // Transfer tokens to addr1 for testing
            await tbToken.transfer(addr1.address, ethers.utils.parseUnits("1000", 18));
        });

        it("Should apply buy fee when buying from DEX", async function () {
            // Set up a mock DEX pair
            await tbToken.setAutomatedMarketMakerPair(addr2.address, true);

            // Transfer from DEX (addr2) to addr1 (simulating a buy)
            await tbToken.connect(addr2).transfer(addr1.address, ethers.utils.parseUnits("100", 18));

            // Check if fee was applied (3% of 100 = 3 tokens)
            const contractBalance = await tbToken.balanceOf(tbToken.address);
            expect(contractBalance).to.be.above(0);
        });

        it("Should apply sell fee when selling to DEX", async function () {
            // Set up a mock DEX pair
            await tbToken.setAutomatedMarketMakerPair(addr2.address, true);

            // Transfer from addr1 to DEX (addr2) (simulating a sell)
            await tbToken.connect(addr1).transfer(addr2.address, ethers.utils.parseUnits("100", 18));

            // Check if fee was applied
            const contractBalance = await tbToken.balanceOf(tbToken.address);
            expect(contractBalance).to.be.above(0);
        });
    });

    describe("Pausable", function () {
        it("Should pause and unpause transfers", async function () {
            await tbToken.enableTrading();
            await tbToken.transfer(addr1.address, 100);

            // Pause transfers
            await tbToken.pause();

            // Try to transfer while paused
            await expect(
                tbToken.connect(addr1).transfer(addr2.address, 50)
            ).to.be.revertedWith("Pausable: paused");

            // Unpause transfers
            await tbToken.unpause();

            // Transfer should work now
            await tbToken.connect(addr1).transfer(addr2.address, 50);
            expect(await tbToken.balanceOf(addr2.address)).to.equal(50);
        });
    });

    describe("Snapshot", function () {
        it("Should create snapshots", async function () {
            await tbToken.enableTrading();
            await tbToken.transfer(addr1.address, 100);

            // Take snapshot
            const snapshot1 = await tbToken.snapshot();

            // Transfer more tokens
            await tbToken.transfer(addr1.address, 50);

            // Check balance at snapshot
            const balanceAtSnapshot = await tbToken.balanceOfAt(addr1.address, snapshot1);
            expect(balanceAtSnapshot).to.equal(100);

            // Check current balance
            const currentBalance = await tbToken.balanceOf(addr1.address);
            expect(currentBalance).to.equal(150);
        });
    });
});
