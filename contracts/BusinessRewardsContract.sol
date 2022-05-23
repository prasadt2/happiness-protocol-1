// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./USRToken.sol";

/// @title Business Rewards Contract
/// @notice This contract is cloned for each Business Reward Token. It is used award rewards and redeem them, 
contract BusinessRewardsContract is Initializable, ERC20Upgradeable {

    uint16 public brtConversionUnits;
    address public creator;
    address public owner;
    address public usrToken;

    event Rewarded(address indexed _rewardee, uint256 _brtAmount);
    event Redeemed(address indexed _rewardee, uint256 _brtAmount, uint256 _usrAmount);

    constructor(address _owner, address _usrToken) {
        owner = _owner;
        usrToken = _usrToken;
    }

    function initialize(
        string memory _name, 
        string memory _symbol, 
        uint16 _brtConversionUnits, 
        address _creatorAddress, 
        uint256 _initialSupply) public virtual initializer {
        __ERC20_init(_name, _symbol);
        brtConversionUnits = _brtConversionUnits;
        creator = _creatorAddress;

        _mint(_msgSender(), _initialSupply);

    }

    /// @notice Checks to see if there is enough collatoral to rewards BRT
    /// @param _brtAmount number of BRT tokens
     function isRewardable(uint256 _brtAmount) public view returns(bool) {
         require(_brtAmount > 0, "Invalid BRT amount");

        uint256 _balance = USRToken(usrToken).balanceOf(address(this));

        if (_balance > 0 && ((_balance - convertBRTToUSRAmount(_brtAmount)) >= 0) ) 
            return true; 
        else 
            return false;
     }
    
    /// @notice Grant rewards
    /// @param _rewardee reward recipient
    /// @param _brtAmount number of BRT tokens
    function grantRewards(address _rewardee, uint256 _brtAmount) public returns(uint256) {
        require(isRewardable(_brtAmount), "Not enough collateral.");
        require(_rewardee != address(0), "Invalid rewardee address.");

        uint256 _usrAmount = convertBRTToUSRAmount(_brtAmount);
        USRToken(usrToken).burn(_usrAmount);
        transfer(_rewardee, _brtAmount);

        emit Rewarded(_rewardee, _brtAmount);
        return _brtAmount;
    }

    /// @notice The rewardee redeeming rewards
    /// @param _brtAmount number of BRT tokens
    function redeemRewards(uint256 _brtAmount) public returns(uint256) {

        require(balanceOf(msg.sender) >= _brtAmount, "No enough rewards to redeem");
        
        uint256 _usrAmount = convertBRTToUSRAmount(_brtAmount);

        _burn(msg.sender, _brtAmount);

        emit Redeemed(msg.sender, _brtAmount, _usrAmount);

        return _usrAmount;
    }

    function convertUSRToBRTAmount(uint256 _amount) public view returns (uint256) {
        return uint256(_amount * brtConversionUnits);
    }

    function convertBRTToUSRAmount(uint256 _amount) public view returns (uint256) {
        return uint256(_amount / brtConversionUnits);
    }


}
