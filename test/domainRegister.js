import { expect } from "chai";
import pkg from "hardhat";
const { ethers, upgrades } = pkg;
const zeroAddress = ethers.ZeroAddress;

describe("DomainRegister New version tests", function () {
  let domainRegister;
  let owner, user1, user2, user3, user4, user5, user6;

  let registrationFee = ethers.parseEther("0.01");
  let newFee = ethers.parseEther("0.02");
  let rewardForParentDomain = ethers.parseEther("0.001");
  const zeroAddress = ethers.ZeroAddress;

  beforeEach(async function () {
    [owner, user1, user2, user3, user4, user5, user6] =
      await ethers.getSigners();
    const DomainRegister = await ethers.getContractFactory(
      "DomainRegisterNewVersion"
    );
    domainRegister = await upgrades.deployProxy(
      DomainRegister,
      [registrationFee, rewardForParentDomain],
      { initializer: "initialize" }
    );
  });

  describe.only("Registration", function () {
    it("Should revert with DomainAlreadyRegistered if the domain is already registered", async function () {
      //
      await domainRegister.registerDomain("example.com", user1.address, {
        value: registrationFee,
      });

      // register the same domain
      await expect(
        domainRegister.registerDomain("example.com", user1.address, {
          value: registrationFee,
        })
      ).to.be.revertedWithCustomError(
        domainRegister,
        "DomainAlreadyRegistered"
      );
    });
    it("Should revert with IncorrectFeeValue if the payment is incorrect", async function () {
      // Attempt to register with less than the required fee
      await expect(
        domainRegister.registerDomain("example.com", user1.address, {
          value: ethers.parseEther("0.005"), // Incorrect fee (too low)
        })
      ).to.be.revertedWithCustomError(domainRegister, "IncorrectFeeValue");

      // Attempt to register with more than the required fee
      await expect(
        domainRegister.registerDomain("example.com", user1.address, {
          value: ethers.parseEther("0.015"), // Incorrect fee (too high)
        })
      ).to.be.revertedWithCustomError(domainRegister, "IncorrectFeeValue");
    });

    it("Should revert with InvalidControllerAddress if the controller address is zero", async function () {
      await expect(
        domainRegister.registerDomain("invalidDomain.com", ethers.ZeroAddress, {
          value: registrationFee,
        })
      ).to.be.revertedWithCustomError(
        domainRegister,
        "InvalidControllerAddress"
      );
    });

    it("Should register a domain successfully", async function () {
      const tx = await domainRegister.registerDomain(
        "example.com",
        user1.address,
        { value: registrationFee }
      );
      expect(tx)
        .to.emit(domainRegister, "DomainRegistered")
        .withArgs("example.com", user1.address);
    });

    it("Should correctly distribute reward to parent domain controllers", async function () {
      const contractBalanceInit = await ethers.provider.getBalance(
        owner.address
      );
      // Register a domain 1 level by user2
      await domainRegister.connect(user2).registerDomain("org", user2.address, {
        value: registrationFee,
      });
      const user2BalanceAfterPerchase = await ethers.provider.getBalance(
        user2.address
      );
      //owner`s balance has increased by registrationFee
      expect(await ethers.provider.getBalance(owner.address)).to.equal(
        contractBalanceInit + registrationFee
      );
      // Register a domain 2 level by user3
      await domainRegister
        .connect(user3)
        .registerDomain("test.org", user3.address, {
          value: registrationFee,
        });
      const user3BalanceAfterPerchase = await ethers.provider.getBalance(
        user3.address
      );
      //user2`s balance has increased by rewardForParentDomain
      expect(await ethers.provider.getBalance(user2.address)).to.equal(
        user2BalanceAfterPerchase + rewardForParentDomain
      );
      //owner`s balance has increased by registrationFee + (registrationFee - rewardForParentDomain)
      expect(await ethers.provider.getBalance(owner.address)).to.equal(
        contractBalanceInit +
          registrationFee +
          (registrationFee - rewardForParentDomain)
      );
      // Register a domain 3 level by user4
      await domainRegister
        .connect(user4)
        .registerDomain("example.test.org", user4.address, {
          value: registrationFee,
        });
      //user2`s balance has increased by 2*rewardForParentDomain
      expect(await ethers.provider.getBalance(user2.address)).to.equal(
        user2BalanceAfterPerchase +
          rewardForParentDomain +
          rewardForParentDomain
      );
      //user3`s balance has increased by rewardForParentDomain
      expect(await ethers.provider.getBalance(user3.address)).to.equal(
        user3BalanceAfterPerchase + rewardForParentDomain
      );
      //owner`s balance has increased by registrationFee + (registrationFee - rewardForParentDomain) + (registrationFee - 2*rewardForParentDomain)
      expect(await ethers.provider.getBalance(owner.address)).to.equal(
        contractBalanceInit +
          registrationFee +
          (registrationFee - rewardForParentDomain) +
          (registrationFee - rewardForParentDomain - rewardForParentDomain)
      );
    });

    it("Should owner receive fee", async function () {
      // get owner balance before
      const ownerBalanceBefore = await ethers.provider.getBalance(
        owner.address
      );
      console.log("ownerBalanceBefore", ownerBalanceBefore.toString());

      const user1BalanceBefore = await ethers.provider.getBalance(
        user1.address
      );
      console.log("user1BalanceBefore", user1BalanceBefore.toString());

      // register domain
      await domainRegister
        .connect(user1)
        .registerDomain("example.com", user1.address, {
          value: registrationFee,
        });

      // get owner balance after
      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);
      console.log("ownerBalanceAfter", ownerBalanceAfter.toString());

      // get user1 balance after
      const user1BalanceAfter = await ethers.provider.getBalance(user1.address);
      console.log("user1BalanceAfter", user1BalanceAfter.toString());

      // check owner balance
      expect(ownerBalanceAfter).to.be.equal(
        ownerBalanceBefore + registrationFee
      );
    });
  });
  describe.only("getAllParentDomains", function () {
    it("should correctly extract all parent domains for a subdomain", async function () {
      expect(
        await domainRegister.getAllParentDomains(
          "example1.subdomain.example.com"
        )
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
  describe.only("Metrics", function () {
    it("tracks the total number of registered domains", async function () {
      let totalDomains = await domainRegister.getTotalDomainsForTesting();
      expect(totalDomains).to.equal(0);
      await domainRegister
        .connect(owner)
        .registerDomain("example03.com", owner.address, {
          value: registrationFee,
        });
      totalDomains = await domainRegister.getTotalDomainsForTesting();
      expect(totalDomains).to.equal(1);
      await domainRegister
        .connect(user1)
        .registerDomain("example04.com", user1.address, {
          value: registrationFee,
        });
      totalDomains = await domainRegister.getTotalDomainsForTesting();
      expect(totalDomains).to.equal(2);

      console.log("total number of registered domains is ", totalDomains);
    });

    it("should collect metrics for list of domains sorted by registration date", async function () {
      await domainRegister.registerDomain("first.com", user1.address, {
        value: registrationFee,
      });
      await new Promise((resolve) => setTimeout(resolve, 1000));
      await domainRegister.registerDomain("second.com", user1.address, {
        value: registrationFee,
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
        user1.address,
        { value: registrationFee }
      );
      await new Promise((resolve) => setTimeout(resolve, 1000));
      await domainRegister.registerDomain(
        "controller1domain2.com",
        user1.address,
        { value: registrationFee }
      );

      const filter = domainRegister.filters.DomainRegistered(
        null,
        user1.address
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
        `Domains registered by controller ${user1.address} and their registration timestamps:`
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
  describe.only("Checking events", function () {
    it("emits a DomainRegistered event when a domain is registered", async function () {
      const domainName = "example.com";
      const tx = await domainRegister
        .connect(user1)
        .registerDomain(domainName, user1.address, { value: registrationFee });
      await expect(tx)
        .to.emit(domainRegister, "DomainRegistered")
        .withArgs(domainName, user1.address);
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
      const tx = await domainRegister.registerDomain(
        childDomain,
        owner.address,
        {
          value: registrationFee,
        }
      );
      const rewardAmount = rewardForParentDomain;
      await expect(tx)
        .to.emit(domainRegister, "RewardDistributed")
        .withArgs(parentDomain, rewardAmount);
    });
  });
  describe.only("Fee Management", function () {
    it("Should allow the owner to change the registration fee", async function () {
      await domainRegister.changeFee(newFee);
      const currentFee = await domainRegister.getFeeForTesting();
      expect(currentFee).to.equal(newFee);
    });

    it("Should prevent non-owners from changing the registration fee", async function () {
      await expect(
        domainRegister.connect(user2).changeFee(newFee)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });
  describe.only("Domain Queries", function () {
    it("Should retrieve a list of domains for a specific controller", async function () {
      await domainRegister.registerDomain("example22.com", user2.address, {
        value: registrationFee,
      });
      await domainRegister.registerDomain("example23.com", user2.address, {
        value: registrationFee,
      });
      const domains = await domainRegister.getControllerDomains(
        user2.address,
        0,
        10
      );
      expect(domains.includes("example22.com")).to.be.true;
      expect(domains.includes("example23.com")).to.be.true;
    });
  });
});
