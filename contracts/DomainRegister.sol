// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

error DomainAlreadyRegistered(string domain);
error FeeMustBeGreaterThanZero();
error FeeMustDifferFromCurrent();
error InsufficientPayment(uint256 requiredFee);
error InvalidControllerAddress();
error TransferFailed();

contract DomainRegister is Initializable, OwnableUpgradeable {
    struct DomainStorage {
        uint256 fee;
        uint totalDomains;
        uint256 rewardDistributionRate;

        mapping(address => string[]) controllerDomains;
        mapping(string => bool) registeredDomains;
        mapping(string => uint256) domainRewards;
        mapping(string => address) domainController;
    }

    bytes32 private constant DomainStorageLocation = 0xe883eb4257b84497a2d75d72086944e71c11e3651be7aa24d21030462e3f0600;
    function _getDomainStorage() private pure returns (DomainStorage storage $) {
        assembly {
            $.slot := DomainStorageLocation
        }
    }

    event DomainRegistered(string domain, address indexed controller);
    event FeeChanged(uint256 newFee);
    event RewardDistributed(string domain, uint256 amount);

    /**
     * @dev Sets the contract owner and initializes the registration fee with a valid value.
     * @param _defaultFee The initial fee amount for domain registration, must be greater than zero.
     */
    function initialize(
        uint256 _defaultFee,
        uint256 _rewardDistributionRate
    ) public initializer {
        __Ownable_init();
        if (_defaultFee <= 0) revert FeeMustBeGreaterThanZero();
        _getDomainStorage().fee = _defaultFee;
        _getDomainStorage().rewardDistributionRate = _rewardDistributionRate;
    }

    /**
     * @notice Distributes rewards up the domain hierarchy.
     * @dev This function calculates and distributes rewards to controllers of
     *      parent domains based on the reward distribution rate.
     * @param domain The domain name for which rewards are being distributed.
     * @param rewardAmount The total reward amount to distribute.
     * @return totalDistributed The total amount of rewards distributed.
     */
    function distributeRewards(
        string memory domain,
        uint256 rewardAmount
    ) public returns (uint256 totalDistributed) {
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
            if (_getDomainStorage().registeredDomains[parentDomains[i]]) {
                address controller = _getDomainStorage().domainController[parentDomains[i]];
                if (controller != address(0)) {
                    _getDomainStorage().domainRewards[parentDomains[i]] += currentReward;
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
    function registerDomain(
        string calldata domain,
        address controller
    ) external payable {
        if (_getDomainStorage().registeredDomains[domain])
            revert DomainAlreadyRegistered({domain: domain});
        if (msg.value < _getDomainStorage().fee) revert InsufficientPayment({requiredFee: _getDomainStorage().fee});
        if (controller == address(0)) revert InvalidControllerAddress();

        _getDomainStorage().registeredDomains[domain] = true;
        _getDomainStorage().domainController[domain] = controller;
        _getDomainStorage().controllerDomains[controller].push(domain);
        _getDomainStorage().totalDomains += 1;

        uint256 reward = (_getDomainStorage().fee * _getDomainStorage().rewardDistributionRate) / 100;
        uint256 totalReward = distributeRewards(domain, reward);

        emit DomainRegistered(domain, controller);

        uint256 feeForOwner = _getDomainStorage().fee - totalReward;

        _safeTransfer(owner(), feeForOwner);
        if (msg.value > _getDomainStorage().fee) {
            _safeTransfer(msg.sender, msg.value - _getDomainStorage().fee);
        }
    }

    function _safeTransfer(address to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    function getAllParentDomains(
        string memory domain
    ) public pure returns (string[] memory) {
        uint256 dotCount = countOccurrences(domain, ".");

        string[] memory parentDomains = new string[](dotCount + 1);
        uint256 lastIndex = 0;
        uint256 nextIndex = 0;
        uint256 arrayIndex = dotCount;

        while (nextIndex < bytes(domain).length && arrayIndex > 0) {
            nextIndex = findNextDot(domain, lastIndex);
            parentDomains[arrayIndex - 1] = substring(
                domain,
                nextIndex + 1,
                bytes(domain).length
            );
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

    function findNextDot(
        string memory str,
        uint256 startIndex
    ) private pure returns (uint256) {
        uint256 i = startIndex;
        while (i < bytes(str).length && bytes(str)[i] != bytes1(".")) {
            i++;
        }
        return i;
    }

    function substring(
        string memory str,
        uint256 startIndex,
        uint256 endIndex
    ) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    function countOccurrences(
        string memory str,
        bytes1 needle
    ) private pure returns (uint256) {
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
    function getControllerDomains(
        address controller,
        uint256 offset,
        uint256 limit
    ) external view returns (string[] memory) {
        string[] memory registerDomains = _getDomainStorage().controllerDomains[controller];
        uint256 registerCount = registerDomains.length;

        if (offset >= registerCount) {
            return new string[](0);
        }

        uint256 resultSize = (registerCount - offset > limit)
            ? limit
            : registerCount - offset;
        string[] memory domains = new string[](resultSize);

        for (uint256 i = 0; i < resultSize; ++i) {
            domains[i] = registerDomains[offset + i];
        }
        return domains;
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
    function getRewardForDomain(string memory domain) external view returns (uint256) {
        return _getDomainStorage().domainRewards[domain];
    }
}
