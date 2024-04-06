// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

error DomainAlreadyRegistered(string domain);
error FeeMustBeGreaterThanZero();
error FeeMustDifferFromCurrent();
error InsufficientPayment(uint256 requiredFee);
error InvalidControllerAddress();
error NotTopLevelDomain(string domain);
error OnlyOwner();

contract DomainRegister {
    uint256 public fee;
    address public owner;
    uint public totalDomains;
    mapping(address => string[]) public controllerDomains;
    mapping(string => bool) public registeredDomains;

    event DomainRegistered(
        string domain,
        address indexed controller
    );
    event FeeChanged(uint256 newFee);

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    /**
    * @dev Sets the contract owner and initializes the registration fee with a valid value.
    * @param defaultFee The initial fee amount for domain registration, must be greater than zero.
    */
    constructor(uint256 defaultFee) payable {
        if (defaultFee <= 0) revert InsufficientPayment({requiredFee: 1});
        owner = msg.sender;
        fee = defaultFee;
    }

    /**
    * @notice Registers a new top-level domain with a single dot.
    * @dev Emits a `DomainRegistered` event upon successful registration
    * @param domain The domain name to register, must be a top-level domain.
    * @param controller The wallet address that will control the domain.
    */
    function registerDomain(string calldata domain, address controller) external payable {
        if (registeredDomains[domain]) revert DomainAlreadyRegistered({domain: domain});
        if (msg.value < fee) revert InsufficientPayment({requiredFee: fee});
        if (controller == address(0)) revert InvalidControllerAddress();
        if (countDots(domain) != 1) revert NotTopLevelDomain({domain: domain});

        registeredDomains[domain] = true;
        controllerDomains[controller].push(domain);
        totalDomains += 1;

        emit DomainRegistered(domain, controller);

        payable(owner).transfer(fee);

        if (msg.value > fee) {
           payable(msg.sender).transfer(msg.value - fee);
        }
    }

    /**
    * @notice Changes the registration fee for new domains.
    * @dev Validates the new fee before changing to prevent unnecessary changes.
    * @param newFee The new registration fee amount, must be greater than zero and different from the current fee
    */
    function changeFee(uint256 newFee) external onlyOwner {
        if (newFee <= 0) revert FeeMustBeGreaterThanZero();
        if (newFee == fee) revert FeeMustDifferFromCurrent();
        fee = newFee;
        emit FeeChanged(newFee);
    }

    /**
    * @notice Retrieves a list of domains registered by the specified controller with pagination.
    * @param controller The Ethereum address of the controller.
    * @param offset The index of the first domain to return.
    * @param limit The maximum number of domains to return.
    * @return domains A subset of domain names associated with the controller's address.
    */
    function getControllerDomains(address controller, uint256 offset, uint256 limit) external view returns (string[] memory) {
        string[] memory registerDomains = controllerDomains[controller];
        uint256 registerCount = registerDomains.length;

        if (offset >= registerCount) {
            return new string[](0) ;
        }

        uint256 resultSize = (registerCount - offset > limit) ? limit : registerCount - offset;
        string[] memory domains = new string[](resultSize);

        for (uint256 i = 0; i < resultSize; ++i) {
            domains[i] = registerDomains[offset + i];
        }
        return domains;
    }

    /**
    * @notice Counts the dots in the provided string to verify top-level domain format.
    * @dev Used to verify that a domain is a top-level domain with a single dot.
    * @param str The domain name as a string to verify.
    * @return dotCount The total number of dots found in the string.
    */
    function countDots(string memory str) private pure returns (uint) {
        bytes memory strBytes = bytes(str);
        uint dotCount = 0;
        for(uint i = 0; i < strBytes.length; ++i) {
            if (strBytes[i] == '.') {
                dotCount++;
            }
        }
        return dotCount;
    }
}