// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/access/Ownable.sol';

contract Aggregator is Ownable {

    struct DataPoint{
        uint192 answer; 
        uint64 timestamp;
    }
    mapping(uint => DataPoint) public roundById;
    uint public latestRound;

    function latestRoundData()external view
    returns (DataPoint memory){
        return roundById[latestRound];
    }

    function updateDataPoint(uint192 _answer) external onlyOwner{
        roundById[latestRound] = DataPoint(_answer,uint64(block.timestamp));
        unchecked {
            latestRound++;
        }
    }

    function description() external pure returns (string memory){
        return "Precio MeLiTW in TWCOP";
    }
}