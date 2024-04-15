import pkg from 'hardhat';
const { ethers, upgrades } = pkg;

async function main() {
    const DomainRegisterV1 = await ethers.getContractFactory("DomainRegister");
    const existingContractAddress = "address of existing contract";
    const DomainRegisterV2 = await ethers.getContractFactory("DomainRegisterV2");
    console.log("Upgrading contract...");
    const upgraded = await upgrades.upgradeProxy(existingContractAddress, DomainRegisterV2);
    console.log("Contract has been upgraded to version 2 at address:", upgraded.address);
}

main().then(() => process.exit(0)).catch(error => {
    console.error(error);
    process.exit(1);
});