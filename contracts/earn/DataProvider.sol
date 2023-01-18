// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IDataProvider.sol";

contract DataProvider is IDataProvider {
    /* ----- View Functions ----- */

    function infos(
        address user,
        address masterChefWoo,
        address[] memory vaults,
        address[] memory tokens,
        address[] memory superChargerVaults,
        address[] memory withdrawManagers,
        uint256[] memory pids
    )
        public
        view
        override
        returns (
            VaultInfos memory vaultInfos,
            TokenInfos memory tokenInfos,
            MasterChefWooInfos memory masterChefWooInfos,
            SuperChargerRelatedInfos memory superChargerRelatedInfos
        )
    {
        vaultInfos.balancesOf = balancesOf(user, vaults);
        vaultInfos.sharePrices = sharePrices(vaults);
        vaultInfos.costSharePrices = costSharePrices(user, vaults);

        tokenInfos.nativeBalance = user.balance;
        tokenInfos.balancesOf = balancesOf(user, tokens);

        (masterChefWooInfos.amounts, masterChefWooInfos.rewardDebts) = userInfos(user, masterChefWoo, pids);
        (masterChefWooInfos.pendingXWooAmounts, masterChefWooInfos.pendingWooAmounts) = pendingXWoos(
            user,
            masterChefWoo,
            pids
        );

        superChargerRelatedInfos.requestedWithdrawAmounts = requestedWithdrawAmounts(user, superChargerVaults);
        superChargerRelatedInfos.withdrawAmounts = withdrawAmounts(user, withdrawManagers);
    }

    function balancesOf(address user, address[] memory tokens) public view override returns (uint256[] memory results) {
        uint256 length = tokens.length;
        results = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            results[i] = IERC20(tokens[i]).balanceOf(user);
        }
    }

    function sharePrices(address[] memory vaults) public view override returns (uint256[] memory results) {
        uint256 length = vaults.length;
        results = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            results[i] = IVaultInfo(vaults[i]).getPricePerFullShare();
        }
    }

    function costSharePrices(address user, address[] memory vaults)
        public
        view
        override
        returns (uint256[] memory results)
    {
        uint256 length = vaults.length;
        results = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            results[i] = IVaultInfo(vaults[i]).costSharePrice(user);
        }
    }

    function userInfos(
        address user,
        address masterChefWoo,
        uint256[] memory pids
    ) public view override returns (uint256[] memory amounts, uint256[] memory rewardDebts) {
        uint256 length = pids.length;
        amounts = new uint256[](length);
        rewardDebts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            (amounts[i], rewardDebts[i]) = IMasterChefWooInfo(masterChefWoo).userInfo(pids[i], user);
        }
    }

    function pendingXWoos(
        address user,
        address masterChefWoo,
        uint256[] memory pids
    ) public view override returns (uint256[] memory pendingXWooAmounts, uint256[] memory pendingWooAmounts) {
        uint256 length = pids.length;
        pendingXWooAmounts = new uint256[](length);
        pendingWooAmounts = new uint256[](length);
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        if (chainId == 10) {
            for (uint256 i = 0; i < length; i++) {
                (pendingWooAmounts[i], ) = IMasterChefWooInfo(masterChefWoo).pendingReward(pids[i], user);
                pendingXWooAmounts[i] = pendingWooAmounts[i];
            }
        } else {
            for (uint256 i = 0; i < length; i++) {
                (pendingXWooAmounts[i], pendingWooAmounts[i]) = IMasterChefWooInfo(masterChefWoo).pendingXWoo(
                    pids[i],
                    user
                );
            }
        }
    }

    function requestedWithdrawAmounts(address user, address[] memory superChargerVaults)
        public
        view
        override
        returns (uint256[] memory results)
    {
        uint256 length = superChargerVaults.length;
        results = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            results[i] = ISuperChargerVaultInfo(superChargerVaults[i]).requestedWithdrawAmount(user);
        }
    }

    function withdrawAmounts(address user, address[] memory withdrawManagers)
        public
        view
        override
        returns (uint256[] memory results)
    {
        uint256 length = withdrawManagers.length;
        results = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            results[i] = IWithdrawManagerInfo(withdrawManagers[i]).withdrawAmount(user);
        }
    }
}
