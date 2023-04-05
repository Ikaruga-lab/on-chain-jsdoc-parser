import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import './tasks';

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000
      },
      viaIR: true,
    },
    
  },
  paths: {
    sources: "./contracts",
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      gas: 10000000
    },
    goerli: {
      url: `https://eth-goerli.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: [
        process.env.PRIVATE_KEY_OWNER as string,
        process.env.PRIVATE_KEY_ADMIN as string,
        process.env.PRIVATE_KEY_USER as string
      ]
    }
  },
  mocha: {
    timeout: 100000000
  }
};

export default config;
