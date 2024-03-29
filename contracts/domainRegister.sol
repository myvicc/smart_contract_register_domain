// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract DomainRegister {
    struct DomainInfo {
        address controller;
        uint256 registrationTime;
    }
    uint256 public fee;
    address public owner;
    uint public totalDomains;
    mapping(string => DomainInfo) public domains;
    mapping(address => string[]) public controllerDomains;

    event DomainRegistered(
        string domain,
        address indexed controller,
        uint256 indexed registrationTime
    );
    event FeeChanged(uint256 newFee);

    modifier onlyOwner() {
        require(msg.sender == owner, "This action only for owner");
        _;
    }

    constructor(uint256 defaultFee) payable {
        owner = msg.sender;
        fee = defaultFee;
    }

    /// @notice Registers a domain with the specified name and controller
    /// @dev Emits a `DomainRegistered` event upon successful registration
    /// @param domain The name of the domain to be registered
    /// @param controller The address of the domain's controller
    function registerDomain(string calldata domain, address controller) external payable {
        require(domains[domain].controller == address(0), "Domain has already been registered");
        require(msg.value >= fee, "Insufficient payment");
        require(controller != address(0), "Controller address must be proper address");
        require(countDots(domain) == 1, "Domain must be a top-level domain with a single dot");

        domains[domain] = DomainInfo({
            controller: controller,
            registrationTime: block.timestamp
        });
        controllerDomains[controller].push(domain);
        totalDomains += 1;

        emit DomainRegistered(domain, controller, block.timestamp);

        payable(owner).transfer(fee);

        if (msg.value > fee) {
           payable(msg.sender).transfer(msg.value - fee);
        }
    }

    /// @notice Changes the registration fee for domains
    /// @dev Emits a `FeeChanged` event upon changing the fee
    /// @param newFee The new registration fee amount
    function changeFee(uint256 newFee) external onlyOwner {
        fee = newFee;
        emit FeeChanged(newFee);
    }

    /// @notice Returns a list of domains registered by the specified controller
    /// @param controller The controller's address for which to retrieve the domain list
    /// @return An array of string identifiers of domains
    function getControllerDomains(address controller) external view returns (string[] memory) {
        return controllerDomains[controller];
    }

    /// @notice Counts the number of dots in a string
    /// @dev Used to verify that a domain is a top-level domain with a single dot
    /// @param str The string to be checked
    /// @return The number of dots in the string
    function countDots(string memory str) private pure returns (uint) {
        bytes memory strBytes = bytes(str);
        uint dotCount = 0;
        for(uint i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == '.') {
                dotCount++;
            }
        }
        return dotCount;
    }
}