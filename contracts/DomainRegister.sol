// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

error DomainAlreadyRegistered(string domain);
error FeeMustBeGreaterThanZero();
error FeeMustDifferFromCurrent();
error InsufficientPayment(uint256 requiredFee);
error InvalidControllerAddress();
error NotTopLevelDomain(string domain);
contract DomainRegister is Initializable, OwnableUpgradeable {
    struct DomainStorage {
        uint256 fee;
        uint totalDomains;
        mapping(address => string[]) controllerDomains;
        mapping(string => bool) registeredDomains;
    }

    bytes32 private constant DomainStorageLocation = 0xe883eb4257b84497a2d75d72086944e71c11e3651be7aa24d21030462e3f0600;
    function _getDomainStorage() private pure returns (DomainStorage storage $) {
    assembly {
    $.slot := DomainStorageLocation
     }
    }

    event DomainRegistered(
        string domain,
        address indexed controller
    );
    event FeeChanged(uint256 newFee);

    /**
    * @dev Sets the contract owner and initializes the registration fee with a valid value.
    * @param _defaultFee The initial fee amount for domain registration, must be greater than zero.
    */
    function initialize(uint256 _defaultFee) public initializer {
        __Ownable_init();
        if (_defaultFee <= 0) revert FeeMustBeGreaterThanZero();
        _getDomainStorage().fee = _defaultFee;
    }

    /**
    * @notice Registers a new top-level domain with a single dot.
    * @dev Emits a `DomainRegistered` event upon successful registration
    * @param domain The domain name to register, must be a top-level domain.
    * @param controller The wallet address that will control the domain.
    */
    function registerDomain(string calldata domain, address controller) external payable {
        if (_getDomainStorage().registeredDomains[domain]) revert DomainAlreadyRegistered({domain: domain});
        if (msg.value < _getDomainStorage().fee) revert InsufficientPayment({requiredFee: _getDomainStorage().fee});
        if (controller == address(0)) revert InvalidControllerAddress();
        if (countDots(domain) != 1) revert NotTopLevelDomain({domain: domain});

        _getDomainStorage().registeredDomains[domain] = true;
        _getDomainStorage().controllerDomains[controller].push(domain);
        _getDomainStorage().totalDomains += 1;

        emit DomainRegistered(domain, controller);
        _safeTransfer(owner(), _getDomainStorage().fee);

        if (msg.value > _getDomainStorage().fee) {
            _safeTransfer(msg.sender, msg.value - _getDomainStorage().fee);
        }
    }
    function _safeTransfer(address to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
    * @notice Changes the registration fee for new domains.
    * @dev Validates the new fee before changing to prevent unnecessary changes.
    * @param newFee The new registration fee amount, must be greater than zero and different from the current fee
    */
    function changeFee(uint256 newFee) external onlyOwner {
        if (newFee <= 0) revert FeeMustBeGreaterThanZero();
        if (newFee == _getDomainStorage().fee) revert FeeMustDifferFromCurrent();
        _getDomainStorage().fee = newFee;
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
        string[] memory registerDomains = _getDomainStorage().controllerDomains[controller];
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

    function getDomainStorageForTesting(string calldata domain) external view returns (bool) {
        return _getDomainStorage().registeredDomains[domain];
    }
    function getFeeForTesting() external view returns (uint256) {
        return _getDomainStorage().fee;
    }
    function getTotalDomainsForTesting() external view returns (uint256) {
        return _getDomainStorage().totalDomains;
    }
}