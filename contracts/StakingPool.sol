/* solium-disable security/no-block-members */
/* solium-disable security/no-inline-assembly */
pragma solidity >=0.5.0 <0.6.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "./math.sol";
import "./token/ApproveAndCallFallBack.sol";
import "./token/MiniMeTokenInterface.sol";

contract StakingPool is ERC20, ERC20Detailed, ERC20Burnable, DSMath, ApproveAndCallFallBack {
  uint public MAX_SUPPLY = 0;

  MiniMeTokenInterface public token;
  uint public stakingBlockLimit;
  uint public blockToCheckBalance;

  /**
   * @param _tokenAddress SNT token address
   * @param _stakingPeriodLen Number of block that represents the period when Staking is available
   */
  constructor (address _tokenAddress, uint _stakingPeriodLen) public ERC20Detailed("Status Stake Token", "SST", 18) {
    token = MiniMeTokenInterface(_tokenAddress);
    stakingBlockLimit = block.number + _stakingPeriodLen;
    blockToCheckBalance = block.number;
  }

  /**
   * @notice Determine exchange rate
   * @return Exchange rate
   */
  function exchangeRate (uint256 excludeAmount) public view returns (uint256) {
    if (totalSupply() == 0) return 1000000000000000000;
    return wdiv(token.balanceOf(address(this)), totalSupply());
  }

  /**
   * @notice Estimate the number of tokens that will be minted based on an amount of SNT
   * @param _value Amount of SNT used in calculation
   */
  function estimatedTokens(uint256 _value) public view returns (uint256) {
    uint256 rate = exchangeRate(_value);
    return wdiv(_value, wdiv(rate, 1000000000000000000));
  }

  /**
   * @notice Determine max amount that can be staked
   * @return Max amount to stake
   */
  function maxAmountToStake() public view returns (uint256) {
    return MAX_SUPPLY - totalSupply();
  }

  /**
   * @notice Stake SNT in the pool and receive tSNT. During the stake period you can stake up to the amount of SNT you had when the pool was created. Afterwards, the amount you can stake can not exceed MAXSUPPLY - TOTALSUPPLY
   * @dev Use this function with approveAndCall, since it requires a SNT transfer
   * @param _amount Amount to stake
   */
  function stake(uint256 _amount) public payable {
    if(block.number <= stakingBlockLimit){
      uint maxBalance = token.balanceOfAt(msg.sender, blockToCheckBalance);
      require(_amount <= maxBalance, "Stake amount exceeds SNT balance at pool creation");
      _stake(msg.sender, _amount);
      MAX_SUPPLY = totalSupply();
    } else {
      require(_amount <= (MAX_SUPPLY - totalSupply()), "Max stake amount exceeded");
      _stake(msg.sender, _amount);
    }
  }

  /**
   * @dev Stake SNT in the contract, and receive tSNT
   * @param _from Address transfering the SNT
   * @param _amount Amount being staked
   */
  function _stake(address _from, uint256 _amount) internal returns (uint equivalentTokens){
    equivalentTokens = estimatedTokens(_amount);
    require(token.transferFrom(_from, address(this), _amount), "Couldn't transfer");
    _mint(_from, equivalentTokens);
  }

  /**
   * @notice Withdraw SNT from Staking Pool, by burning tSNT
   * @param amount Amount to withdraw
   */
  function withdraw (uint256 amount) public {
    uint256 rate = exchangeRate(0);
    burn(amount);

    if(block.number <= stakingBlockLimit){
     MAX_SUPPLY = totalSupply(); 
    }

    require(token.transfer(msg.sender, wmul(amount, wdiv(rate, 1000000000000000000))), "Couldn't transfer");
 }

  /**
   * @notice Support for "approveAndCall". Callable only by `token()`.
   * @param _from Who approved.
   * @param _amount Amount being approved,
   * @param _token Token being approved, need to be equal `token()`.
   * @param _data ABI encoded data`.
   */
  function receiveApproval(address _from, uint256 _amount, address _token, bytes memory _data) public {
    require(_token == address(token), "Wrong token");
    require(_token == address(msg.sender), "Wrong call");
    require(_data.length == 36, "Wrong data length");

    bytes4 sig;
    uint amount;
    (sig, amount) = abiDecode(_data);

    require(amount == _amount, "Amounts mismatch");
    require(sig == 0xa694fc3a, "Wrong method selector"); // stake(uint256)
    _stake(_from, amount);
  }

  /**
   * @dev Decode calldata - stake(uint256)
   * @param _data Calldata, ABI encoded
   */
  function abiDecode(bytes memory _data) internal pure returns (
    bytes4 sig,
    uint256 amount
  ) {
    assembly {
      sig := mload(add(_data, add(0x20, 0)))
      amount := mload(add(_data, 36))
    }
  }
}
