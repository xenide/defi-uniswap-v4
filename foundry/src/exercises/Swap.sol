// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// import {console} from "forge-std/Test.sol";

import {IERC20} from "../interfaces/IERC20.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/IUnlockCallback.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {SwapParams} from "../types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {CurrencyLib} from "../libraries/CurrencyLib.sol";
import {MIN_SQRT_PRICE, MAX_SQRT_PRICE} from "../Constants.sol";

contract Swap is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for int128;
    using SafeCast for uint128;
    using CurrencyLib for address;

    IPoolManager public immutable poolManager;

    struct SwapExactInputSingleHop {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMin;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "not pool manager");
        _;
    }

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    receive() external payable {}

    function unlockCallback(bytes calldata data)
        external
        onlyPoolManager
        returns (bytes memory)
    {
        SwapExactInputSingleHop memory s = abi.decode(data, (SwapExactInputSingleHop));

        address inputCurrency = s.zeroForOne? s.poolKey.currency0 : s.poolKey.currency1;
        address outputCurrency = s.zeroForOne? s.poolKey.currency1 : s.poolKey.currency0;

        BalanceDelta delta = BalanceDelta.wrap(poolManager.swap(s.poolKey, SwapParams({
            zeroForOne: s.zeroForOne,
            amountSpecified: -int128(s.amountIn),
            sqrtPriceLimitX96: s.zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
        }), ""));

        uint256 outputAmt = s.zeroForOne ? uint256(int256(delta.amount1())) : uint256(int256(delta.amount0()));
        require(outputAmt >= s.amountOutMin, "Output amt too little");

        poolManager.take(
            outputCurrency,
            address(this),
            outputAmt
        );

        // N.B. If the input currency is ETH, the transfer and settle is in one tx
        // Unlike ERC20 settles
        poolManager.sync(inputCurrency);
        if (inputCurrency == address(0)) {
            poolManager.settle{value: s.amountIn}();
        } else {
            inputCurrency.transferOut(address(poolManager), s.amountIn);
            poolManager.settle();
        }

        return "";
    }

    function swap(SwapExactInputSingleHop calldata params) external payable {
        // Write your code here
        address currencyIn = params.zeroForOne ? params.poolKey.currency0 : params.poolKey.currency1;
        address currencyOut = params.zeroForOne ? params.poolKey.currency1 : params.poolKey.currency0;

        currencyIn.transferIn(msg.sender,  params.amountIn);
        poolManager.unlock(abi.encode(params));

        if (currencyIn.balanceOf(address(this)) > 0) {
            currencyIn.transferOut(msg.sender, currencyIn.balanceOf(address(this)));
        }

        currencyOut.transferOut(msg.sender, currencyOut.balanceOf(address(this)));
    }
}
