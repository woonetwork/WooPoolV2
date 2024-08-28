// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract UsdtMock is ERC20("Tether", "USDT") {

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}
