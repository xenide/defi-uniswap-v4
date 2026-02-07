// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// import {console} from "forge-std/Test.sol";

import {IERC20} from "../interfaces/IERC20.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/IUnlockCallback.sol";
import {CurrencyLib} from "../libraries/CurrencyLib.sol";

contract Flash is IUnlockCallback {
    using CurrencyLib for address;

    IPoolManager public immutable poolManager;
    // Contract address to test flash loan
    address private immutable tester;

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "not pool manager");
        _;
    }

    constructor(address _poolManager, address _tester) {
        poolManager = IPoolManager(_poolManager);
        tester = _tester;
    }

    receive() external payable {}

    function unlockCallback(bytes calldata data)
        external
        onlyPoolManager
        returns (bytes memory)
    {
        (address currency, uint256 amount) = abi.decode(data, (address, uint256));
        poolManager.take(currency, address(this), amount);
        tester.call("");

        // N.B. this pattern: it's always sync, transfer, then setle
        poolManager.sync(currency);
        IERC20(currency).transfer(address(poolManager), amount);
        uint256 paid = poolManager.settle();
        assert(paid == amount);
        return "";
    }

    function flash(address currency, uint256 amount) external {
        // Write your code here
        poolManager.unlock(abi.encode(currency, amount));
    }
}
