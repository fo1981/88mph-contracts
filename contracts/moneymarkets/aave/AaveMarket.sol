// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../IMoneyMarket.sol";
import "../../libs/Rescuable.sol";
import "./imports/ILendingPool.sol";
import "./imports/ILendingPoolAddressesProvider.sol";
import "./imports/IAaveMining.sol";

contract AaveMarket is IMoneyMarket, OwnableUpgradeable, Rescuable {
    using SafeERC20Upgradeable for ERC20Upgradeable;
    using AddressUpgradeable for address;

    uint16 internal constant REFERRALCODE = 20; // Aave referral program code

    ILendingPoolAddressesProvider public provider; // Used for fetching the current address of LendingPool
    ERC20Upgradeable public override stablecoin;
    ERC20Upgradeable public aToken;
    IAaveMining public aaveMining;
    address public rewards;

    function initialize(
        address _provider,
        address _aToken,
        address _aaveMining,
        address _rewards,
        address _stablecoin
    ) external initializer {
        __Ownable_init();

        // Verify input addresses
        require(
            _provider.isContract() &&
                _aToken.isContract() &&
                _aaveMining.isContract() &&
                _stablecoin.isContract(),
            "AaveMarket: An input address is not a contract"
        );

        provider = ILendingPoolAddressesProvider(_provider);
        stablecoin = ERC20Upgradeable(_stablecoin);
        aaveMining = IAaveMining(_aaveMining);
        aToken = ERC20Upgradeable(_aToken);
        rewards = _rewards;
    }

    function deposit(uint256 amount) external override onlyOwner {
        require(amount > 0, "AaveMarket: amount is 0");

        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Approve `amount` stablecoin to lendingPool
        stablecoin.safeIncreaseAllowance(address(lendingPool), amount);

        // Deposit `amount` stablecoin to lendingPool
        lendingPool.deposit(
            address(stablecoin),
            amount,
            address(this),
            REFERRALCODE
        );
    }

    function withdraw(uint256 amountInUnderlying)
        external
        override
        onlyOwner
        returns (uint256 actualAmountWithdrawn)
    {
        require(amountInUnderlying > 0, "AaveMarket: amountInUnderlying is 0");

        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());

        // Redeem `amountInUnderlying` aToken, since 1 aToken = 1 stablecoin
        // Transfer `amountInUnderlying` stablecoin to `msg.sender`
        lendingPool.withdraw(
            address(stablecoin),
            amountInUnderlying,
            msg.sender
        );

        return amountInUnderlying;
    }

    function claimRewards() external override {
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        aaveMining.claimRewards(assets, type(uint256).max, rewards);
    }

    function totalValue() external view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function incomeIndex() external view override returns (uint256) {
        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
        return lendingPool.getReserveNormalizedIncome(address(stablecoin));
    }

    /**
        Param setters
     */
    function setRewards(address newValue) external override onlyOwner {
        require(newValue.isContract(), "HarvestMarket: not contract");
        rewards = newValue;
        emit ESetParamAddress(msg.sender, "rewards", newValue);
    }

    /**
        Rescuable
     */
    function _authorizeRescue(address token, address target)
        internal
        view
        override
    {
        require(token != address(aToken), "AaveMarket: no steal");
        require(msg.sender == owner(), "AaveMarket: not owner");
    }
}
