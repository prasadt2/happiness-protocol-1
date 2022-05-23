// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "./USRToken.sol";
import "./BusinessRewardsContract.sol";


/// @title Coordinator
/// @notice Coordinator contract is the main on-chain coordinator for all things rewards protocol
contract Coordinator is Ownable {

    // rewards redemption fee as a percentage of the USDT rewarded to the redemptionee
    // represented as an integer denominator 
    uint8 public rewardsRedemptionFee;    
    uint8 public constant USDTtoUSRMultipler = 1;

    // business rewards contract creation fee in Wei
    uint256 public contractCreationfee;

    address public constant usdtContractAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    USRToken public usrToken;
    BusinessRewardsContract public businessRewardsContractTemplate;



    // Registry to maintain all the business rewards contracts created by the Coordinator contract
    // Each contract is uniquely identified by a string id.
    mapping(address => BusinessContract) public businessRewardsContractRegistry;

    // 
    // Business Contract definition
    struct BusinessContract {
        uint16 _brtConversionUnits;
        string _name;
        string _symbol;
        address _creatorAddress;
    }

    event ContractCreated(address indexed _createdBy, address indexed _contractAddress, string indexed description);
    event CollateralAdded(address indexed _addedBy, uint256 usdtAmount, uint256 usrAmount);
    event WithdrewCollateral(address indexed _to, uint256 _usdtAmount);
    event RewardsGranted(address indexed _brtAddress, address indexed _rewardee, uint256 _brtAmount);
    event RedeemedRewards(address indexed _brtAddress, address indexed _rewardee, uint256 _brtAmount, uint256 _usdtAmount);

    /// @notice Constructor
    /// @dev Business Rewards contract should be deployed first before this contract
    /// @param _contractCreationFee Contract creation fee in Wei.
    /// @param _rewardsRedemptionFee Rewards redemption fee, represented as an integer demoninator (1/x)%. For example, if the fee is 3%, x is 5
    constructor(uint _contractCreationFee, uint8 _rewardsRedemptionFee) {
        contractCreationfee =_contractCreationFee;
        rewardsRedemptionFee = _rewardsRedemptionFee;

        usrToken = new USRToken();
        businessRewardsContractTemplate = new BusinessRewardsContract(address(this), address(usrToken));      
    }

    /// @notice Creates Business Rewards Contract
    /// @param _name The rewards descriptive name
    /// @param _symbol The rewards token symbol
    /// @param _brtConversionUnits The USDT to BRT conversion units expressed as an integer >= 1. If value is 100, 1 USDT = 100 BRT
    function createBusinessRewardsContract(address _creatorAddress, string memory _name, string memory _symbol, uint16 _brtConversionUnits) public onlyOwner {

        require(bytes(_name).length > 0, "Invalid name");
        require(bytes(_symbol).length > 0, "Invalid symbol");
        require(_brtConversionUnits > 0, "Invalid USDT to BRT conversion units");
        require(_creatorAddress != address(0), "Invalid creator address");

        // create clone of BusinessRewardsContract and initialize it. 
        uint256 _initialSupply = 0;
        address _brtClone = Clones.clone(address(businessRewardsContractTemplate));
        BusinessRewardsContract(_brtClone).initialize(_name, _symbol, _brtConversionUnits, _creatorAddress, _initialSupply);

        // add to registry
        BusinessContract memory _contract = BusinessContract(_brtConversionUnits, _name, _symbol, _creatorAddress) ;
        businessRewardsContractRegistry[_brtClone] = _contract;

        emit ContractCreated(msg.sender, _brtClone, string(abi.encodePacked(_name, "-", _symbol)));
    }

    /// @notice Add Collaterel
    /// @param _brtAddress Business rewards address
    /// @param _usdtAmount USDT amount to add as collateral 
    function addCollateral(address _brtAddress, uint256 _usdtAmount) public  {
        require(businessRewardsContractRegistry[_brtAddress]._creatorAddress != address(0), "Invalid BRT address");
        require(_usdtAmount > 0, "Invalid amount");

        _sendUSDT(address(this), _usdtAmount);

        // mint corresponding amount of USR token
        uint256 _usrAmount = convertUSDTtoUSR(_usdtAmount);
        usrToken.mint(_brtAddress, _usrAmount);

        emit CollateralAdded(msg.sender, _usdtAmount, _usrAmount);

    }

    /// @notice Withdraw Collaterel
    /// @param _brtAddress Business rewards address
    /// @param _usdtAmount USDT amount to withdraw as collateral 
    function withdrawCollateral(address _brtAddress, uint256 _usdtAmount) public  {
        require(businessRewardsContractRegistry[_brtAddress]._creatorAddress != address(0), "Invalid BRT address");
        require(_usdtAmount > 0, "Invalid amount");

        // burn USR tokens
        uint256 _usrAmount = convertUSDTtoUSR(_usdtAmount);
        require(usrToken.balanceOf(_brtAddress) >= _usrAmount, "Not enough USR tokens");
        usrToken.burn(_usrAmount);

        _sendUSDT(msg.sender, _usdtAmount);

        emit WithdrewCollateral(msg.sender, _usdtAmount);

    }    

    /// @notice Transfer Rewards
    /// @param _brtAddress Business rewards address
    /// @param _rewardee address to which rewards are to be granted
    /// @param _brtAmount BRT amount
    function transferRewards(address _brtAddress, address _rewardee, uint256 _brtAmount) public onlyOwner {
        require(businessRewardsContractRegistry[_brtAddress]._creatorAddress != address(0), "Invalid BRT address");
        require(_brtAmount > 0, "Invalid amount");

        // check if BRT worth collateral is present and reward
        require(BusinessRewardsContract(_brtAddress).isRewardable(_brtAmount), "Not enough collateral to reward");
        BusinessRewardsContract(_brtAddress).grantRewards(_rewardee, _brtAmount);

        emit RewardsGranted(_brtAddress, _rewardee, _brtAmount);

    }   

    /// @notice Redeem Rewards
    /// @param _brtAddress Business rewards address
    /// @param _brtAmount BRT amount
    function redeemRewards(address _brtAddress, uint256 _brtAmount) public onlyOwner { 
        require(businessRewardsContractRegistry[_brtAddress]._creatorAddress != address(0), "Invalid BRT address");
        require(_brtAmount > 0, "Invalid amount");
        uint256 _usrAmount = businessRewardsContractTemplate.convertBRTToUSRAmount(_brtAmount);
        uint256 _usdtAmount = convertUSRtoUSDT(_usrAmount); 

        // is there enough USDT balance.
        IERC20 usdt = IERC20(address(usdtContractAddress));
        require(usdt.balanceOf(address(this)) > 0, "Not enough USDT balance");

        // check if BRT worth collateral is present and redeem
        require(BusinessRewardsContract(_brtAddress).balanceOf(msg.sender) > 0, "Not enough collateral to reward");
        _usrAmount = BusinessRewardsContract(_brtAddress).redeemRewards(_brtAmount);
        _usdtAmount = convertUSRtoUSDT(_usrAmount); 
        _sendUSDT(msg.sender, _usdtAmount);

        emit RedeemedRewards(_brtAddress, msg.sender, _brtAmount, _usdtAmount);

    }     

    function convertUSDTtoUSR(uint256 _amount) public pure returns(uint256) {
        return _amount * USDTtoUSRMultipler;
    }

    function convertUSRtoUSDT(uint256 _amount) public pure returns(uint256) {
        // todo: implement safe division
        return _amount / USDTtoUSRMultipler;
    }

    function _sendUSDT(address _to, uint256 _amount) internal {
         // This is the mainnet USDT contract address
         // Using on other networks (rinkeby, local, ...) would fail
         //  - there's no contract on this address on other networks
        IERC20 usdt = IERC20(address(usdtContractAddress));
        
        // transfers USDT that belong to your contract to the specified address
        usdt.transfer(_to, _amount);
    }

}
