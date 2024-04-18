import pkg from 'hardhat';
const { ethers, upgrades } = pkg;

(async () => {
  const Contract = await ethers.getContractFactory("DomainRegister");
  const defaultFee = ethers.parseUnits("1", "ether");
  // const contract = await Contract.deploy();
  const contract = await upgrades.deployProxy(Contract, [defaultFee], {initializer: 'initialize'});
  console.log("DomainRegister deployed to:", await contract.getAddress());
})();
