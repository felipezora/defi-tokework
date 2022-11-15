// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./oracles/PriceFeed.sol";
import "./tokens/MeLiTW.sol";
import "./tokens/COPTW.sol";

// errors
error ErrorCollateralTransfer(address from, uint256 value);
error InsufficientCollateral(address from, uint256 amountToWithdraw, uint256 amountAvailable);
error ErrorStableTransfer(address from, uint256 value, uint256 debt);
error ErrorStableWithdraw(address destination, uint256 value);

// structs
struct UserInstance {
    uint256 liquidCollateral;
    uint256 frozenCollateral;
    uint256 debt;
}

// interfaces
interface ITokework {

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function decimals() external view returns (uint8);
}

contract DebtManager is Ownable {

    // utils
    Aggregator public dataFeed = Aggregator(0xD7ACd2a9FD159E69Bb102A1ca21C9a3e3A5F771B);
    ITokework public melitw;
    COPTW public stablecop;

    // data storage
    mapping(address => UserInstance) public usersLedger;

    // events
    event collatDeposited(address depositor, uint256 amount);
    event collatWithdrawn(address retireer, uint256 amount);
    event stableDeposited(address depositor, uint256 amount, uint256 updatedDebt);
    event notAbleToIndebt(address who, uint256 liquidCollat, uint256 liquidNeeded);
    event borrowerLiquidated(address borrower, uint256 collatAmount, uint256 debt);

    constructor (address _tokeworkAddress, address _stableTokAddress) {
        melitw = ITokework(_tokeworkAddress);
        stablecop = COPTW(_stableTokAddress);
    }

    function depositCollateral (uint256 _amount) external {
        bool success = melitw.transferFrom(msg.sender, address(this), _amount);
        if(!success){
            revert ErrorCollateralTransfer({
                from: msg.sender,
                value: _amount
            });
        }
        usersLedger[msg.sender].liquidCollateral += _amount;
        emit collatDeposited(msg.sender, _amount);
    }

    function withdrawCollateral (uint256 _amount) external {
        UserInstance storage _user = usersLedger[msg.sender];
        if(_amount > _user.liquidCollateral){
            revert InsufficientCollateral({
                from: msg.sender,
                amountToWithdraw: _amount,
                amountAvailable: _user.liquidCollateral
            });
        }
        _user.liquidCollateral -= _amount;
        bool success = melitw.transfer(msg.sender, _amount);
        if(!success){
            _user.liquidCollateral += _amount;
            revert ErrorCollateralTransfer({
                from: address(this),
                value: _amount
            });
        }
        emit collatWithdrawn(msg.sender, _amount);
    }

    function payDebt (uint256 _amount) external{
        UserInstance storage _user = usersLedger[msg.sender];
        if(_amount > _user.debt){
            revert ErrorStableTransfer({
                from: msg.sender,
                value: _amount,
                debt: _user.debt
            });
        }
        bool success = stablecop.transferFrom(msg.sender, address(this), _amount);
        if(!success){
            revert ErrorStableTransfer({
                from: msg.sender,
                value: _amount,
                debt: _user.debt
            });
        }
        _user.debt -= _amount;
        uint256 percentagePaid = _amount * 100 / _user.debt;
        uint256 liquidated = _user.frozenCollateral * percentagePaid * 10 ** (melitw.decimals() - 2);
        if(liquidated > _user.frozenCollateral){
            _user.liquidCollateral += _user.frozenCollateral;
            _user.frozenCollateral = 0;
        } else {
            _user.liquidCollateral += liquidated;
            _user.frozenCollateral -= liquidated;
        }
        emit stableDeposited(msg.sender, _amount, _user.debt);
    }

    function requestDebt (uint256 _amount) external {
        UserInstance storage _user = usersLedger[msg.sender];
        (bool isAble, uint256 collateralToFreeze) = calculateBorrowingCapacity(msg.sender, _amount);
        if(!isAble){
            emit notAbleToIndebt(msg.sender, _user.liquidCollateral, collateralToFreeze);
            return;
        }
        _user.debt += _amount;
        _user.liquidCollateral -= collateralToFreeze;
        _user.frozenCollateral += collateralToFreeze;
        stablecop.transfer(msg.sender, _amount);
        emit stableDeposited(address(this), _amount, _user.debt);
    }

    function calculateBorrowingCapacity (address _who, uint256 _amountStableRequest) public view returns (bool _isAble, uint256 _collateralToFreeze){
        uint256 collateralPrice = dataFeed.latestRoundData().answer * 10 ** 18;
        uint256 freezableStable = 100 * _amountStableRequest / 45;
        uint256 freezableCollateral = freezableStable / collateralPrice;
        UserInstance storage _user = usersLedger[_who];
        if(_user.liquidCollateral > freezableCollateral){
            _collateralToFreeze = freezableCollateral;
            _isAble = true;
        }
    }

    function liquidateBorrower (address _who, address _destinationCollateral) external onlyOwner {
        UserInstance storage _user = usersLedger[_who];
        UserInstance memory _userBeforeChanges = usersLedger[_who];
        bool success = melitw.transfer(_destinationCollateral, _user.frozenCollateral);
        if(!success){
            revert ErrorCollateralTransfer({
                from: address(this),
                value: _user.frozenCollateral
            });
        }
        _user.debt = 0;
        _user.frozenCollateral = 0;
        emit borrowerLiquidated(_who, _userBeforeChanges.frozenCollateral, _userBeforeChanges.debt);
    }

    function withdrawStable (uint256 _amount, address _destinationStable) external onlyOwner{
        bool success = stablecop.transfer(_destinationStable, _amount);
        if(!success){
            revert ErrorStableWithdraw({
                destination: _destinationStable,
                value: _amount
            });
        }
        emit stableDeposited(msg.sender, _amount, 0);
    }
}