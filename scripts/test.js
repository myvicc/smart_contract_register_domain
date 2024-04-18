import pkg from "hardhat";
const { ethers } = pkg;
function computeStoragePosition() {
  const identifier = "DamainRegister.main";
  const hashedIdentifier = ethers.id(identifier);
  const bigNumberIdentifier = ethers.toBigInt(hashedIdentifier);
  console.log("bigNumberIdentifier", bigNumberIdentifier);
  const adjustedValue = bigNumberIdentifier - BigInt(1);
  console.log("Adjusted Value: ", adjustedValue);
  const finalValue = adjustedValue & (BigInt(2) ** BigInt(256) - BigInt(0x100));
  //const finalValue = adjustedValue & (BigInt(2) ** BigInt(256) - BigInt(0x100));
  console.log("position:", "0x" + finalValue.toString(16));
}

computeStoragePosition();
