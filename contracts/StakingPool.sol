pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Burnable.sol";
import "math.sol";

contract StakingPool is ERC20, ERC20Detailed, ERC20Burnable, DSMath {
  uint private INITIAL_SUPPLY = 0;

  constructor () public ERC20Detailed("TellerStatus", "TSNT", 18) {
  }

  function exchangeRate (uint256 excludeAmount) public view returns (uint256) {
    if (totalSupply() == 0) return 1000000000000000000;
    return wdiv(address(this).balance - excludeAmount, totalSupply());
  }

  function estimatedTokens(uint256 value) public view returns (uint256) {
    uint256 rate = exchangeRate(value);
    return wdiv(value, wdiv(rate, 1000000000000000000));
  }

  function deposit () public payable {
    uint256 rate = exchangeRate(msg.value);
    _mint(msg.sender, estimatedTokens(msg.value));
  }

  function withdraw (uint256 amount) public {
    uint256 rate = exchangeRate(0);
    burn(amount);
    msg.sender.transfer(wmul(amount, wdiv(rate, 1000000000000000000)));
  }

  function() external payable {
  }

}