// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./BRT.sol";

contract Coordinator {
    BRT[] public brtContracts;

    function createBRT( string memory _model) public {
        BRT brt = new BRT( _model);
        brtContracts.push(brt);
    }

    function getBrt(uint256 _index)
        public
        view
        returns (
            string memory model,
            address brtAddr,
            uint256 balance
        )
    {
        BRT brt = brtContracts[_index];

        return (brt.model(), brt.brtAddr(), address(brt).balance);
    }
}
