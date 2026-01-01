import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "dotenv/config";

const {
    PRIVATE_KEY,
    SEPOLIA_RPC_URL,
    MUMBAI_RPC_URL,
    POLYGON_RPC_URL,
    ETHERSCAN_API_KEY,
    POLYGONSCAN_API_KEY,
    COINMARKETCAP_API_KEY
} = process.env;

/** @type import('hardhat/config').HardhatUserConfig */
export const solidity = {
    version: "0.8.19",
    settings: {
        optimizer: {
            enabled: true,
            runs: 200,
        },
        viaIR: true,
    },
};
export const networks = {
    hardhat: {
        chainId: 31337,
        allowUnlimitedContractSize: true,
    },
    localhost: {
        url: "http://127.0.0.1:8545",
        chainId: 31337,
    },
    sepolia: {
        url: SEPOLIA_RPC_URL || "https://rpc.sepolia.org",
        accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
        chainId: 11155111,
    },
    mumbai: {
        url: MUMBAI_RPC_URL || "https://rpc-mumbai.maticvigil.com",
        accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
        chainId: 80001,
        gasPrice: 35000000000, // 35 gwei
    },
    polygon: {
        url: POLYGON_RPC_URL || "https://polygon-rpc.com",
        accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
        chainId: 137,
    },
    arbitrum: {
        url: "https://arb1.arbitrum.io/rpc",
        accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
        chainId: 42161,
    },
    optimism: {
        url: "https://mainnet.optimism.io",
        accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
        chainId: 10,
    },
};
export const etherscan = {
    apiKey: {
        sepolia: ETHERSCAN_API_KEY,
        polygon: POLYGONSCAN_API_KEY,
        polygonMumbai: POLYGONSCAN_API_KEY,
        arbitrumOne: process.env.ARBISCAN_API_KEY,
        optimisticEthereum: process.env.OPTIMISM_API_KEY,
    },
};
export const gasReporter = {
    enabled: process.env.REPORT_GAS ? true : false,
    currency: "USD",
    coinmarketcap: COINMARKETCAP_API_KEY,
    token: "MATIC",
    gasPriceApi: "https://api.polygonscan.com/api?module=proxy&action=eth_gasPrice",
};
export const paths = {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
};
export const mocha = {
    timeout: 40000,
};
