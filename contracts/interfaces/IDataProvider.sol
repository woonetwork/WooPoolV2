// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

interface IVaultInfo {
    function costSharePrice(address user) external view returns (uint256 sharePrice);

    function getPricePerFullShare() external view returns (uint256 sharePrice);
}

interface ISuperChargerVaultInfo {
    function requestedWithdrawAmount(address user) external view returns (uint256 amount);
}

interface IWithdrawManagerInfo {
    function withdrawAmount(address user) external view returns (uint256 amount);
}

interface IMasterChefWooInfo {
    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);

    function pendingXWoo(uint256 pid, address user)
        external
        view
        returns (uint256 pendingXWooAmount, uint256 pendingWooAmount);

    function pendingReward(uint256 pid, address user)
        external
        view
        returns (uint256 pendingRewardAmount, uint256 pendingRewarderTokens);
}

interface IWooSimpleRewarder {
    function pendingTokens(address user) external view returns (uint256 tokens);
}

interface IDataProvider {
    /* ----- Struct ----- */

    struct VaultInfos {
        uint256[] balancesOf;
        uint256[] sharePrices;
        uint256[] costSharePrices;
    }

    struct TokenInfos {
        uint256 nativeBalance;
        uint256[] balancesOf;
    }

    struct MasterChefWooInfos {
        uint256[] amounts;
        uint256[] rewardDebts;
        uint256[] pendingXWooAmounts;
        uint256[] pendingWooAmounts;
        uint256[] pendingTokens;
    }

    struct SuperChargerRelatedInfos {
        uint256[] requestedWithdrawAmounts;
        uint256[] withdrawAmounts;
    }

    /* ----- View Functions ----- */

    function infos(
        address user,
        address masterChefWoo,
        address[] memory wooSimpleRewarders,
        address[] memory vaults,
        address[] memory tokens,
        address[] memory superChargerVaults,
        address[] memory withdrawManagers,
        uint256[] memory pids
    )
        external
        view
        returns (
            VaultInfos memory vaultInfos,
            TokenInfos memory tokenInfos,
            MasterChefWooInfos memory masterChefWooInfos,
            SuperChargerRelatedInfos memory superChargerRelatedInfos
        );

    function balancesOf(address user, address[] memory tokens) external view returns (uint256[] memory results);

    function sharePrices(address[] memory vaults) external view returns (uint256[] memory results);

    function costSharePrices(address user, address[] memory vaults) external view returns (uint256[] memory results);

    function userInfos(
        address user,
        address masterChefWoo,
        uint256[] memory pids
    ) external view returns (uint256[] memory amounts, uint256[] memory rewardDebts);

    function pendingXWoos(
        address user,
        address masterChefWoo,
        uint256[] memory pids
    ) external view returns (uint256[] memory pendingXWooAmounts, uint256[] memory pendingWooAmounts);

    function pendingTokens(address user, address[] memory wooSimpleRewarders)
        external
        view
        returns (uint256[] memory results);

    function requestedWithdrawAmounts(address user, address[] memory superChargerVaults)
        external
        view
        returns (uint256[] memory results);

    function withdrawAmounts(address user, address[] memory withdrawManagers)
        external
        view
        returns (uint256[] memory results);
}
