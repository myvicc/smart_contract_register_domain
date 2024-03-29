import { expect } from "chai";
import pkg from 'hardhat';
import {BigNumber} from "@ethersproject/bignumber";
const { ethers } = pkg;

describe("DomainRegister", function () {
    let domainRegister;
    let owner, another_address, other_address;
    let registrationFee;

    beforeEach(async function () {
        [owner, another_address, other_address] = await ethers.getSigners();
        const DomainRegister = await ethers.getContractFactory("DomainRegister");
        registrationFee = ethers.parseEther("0.01")
        domainRegister = await DomainRegister.deploy(registrationFee);
    });

    it("tracks the total number of registered domains", async function () {
        expect(await domainRegister.totalDomains()).to.equal(0);
        await domainRegister.connect(owner).registerDomain("example.com", owner.address, { value: registrationFee });
        expect(await domainRegister.totalDomains()).to.equal(1);
        await domainRegister.connect(other_address).registerDomain("anotherdomain.com", other_address.address, { value: registrationFee });
        expect(await domainRegister.totalDomains()).to.equal(2);

        console.log("total number of registered domains is ", await domainRegister.totalDomains())
    });

    it("returns a list of domains sorted by registration time", async function () {
        await domainRegister.connect(owner).registerDomain("example.com", owner.address, { value: registrationFee });
        await domainRegister.connect(other_address).registerDomain("example1.com", other_address.address, { value: registrationFee });
        await domainRegister.connect(other_address).registerDomain("example2.com", other_address.address, { value: registrationFee });
        await domainRegister.connect(other_address).registerDomain("example3.com", other_address.address, { value: registrationFee });
        await domainRegister.connect(other_address).registerDomain("example4.com", other_address.address, { value: registrationFee });

        const filter = domainRegister.filters.DomainRegistered();
        const events = await domainRegister.queryFilter(filter);

        const sortedEvents = events.sort((a, b) => {
               return a.args.registrationTime < b.args.registrationTime ? -1 : a.args.registrationTime > b.args.registrationTime ? 1 : 0;
             });
        const domainsWithRegistrationTimes = sortedEvents.map(event => {
            const date = new Date(parseInt(event.args.registrationTime) * 1000).toISOString();
            return `${event.args.domain} - ${date}`;
        });
        console.log("List of domains with registration dates:", domainsWithRegistrationTimes);
    });

    it("should allow a user to register a domain", async function () {
        await domainRegister.connect(other_address).registerDomain("example.com", other_address.address, { value: registrationFee });

        const domainInfo = await domainRegister.domains("example.com");
        await expect(domainInfo.controller).to.equal(other_address.address);
        await expect(domainInfo.registrationTime).to.be.gt(0);
    });

    it("returns a list of domains for a specific controller, sorted by registration time", async function () {
        await domainRegister.connect(owner).registerDomain("example.com", owner.address, { value: registrationFee });
        await domainRegister.connect(another_address).registerDomain("example1.com", another_address.address, { value: registrationFee });
        await domainRegister.connect(other_address).registerDomain("example2.com", other_address.address, { value: registrationFee });
        await domainRegister.connect(another_address).registerDomain("example3.com", another_address.address, { value: registrationFee });
        await domainRegister.connect(other_address).registerDomain("example4.com", other_address.address, { value: registrationFee });

        const controllerAddress = another_address.address;
        const filter = domainRegister.filters.DomainRegistered(null, controllerAddress, null);
        const events = await domainRegister.queryFilter(filter);
        const sortedEvents = events.sort((a, b) => {
            return a.args.registrationTime < b.args.registrationTime ? -1 : a.args.registrationTime > b.args.registrationTime ? 1 : 0;
        });
        const domainNames = sortedEvents.map(event => event.args.domain);
        console.log(domainNames);
    });

    it("should emit an event upon registration", async function () {

        const startBlock = await ethers.provider.getBlockNumber();
        const tx = await domainRegister.connect(other_address).registerDomain("example.com", other_address.address, { value: registrationFee });
        const receipt = await tx.wait();
        const filter = domainRegister.filters.DomainRegistered(null, null);
        const logs = await domainRegister.queryFilter(filter, startBlock);

        console.log("Logs found: ", logs.length);
        logs.forEach((log, index) => {
            console.log(`Log ${index + 1}: domain - ${log.args.domain}, controller - ${log.args.controller}, registrationTime - ${log.args.registrationTime}`);
        });

        expect(logs.length).to.be.at.least(1, "No DomainRegistered event found");
        const event = logs[0];
        const registrationTime = event.args.registrationTime;
        const registrationTimeNumber = BigNumber.isBigNumber(registrationTime)
            ? registrationTime.toNumber()
            : registrationTime;
        expect(event.args.domain).to.equal("example.com");
        expect(event.args.controller).to.equal(other_address.address);

        const currentBlockTime = await ethers.provider.getBlock('latest').then(block => block.timestamp);
        expect(registrationTimeNumber).to.be.at.least(1);
        expect(registrationTimeNumber).to.be.at.most(currentBlockTime);
    });

    it("should change fee by owner", async function () {
        const newFee = ethers.parseEther("0.02");
        await domainRegister.connect(owner).changeFee(newFee);
        expect(await domainRegister.fee()).to.equal(newFee);
    });

    it("should not allow non-owner to change fee", async function () {
        const newFee = ethers.parseEther("0.02");
        await expect(domainRegister.connect(other_address).changeFee(newFee))
            .to.be.revertedWith("This action only for owner");
    });

    it("should return domains registered by a controller", async function () {
        await domainRegister.connect(other_address).registerDomain("example1.com", other_address.address, { value: registrationFee });
        await domainRegister.connect(other_address).registerDomain("example2.com", other_address.address, { value: registrationFee });

        const registeredDomains = await domainRegister.getControllerDomains(other_address.address);
        expect(registeredDomains).to.deep.equal(["example1.com", "example2.com"]);
    });
});
