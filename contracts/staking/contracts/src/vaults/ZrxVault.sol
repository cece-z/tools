/*

  Copyright 2019 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.5.9;

import "@0x/contracts-utils/contracts/src/LibSafeMath.sol";
import "@0x/contracts-asset-proxy/contracts/src/interfaces/IAssetProxy.sol";
import "@0x/contracts-asset-proxy/contracts/src/interfaces/IAssetData.sol";
import "@0x/contracts-erc20/contracts/src/interfaces/IERC20Token.sol";
import "../interfaces/IZrxVault.sol";
import "./MixinVaultCore.sol";


/// @dev This vault manages Zrx Tokens.
/// When a user mints stake, their Zrx Tokens are deposited into this vault.
/// Similarly, when they burn stake, their Zrx Tokens are withdrawn from this vault.
/// There is a "Catastrophic Failure Mode" that, when invoked, only
/// allows withdrawals to be made. Once this vault is in catastrophic
/// failure mode, it cannot be returned to normal mode; this prevents
/// corruption of related state in the staking contract.
contract ZrxVault is
    IVaultCore,
    IZrxVault,
    MixinVaultCore
{
    using LibSafeMath for uint256;

    // mapping from Owner to ZRX balance
    mapping (address => uint256) internal _balances;

    // Zrx Asset Proxy
    IAssetProxy public zrxAssetProxy;

    // Zrx Token
    IERC20Token internal _zrxToken;

    // Asset data for the ERC20 Proxy
    bytes internal _zrxAssetData;

    /// @dev Constructor.
    /// @param _zrxProxyAddress Address of the 0x Zrx Proxy.
    /// @param _zrxTokenAddress Address of the Zrx Token.
    constructor(
        address _zrxProxyAddress,
        address _zrxTokenAddress
    )
        public
    {
        zrxAssetProxy = IAssetProxy(_zrxProxyAddress);
        _zrxToken = IERC20Token(_zrxTokenAddress);
        _zrxAssetData = abi.encodeWithSelector(
            IAssetData(address(0)).ERC20Token.selector,
            _zrxTokenAddress
        );
    }

    /// @dev Sets the Zrx proxy.
    /// Note that only an authorized address can call this function.
    /// Note that this can only be called when *not* in Catastrophic Failure mode.
    /// @param _zrxProxyAddress Address of the 0x Zrx Proxy.
    function setZrxProxy(address _zrxProxyAddress)
        external
        onlyAuthorized
        onlyNotInCatastrophicFailure
    {
        zrxAssetProxy = IAssetProxy(_zrxProxyAddress);
        emit ZrxProxySet(_zrxProxyAddress);
    }

    /// @dev Deposit an `amount` of Zrx Tokens from `staker` into the vault.
    /// Note that only the Staking contract can call this.
    /// Note that this can only be called when *not* in Catastrophic Failure mode.
    /// @param staker of Zrx Tokens.
    /// @param amount of Zrx Tokens to deposit.
    function depositFrom(address staker, uint256 amount)
        external
        onlyStakingProxy
        onlyNotInCatastrophicFailure
    {
        // update balance
        _balances[staker] = _balances[staker].safeAdd(amount);

        // notify
        emit Deposit(staker, amount);

        // deposit ZRX from staker
        zrxAssetProxy.transferFrom(
            _zrxAssetData,
            staker,
            address(this),
            amount
        );
    }

    /// @dev Withdraw an `amount` of Zrx Tokens to `staker` from the vault.
    /// Note that only the Staking contract can call this.
    /// Note that this can only be called when *not* in Catastrophic Failure mode.
    /// @param staker of Zrx Tokens.
    /// @param amount of Zrx Tokens to withdraw.
    function withdrawFrom(address staker, uint256 amount)
        external
        onlyStakingProxy
        onlyNotInCatastrophicFailure
    {
        _withdrawFrom(staker, amount);
    }

    /// @dev Withdraw ALL Zrx Tokens to `staker` from the vault.
    /// Note that this can only be called when *in* Catastrophic Failure mode.
    /// @param staker of Zrx Tokens.
    function withdrawAllFrom(address staker)
        external
        onlyInCatastrophicFailure
        returns (uint256)
    {
        // get total balance
        uint256 totalBalance = _balances[staker];

        // withdraw ZRX to staker
        _withdrawFrom(staker, totalBalance);
        return totalBalance;
    }

    /// @dev Returns the balance in Zrx Tokens of the `staker`
    /// @return Balance in Zrx.
    function balanceOf(address staker)
        external
        view
        returns (uint256)
    {
        return _balances[staker];
    }

    /// @dev Withdraw an `amount` of Zrx Tokens to `staker` from the vault.
    /// @param staker of Zrx Tokens.
    /// @param amount of Zrx Tokens to withdraw.
    function _withdrawFrom(address staker, uint256 amount)
        internal
    {
        // update balance
        // note that this call will revert if trying to withdraw more
        // than the current balance
        _balances[staker] = _balances[staker].safeSub(amount);

        // notify
        emit Withdraw(staker, amount);

        // withdraw ZRX to staker
        _zrxToken.transfer(
            staker,
            amount
        );
    }
}
