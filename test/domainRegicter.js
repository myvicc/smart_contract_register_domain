import { expect } from "chai";
import pkg from "hardhat";
const { ethers, upgrades } = pkg;

let domainRegister;
let owner, anotherAddress, otherAddress, other2Address;
let registrationFee = ethers.parseEther("0.01");
let newFee = ethers.parseEther("0.02");
let rewardDistributionRate = 10n;

beforeEach(async function () {
  const DomainRegister = await ethers.getContractFactory("DomainRegister");
  [owner, anotherAddress, otherAddress, other2Address] =
    await ethers.getSigners();
  domainRegister = await upgrades.deployProxy(
    DomainRegister,
    [registrationFee, rewardDistributionRate],
    { initializer: "initialize" }
  );
});

describe("Registration", function () {
  it("Should register a domain successfully", async function () {
    // Perform the transaction and wait for the transaction to complete.
    const tx = await domainRegister.registerDomain(
      "example.com",
      anotherAddress.address,
      { value: registrationFee }
    );
    await tx.wait();
    await expect(tx)
      .to.emit(domainRegister, "DomainRegistered")
      .withArgs("example.com", anotherAddress.address);
    const isRegistered = await domainRegister.getDomainStorageForTesting(
      "example.com"
    );
    expect(isRegistered).to.be.true;
  });

  it("Should fail if the domain is already registered", async function () {
    await domainRegister.registerDomain(
      "example01.com",
      anotherAddress.address,
      { value: registrationFee }
    );
    await expect(
      domainRegister.registerDomain("example01.com", otherAddress.address, {
        value: registrationFee,
      })
    )
      .to.be.revertedWithCustomError(domainRegister, "DomainAlreadyRegistered")
      .withArgs("example01.com");
  });

  it("Should fail if the payment is insufficient", async function () {
    await expect(
      domainRegister.registerDomain("example02.com", anotherAddress.address, {
        value: ethers.parseEther("0.001"),
      })
    )
      .to.be.revertedWithCustomError(domainRegister, "InsufficientPayment")
      .withArgs(registrationFee);
  });
});

