// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DomainRegisterNewVersion is Initializable, OwnableUpgradeable {
    // _____________________ Constants  _________________________

    bytes32 private constant DOMAIN_STORAGE_LOCATION =
        0xe883eb4257b84497a2d75d72086944e71c11e3651be7aa24d21030462e3f0600;

    // _____________________ Structs  _________________________

    struct DomainStorage {
        uint256 fee;
        uint totalDomains;
        uint256 rewardForParentDomain;
        mapping(address => string[]) controllerDomains;
        mapping(string => bool) registeredDomains;
        mapping(string => uint256) domainRewards;
        mapping(string => address) domainController;
    }

    // _____________________ Events  _________________________

    event DomainRegistered(string domain, address indexed controller);
    event FeeChanged(uint256 newFee);
    event RewardDistributed(string domain, uint256 amount);

    // _____________________ Errors  _________________________

    error DomainAlreadyRegistered(string domain);
    error FeeMustBeGreaterThanZero();
    error FeeMustDifferFromCurrent();
    error IncorrectFeeValue(uint256 requiredFee);
    error InvalidControllerAddress();
    error InsufficientBalanceForTransfer();
    error TransferFailed();

    // _____________________ Initializer  _________________________
    /**
     * @dev Sets the contract owner and initializes the registration fee with a valid value.
     * @param _defaultFee The initial fee amount for domain registration, must be greater than zero.
     */
    function initialize(
        uint256 _defaultFee,
        uint256 _rewardForParentDomain
    ) public initializer {
        __Ownable_init();
        _getDomainStorage().fee = _defaultFee;
        _getDomainStorage().rewardForParentDomain = _rewardForParentDomain;
    }

    // _____________________ External functions  _________________________
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
        if (msg.value != _getDomainStorage().fee)
            revert IncorrectFeeValue({requiredFee: _getDomainStorage().fee});
        if (controller == address(0)) revert InvalidControllerAddress();

        _getDomainStorage().registeredDomains[domain] = true;
        _getDomainStorage().domainController[domain] = controller;
        _getDomainStorage().controllerDomains[controller].push(domain);
        _getDomainStorage().totalDomains += 1;

        //distribute and transfer reward to owner of parent domain
        uint256 totalRewardToParentDomain = distributeRewards(
            domain,
            _getDomainStorage().rewardForParentDomain
        );

        uint256 feeForOwner = _getDomainStorage().fee -
            totalRewardToParentDomain;
        //transfer remains of fee to owner
        _safeTransfer(owner(), feeForOwner);

        emit DomainRegistered(domain, controller);
    }

    /**
     * @notice Changes the registration fee for new domains.
     * @dev Validates the new fee before changing to prevent unnecessary changes.
     * @param newFee The new registration fee amount, must be greater than zero and different from the current fee
     */
    function changeFee(uint256 newFee) external onlyOwner {
        if (newFee <= 0) revert FeeMustBeGreaterThanZero();
        if (newFee == _getDomainStorage().fee)
            revert FeeMustDifferFromCurrent();
        _getDomainStorage().fee = newFee;
        emit FeeChanged(newFee);
    }

    // _____________________ External view functions _____________________
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
        string[] memory registerDomains = _getDomainStorage().controllerDomains[
            controller
        ];
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

    function getDomainStorageForTesting(
        string calldata domain
    ) external view returns (bool) {
        return _getDomainStorage().registeredDomains[domain];
    }
    function getFeeForTesting() external view returns (uint256) {
        return _getDomainStorage().fee;
    }
    function getTotalDomainsForTesting() external view returns (uint256) {
        return _getDomainStorage().totalDomains;
    }
    function getRewardForDomain(
        string memory domain
    ) external view returns (uint256) {
        return _getDomainStorage().domainRewards[domain];
    }

    // _____________________ Public functions ____________________________
    /**
     * @notice Distributes rewards up the domain hierarchy.
     * @dev This function calculates and distributes rewards to controllers of
     *      parent domains based on the reward distribution rate.
     * @param domain The domain name for which rewards are being distributed.
     * @param rewardAmount The total reward amount to distribute.
     * @return totalDistributedToParentDomain The total amount of rewards distributed to parent domain controllers.
     */
    function distributeRewards(
        string memory domain,
        uint256 rewardAmount
    ) public returns (uint256 totalDistributedToParentDomain) {
        if (bytes(domain).length == 0 || rewardAmount == 0) {
            return 0;
        }

        string[] memory parentDomains = getAllParentDomains(domain);
        if (parentDomains.length == 0) {
            return 0;
        }
        totalDistributedToParentDomain = 0;
        uint256 currentReward = rewardAmount;
        for (uint256 i = 0; i < parentDomains.length; i++) {
            if (_getDomainStorage().registeredDomains[parentDomains[i]]) {
                address controller = _getDomainStorage().domainController[
                    parentDomains[i]
                ];
                if (controller != address(0)) {
                    _getDomainStorage().domainRewards[
                        parentDomains[i]
                    ] += currentReward;
                    //transfer reward to owner of parent domain
                    _safeTransfer(controller, currentReward);
                    emit RewardDistributed(parentDomains[i], currentReward);
                    totalDistributedToParentDomain += currentReward;
                }
            }
        }
        return totalDistributedToParentDomain;
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

    // _____________________ Private functions ___________________________

    function _getDomainStorage()
        private
        pure
        returns (DomainStorage storage $)
    {
        assembly {
            $.slot := DOMAIN_STORAGE_LOCATION
        }
    }

    function _safeTransfer(address to, uint256 amount) private {
        if (address(this).balance < amount) {
            revert InsufficientBalanceForTransfer();
        }

        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
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
}
