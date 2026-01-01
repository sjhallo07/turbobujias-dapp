import { network, run } from "hardhat";
import { existsSync, readFileSync } from "fs";
import { join } from "path";

async function main() {
    const networkName = network.name;
    const addressesPath = join(__dirname, "..", "deployed", `addresses-${networkName}.json`);

    if (!existsSync(addressesPath)) {
        console.error("Addresses file not found:", addressesPath);
        process.exit(1);
    }

    const addresses = JSON.parse(readFileSync(addressesPath, "utf8"));
    const contracts = addresses.contracts;

    console.log(`Verifying contracts on ${networkName}...`);

    // Verificar TBToken
    console.log("\n1. Verifying TBToken...");
    try {
        await run("verify:verify", {
            address: contracts.TBToken,
            constructorArguments: [
                addresses.deployer, // treasuryWallet
                addresses.deployer, // liquidityWallet
                addresses.deployer  // marketingWallet
            ],
        });
        console.log("✅ TBToken verified");
    } catch (error) {
        console.log("❌ TBToken verification failed:", error.message);
    }

    // Verificar PriceOracle
    console.log("\n2. Verifying PriceOracle...");
    try {
        await run("verify:verify", {
            address: contracts.PriceOracle,
            constructorArguments: [
                "0x694AA1769357215DE4FAC081bf1f309aDC325306" // Chainlink aggregator (Sepolia ETH/USD)
            ],
        });
        console.log("✅ PriceOracle verified");
    } catch (error) {
        console.log("❌ PriceOracle verification failed:", error.message);
    }

    // Verificar LoyaltyProgram
    console.log("\n3. Verifying LoyaltyProgram...");
    try {
        await run("verify:verify", {
            address: contracts.LoyaltyProgram,
            constructorArguments: [
                contracts.TBToken
            ],
        });
        console.log("✅ LoyaltyProgram verified");
    } catch (error) {
        console.log("❌ LoyaltyProgram verification failed:", error.message);
    }

    // Verificar ReferralProgram
    console.log("\n4. Verifying ReferralProgram...");
    try {
        await run("verify:verify", {
            address: contracts.ReferralProgram,
            constructorArguments: [
                contracts.TBToken
            ],
        });
        console.log("✅ ReferralProgram verified");
    } catch (error) {
        console.log("❌ ReferralProgram verification failed:", error.message);
    }

    // Verificar TBStaking
    console.log("\n5. Verifying TBStaking...");
    try {
        await run("verify:verify", {
            address: contracts.TBStaking,
            constructorArguments: [
                contracts.TBToken
            ],
        });
        console.log("✅ TBStaking verified");
    } catch (error) {
        console.log("❌ TBStaking verification failed:", error.message);
    }

    // Verificar AutoPartsMarketplaceV2
    console.log("\n6. Verifying AutoPartsMarketplaceV2...");
    try {
        await run("verify:verify", {
            address: contracts.AutoPartsMarketplaceV2,
            constructorArguments: [
                contracts.TBToken,
                contracts.PriceOracle,
                contracts.LoyaltyProgram,
                addresses.deployer // feeRecipient
            ],
        });
        console.log("✅ AutoPartsMarketplaceV2 verified");
    } catch (error) {
        console.log("❌ AutoPartsMarketplaceV2 verification failed:", error.message);
    }

    // Verificar AirdropManager
    console.log("\n7. Verifying AirdropManager...");
    try {
        await run("verify:verify", {
            address: contracts.AirdropManager,
            constructorArguments: [
                contracts.TBToken
            ],
        });
        console.log("✅ AirdropManager verified");
    } catch (error) {
        console.log("❌ AirdropManager verification failed:", error.message);
    }

    console.log("\n✅ Verification process completed!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
