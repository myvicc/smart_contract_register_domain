// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

error DomainAlreadyRegistered(string domain);
error FeeMustBeGreaterThanZero();
error FeeMustDifferFromCurrent();
error InsufficientPayment(uint256 requiredFee);
error InvalidControllerAddress();

contract DomainRegister is Initializable, OwnableUpgradeable {

    uint256 public fee;
    uint256 public totalDomains;
    uint256 public rewardDistributionRate;

    mapping(address => string[]) public controllerDomains;
    mapping(string => bool) public registeredDomains;
    mapping(string => uint256) public domainRewards;
    mapping(string => address) public domainController;

    event DomainRegistered(
        string domain,
        address indexed controller
    );
    event FeeChanged(uint256 newFee);
    event RewardDistributed(string domain, uint256 amount);

    /**
    * @dev Sets the contract owner and initializes the registration fee with a valid value.
    * @param _defaultFee The initial fee amount for domain registration, must be greater than zero.
    */
    function initialize(uint256 _defaultFee, uint256 _rewardDistributionRate) public initializer {
        __Ownable_init();
        if (_defaultFee <= 0) revert FeeMustBeGreaterThanZero();
        fee = _defaultFee;
        rewardDistributionRate = _rewardDistributionRate;
    }

    /**
    * @notice Distributes rewards up the domain hierarchy.
    * @dev This function calculates and distributes rewards to controllers of parent domains based on the reward distribution rate.
    * @param domain The domain name for which rewards are being distributed.
    * @param rewardAmount The total reward amount to distribute.
    * @return totalDistributed The total amount of rewards distributed.
    */
    function distributeRewards(string memory domain, uint256 rewardAmount) public returns (uint256 totalDistributed) {
        if (bytes(domain).length == 0 || rewardAmount == 0) {
            return 0;
        }

        string[] memory parentDomains = getAllParentDomains(domain);
        if (parentDomains.length == 0) {
            return 0;
        }
        totalDistributed = 0;
        uint256 currentReward = rewardAmount;
        for (uint256 i = 0; i < parentDomains.length; i++) {
            if (registeredDomains[parentDomains[i]]) {
                address controller = domainController[parentDomains[i]];
                if (controller != address(0)) {
                    domainRewards[parentDomains[i]] += currentReward;
                    emit RewardDistributed(parentDomains[i], currentReward);
                    totalDistributed += currentReward;
                }
            }
        }
        return totalDistributed;
    }

    /**
     * @notice Registers a new domain if it has not been already registered and distributes rewards.
     * @dev Emits a `DomainRegistered` event upon successful registration.
     *      Emits a `RewardDistributed` event when rewards are distributed.
     * @param domain The domain name to register, must not be already registered.
     * @param controller The wallet address that will control the domain, must be a valid address.
     * @custom:effects
     *      - Registers the domain to the controller.
     *      - Updates the total domain count.
     *      - Calculates and distributes the reward based on the current fee and the reward distribution rate.
     *      - Transfers the feeForOwner (after deducting the reward) to the owner.
     *      - Refunds any excess payment if the paid amount exceeds the fee.
     */
    function registerDomain(string calldata domain, address controller) external payable {
        if (registeredDomains[domain]) revert DomainAlreadyRegistered({domain: domain});
        if (msg.value < fee) revert InsufficientPayment({requiredFee: fee});
        if (controller == address(0)) revert InvalidControllerAddress();

        registeredDomains[domain] = true;
        domainController[domain] = controller;
        controllerDomains[controller].push(domain);
        totalDomains += 1;

        uint256 reward = (fee * rewardDistributionRate) / 100;
        uint256 totalReward = distributeRewards(domain, reward);

        emit DomainRegistered(domain, controller);

        uint256 feeForOwner = fee - totalReward;
        payable(owner()).transfer(feeForOwner);

        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }

    function getAllParentDomains(string memory domain) public pure returns (string[] memory) {
        uint256 dotCount = countOccurrences(domain, '.');

        string[] memory parentDomains = new string[](dotCount + 1);
        uint256 lastIndex = 0;
        uint256 nextIndex = 0;
        uint256 arrayIndex = dotCount;

        while (nextIndex < bytes(domain).length && arrayIndex > 0) {
            nextIndex = findNextDot(domain, lastIndex);
            parentDomains[arrayIndex - 1] = substring(domain, nextIndex + 1, bytes(domain).length);
            lastIndex = nextIndex + 1;
            arrayIndex--;
        }

        for (uint256 i = 0; i < parentDomains.length; i++) {
            if (bytes(parentDomains[i]).length == 0) {
                for (uint256 j = i; j < parentDomains.length - 1; j++) {
                    parentDomains[j] = parentDomains[j + 1];
                }
                assembly {
                    mstore(parentDomains, sub(mload(parentDomains), 1))
                }
            }
        }
        return parentDomains;
    }

    function findNextDot(string memory str, uint256 startIndex) private pure returns (uint256) {
        uint256 i = startIndex;
        while (i < bytes(str).length && bytes(str)[i] != bytes1('.')) {
            i++;
        }
        return i;
    }

    function substring(string memory str, uint256 startIndex, uint256 endIndex) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    function countOccurrences(string memory str, bytes1 needle) private pure returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < bytes(str).length; i++) {
            if (bytes(str)[i] == needle) {
                count++;
            }
        }
        return count;
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
}