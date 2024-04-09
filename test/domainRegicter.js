import { expect } from "chai";
import pkg from 'hardhat';
const { ethers, upgrades } = pkg;

    let domainRegister;
    let owner, anotherAddress, otherAddress;
    let registrationFee = ethers.parseEther("0.01");
    let newFee = ethers.parseEther("0.02");

    before(async function () {
        const DomainRegister = await ethers.getContractFactory("DomainRegister");
        [owner, anotherAddress, otherAddress] = await ethers.getSigners();
        domainRegister = await upgrades.deployProxy(DomainRegister, [registrationFee], {initializer: 'initialize'});
    });

    describe("Registration", function () {
        it("Should register a domain successfully", async function () {
            await expect(domainRegister.registerDomain("example.com", anotherAddress.address, { value: registrationFee }))
                .to.emit(domainRegister, "DomainRegistered")
                .withArgs("example.com", anotherAddress.address);
            expect(await domainRegister.registeredDomains("example.com")).to.equal(true);
        });

        it("Should fail if the domain is already registered", async function () {
            await domainRegister.registerDomain("example01.com", anotherAddress.address, { value: registrationFee });
            await expect(domainRegister.registerDomain("example01.com", otherAddress.address, { value: registrationFee }))
                .to.be.revertedWithCustomError(domainRegister, "DomainAlreadyRegistered")
                .withArgs("example01.com");
        });

        it("Should fail if the payment is insufficient", async function () {
            await expect(domainRegister.registerDomain("example02.com", anotherAddress.address, { value: ethers.parseEther("0.001") }))
                .to.be.revertedWithCustomError(domainRegister, "InsufficientPayment")
                .withArgs(registrationFee);
        });
    });

    describe("Fee Management", function () {
        it("Should allow the owner to change the registration fee", async function () {
            await domainRegister.changeFee(newFee);
            expect(await domainRegister.fee()).to.equal(newFee);
        });

        it("Should prevent non-owners from changing the registration fee", async function () {
            await expect(domainRegister.connect(anotherAddress).changeFee(newFee))
                .to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    describe("Domain Queries", function () {
        it("Should retrieve a list of domains for a specific controller", async function () {
            await domainRegister.registerDomain("example22.com", anotherAddress.address, { value: newFee });
            await domainRegister.registerDomain("example23.com", anotherAddress.address, { value: newFee });
            const domains = await domainRegister.getControllerDomains(anotherAddress.address, 0, 10);
            expect(domains.includes("example22.com")).to.be.true;
            expect(domains.includes("example23.com")).to.be.true;
        });
    });

    describe("Metrics", function () {
        it("tracks the total number of registered domains", async function () {
        expect(await domainRegister.totalDomains()).to.equal(0);
        await domainRegister.connect(owner).registerDomain("example03.com", owner.address, { value: newFee });
        expect(await domainRegister.totalDomains()).to.equal(1);
        await domainRegister.connect(anotherAddress).registerDomain("example04.com", anotherAddress.address, { value: newFee });
        expect(await domainRegister.totalDomains()).to.equal(2);

        console.log("total number of registered domains is ", await domainRegister.totalDomains())
    });

        it("should collect metrics for list of domains sorted by registration date", async function() {
            await domainRegister.registerDomain("first.com", anotherAddress.address, { value: newFee });
            await new Promise(resolve => setTimeout(resolve, 1000));
            await domainRegister.registerDomain("second.com", anotherAddress.address, { value: newFee });

            const filter = domainRegister.filters.DomainRegistered();
            const events = await domainRegister.queryFilter(filter);
            const domainTimestamps = await Promise.all(events.map(async (event) => {
                const block = await ethers.provider.getBlock(event.blockNumber);
                return { domain: event.args.domain, timestamp: block.timestamp };
            }));
            domainTimestamps.sort((a, b) => a.timestamp - b.timestamp);
            console.log("Domains and their registration timestamps:");
            domainTimestamps.forEach((domainTimestamp) => {
                console.log(`${domainTimestamp.domain}: ${new Date(domainTimestamp.timestamp * 1000).toISOString()}`);
            });
            expect(domainTimestamps.map(dt => dt.timestamp)).to.satisfy((timestamps) => {
                for (let i = 1; i < timestamps.length; i++) {
                    if (timestamps[i] <= timestamps[i - 1]) {
                        return false;
                    }
                }
                return true;
            });
        });

        it("should collect metrics for list of domains registered by a specific controller, sorted by registration date", async function() {
            await domainRegister.registerDomain("controller1domain1.com", anotherAddress.address, { value: newFee });
            await new Promise(resolve => setTimeout(resolve, 1000));
            await domainRegister.registerDomain("controller1domain2.com", anotherAddress.address, { value: newFee });

            const filter = domainRegister.filters.DomainRegistered(null, anotherAddress.address);
            const events = await domainRegister.queryFilter(filter);
            const domainTimestamps = await Promise.all(events.map(async (event) => {
                const block = await ethers.provider.getBlock(event.blockNumber);
                return { domain: event.args.domain, timestamp: block.timestamp };
            }));
            domainTimestamps.sort((a, b) => a.timestamp - b.timestamp);
            console.log(`Domains registered by controller ${anotherAddress.address} and their registration timestamps:`);
            domainTimestamps.forEach((domainTimestamp) => {
                console.log(`${domainTimestamp.domain}: ${new Date(domainTimestamp.timestamp * 1000).toISOString()}`);
            });
            expect(domainTimestamps.map(dt => dt.timestamp)).to.satisfy((timestamps) => {
                for (let i = 1; i < timestamps.length; i++) {
                    if (timestamps[i] <= timestamps[i - 1]) {
                        return false;
                    }
                }
                return true;
            });
        });
    })

    describe("Checking events", function () {
        it("emits a DomainRegistered event when a domain is registered", async function() {
            const domainName = "example.com";
            const tx = await domainRegister.connect(anotherAddress).registerDomain(domainName, anotherAddress.address, { value: newFee });
            await expect(tx)
                .to.emit(domainRegister, "DomainRegistered")
                .withArgs(domainName, anotherAddress.address);
        });

        it("emits a FeeChanged event when the registration fee is changed", async function() {
            const newFee = ethers.parseEther("0.02");
            const tx = await domainRegister.connect(owner).changeFee(newFee);
            await expect(tx)
                .to.emit(domainRegister, "FeeChanged")
                .withArgs(newFee);
        });
    });
