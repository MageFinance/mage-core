import { HardhatUserConfig } from 'hardhat/config';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-waffle';
import dotenv from 'dotenv';
dotenv.config({ path: `.env.${process.env.NODE_ENV}` });

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.12',
    settings: {
      // viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {},
    mainnet: {
      url: 'https://rpc.merlinchain.io',
      chainId: 4200,
    },
    testnet: {
      url: 'https://testnet-rpc.merlinchain.io',
      chainId: 686868,
    },
  },
  mocha: {
    timeout: 400000,
  },
};

export default config;
