// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

contract WhiteList is Ownable {
    mapping(address => bool) public validCollaterals;

    constructor (address _newCollateral){
        validCollaterals[_newCollateral] = true;
    }

    function addToList (address _toAdd) external onlyOwner {
        validCollaterals[_toAdd] = true;
    }

    function removeFromList (address _toRemove) external onlyOwner {
        validCollaterals[_toRemove] = false;
    }
}