describe("Fee Management", function () {
  it("Should allow the owner to change the registration fee", async function () {
    await domainRegister.changeFee(newFee);
    const currentFee = await domainRegister.getFeeForTesting();
    expect(currentFee).to.equal(newFee);
  });

  it("Should prevent non-owners from changing the registration fee", async function () {
    await expect(
      domainRegister.connect(anotherAddress).changeFee(newFee)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
});

describe("Domain Queries", function () {
  it("Should retrieve a list of domains for a specific controller", async function () {
    await domainRegister.registerDomain(
      "example22.com",
      anotherAddress.address,
      { value: newFee }
    );
    await domainRegister.registerDomain(
      "example23.com",
      anotherAddress.address,
      { value: newFee }
    );
    const domains = await domainRegister.getControllerDomains(
      anotherAddress.address,
      0,
      10
    );
    expect(domains.includes("example22.com")).to.be.true;
    expect(domains.includes("example23.com")).to.be.true;
  });
});

describe("Metrics", function () {
  it("tracks the total number of registered domains", async function () {
    let totalDomains = await domainRegister.getTotalDomainsForTesting();
    expect(totalDomains).to.equal(0);
    await domainRegister
      .connect(owner)
      .registerDomain("example03.com", owner.address, { value: newFee });
    totalDomains = await domainRegister.getTotalDomainsForTesting();
    expect(totalDomains).to.equal(1);
    await domainRegister
      .connect(anotherAddress)
      .registerDomain("example04.com", anotherAddress.address, {
        value: newFee,
      });
    totalDomains = await domainRegister.getTotalDomainsForTesting();
    expect(totalDomains).to.equal(2);

    console.log("total number of registered domains is ", totalDomains);
  });

  it("should collect metrics for list of domains sorted by registration date", async function () {
    await domainRegister.registerDomain("first.com", anotherAddress.address, {
      value: newFee,
    });
    await new Promise((resolve) => setTimeout(resolve, 1000));
    await domainRegister.registerDomain("second.com", anotherAddress.address, {
      value: newFee,
    });

    const filter = domainRegister.filters.DomainRegistered();
    const events = await domainRegister.queryFilter(filter);
    const domainTimestamps = await Promise.all(
      events.map(async (event) => {
        const block = await ethers.provider.getBlock(event.blockNumber);
        return { domain: event.args.domain, timestamp: block.timestamp };
      })
    );
    domainTimestamps.sort((a, b) => a.timestamp - b.timestamp);
    console.log("Domains and their registration timestamps:");
    domainTimestamps.forEach((domainTimestamp) => {
      console.log(
        `${domainTimestamp.domain}: ${new Date(
          domainTimestamp.timestamp * 1000
        ).toISOString()}`
      );
    });
    expect(domainTimestamps.map((dt) => dt.timestamp)).to.satisfy(
      (timestamps) => {
        for (let i = 1; i < timestamps.length; i++) {
          if (timestamps[i] <= timestamps[i - 1]) {
            return false;
          }
        }
        return true;
      }
    );
  });

  it("should collect metrics for list of domains registered by a specific controller, sorted by registration date", async function () {
    await domainRegister.registerDomain(
      "controller1domain1.com",
      anotherAddress.address,
      { value: newFee }
    );
    await new Promise((resolve) => setTimeout(resolve, 1000));
    await domainRegister.registerDomain(
      "controller1domain2.com",
      anotherAddress.address,
      { value: newFee }
    );

    const filter = domainRegister.filters.DomainRegistered(
      null,
      anotherAddress.address
    );
    const events = await domainRegister.queryFilter(filter);
    const domainTimestamps = await Promise.all(
      events.map(async (event) => {
        const block = await ethers.provider.getBlock(event.blockNumber);
        return { domain: event.args.domain, timestamp: block.timestamp };
      })
    );
    domainTimestamps.sort((a, b) => a.timestamp - b.timestamp);
    console.log(
      `Domains registered by controller ${anotherAddress.address} and their registration timestamps:`
    );
    domainTimestamps.forEach((domainTimestamp) => {
      console.log(
        `${domainTimestamp.domain}: ${new Date(
          domainTimestamp.timestamp * 1000
        ).toISOString()}`
      );
    });
    expect(domainTimestamps.map((dt) => dt.timestamp)).to.satisfy(
      (timestamps) => {
        for (let i = 1; i < timestamps.length; i++) {
          if (timestamps[i] <= timestamps[i - 1]) {
            return false;
          }
        }
        return true;
      }
    );
  });
});

describe("Checking events", function () {
  it("emits a DomainRegistered event when a domain is registered", async function () {
    const domainName = "example.com";
    const tx = await domainRegister
      .connect(anotherAddress)
      .registerDomain(domainName, anotherAddress.address, { value: newFee });
    await expect(tx)
      .to.emit(domainRegister, "DomainRegistered")
      .withArgs(domainName, anotherAddress.address);
  });

  it("emits a FeeChanged event when the registration fee is changed", async function () {
    const newFee = ethers.parseEther("0.02");
    const tx = await domainRegister.connect(owner).changeFee(newFee);
    await expect(tx).to.emit(domainRegister, "FeeChanged").withArgs(newFee);
  });
  it("emits a RewardDistributed event when rewards are distributed up the domain hierarchy", async function () {
    const parentDomain = "example.com";
    const childDomain = "sub.example.com";
    await domainRegister.registerDomain(parentDomain, owner.address, {
      value: registrationFee,
    });
    const tx = await domainRegister.registerDomain(childDomain, owner.address, {
      value: registrationFee,
    });
    const rewardAmount = (registrationFee * rewardDistributionRate) / 100n;
    await expect(tx)
      .to.emit(domainRegister, "RewardDistributed")
      .withArgs(parentDomain, rewardAmount);
  });
});

describe("getAllParentDomains", function () {
  it("should correctly extract all parent domains for a subdomain", async function () {
    expect(
      await domainRegister.getAllParentDomains("example1.subdomain.example.com")
    ).to.deep.equal(["com", "example.com", "subdomain.example.com"]);
  });
  it("should correctly handle second-level domains", async function () {
    expect(
      await domainRegister.getAllParentDomains("example.com")
    ).to.deep.equal(["com"]);
  });
  it("should return an empty array for top-level domains", async function () {
    expect(await domainRegister.getAllParentDomains("com")).to.deep.equal([]);
  });
  it("should correctly extract all parent domains for a subdomain", async function () {
    expect(
      await domainRegister.getAllParentDomains(
        "new.example1.subdomain.example.com"
      )
    ).to.deep.equal([
      "com",
      "example.com",
      "subdomain.example.com",
      "example1.subdomain.example.com",
    ]);
  });
});
describe("collect rewards", function () {
  it("should correctly collect reward for all parent domains and owner", async function () {
    const initOwnerBalance = await ethers.provider.getBalance(owner.address);
    await domainRegister
      .connect(anotherAddress)
      .registerDomain("org", anotherAddress.address, {
        value: registrationFee,
      });
    expect(await ethers.provider.getBalance(owner.address)).to.equal(
      initOwnerBalance + registrationFee
    );
    const initOwnerBalance1 = await ethers.provider.getBalance(owner.address);
    await domainRegister
      .connect(otherAddress)
      .registerDomain("test.org", otherAddress.address, {
        value: registrationFee,
      });
    const feeForDomain = (registrationFee * rewardDistributionRate) / 100n;
    expect(await domainRegister.getRewardForDomain("org")).to.equal(
      feeForDomain
    );
    expect(await ethers.provider.getBalance(owner.address)).to.equal(
      initOwnerBalance1 + registrationFee - feeForDomain
    );
    await domainRegister
      .connect(other2Address)
      .registerDomain("new.test.org", other2Address.address, {
        value: registrationFee,
      });
    expect(await ethers.provider.getBalance(owner.address)).to.equal(
      initOwnerBalance1 +
        registrationFee -
        feeForDomain +
        registrationFee -
        feeForDomain -
        feeForDomain
    );
    expect(await domainRegister.getRewardForDomain("org")).to.equal(
      feeForDomain * 2n
    );
    expect(await domainRegister.getRewardForDomain("test.org")).to.equal(
      feeForDomain
    );
  });
});
