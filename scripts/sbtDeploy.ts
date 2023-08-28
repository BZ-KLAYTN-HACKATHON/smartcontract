import { ethers } from "hardhat";

async function main() {

  const sbt = await ethers.deployContract("SoulBoundToken")
  console.log(`Congratulations! You have just successfully deployed your soul bound tokens.`);
  console.log(`SBT contract address is ${sbt.target}. You can verify on https://mainnet.scope.klaytn.com/account/${sbt.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});