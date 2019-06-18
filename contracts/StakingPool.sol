pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Burnable.sol";
import "math.sol";

contract StakingPool is ERC20, ERC20Detailed, ERC20Burnable, DSMath {
  uint private INITIAL_SUPPLY = 0;
  IERC20 public token;

  constructor (address tokenAddress) public ERC20Detailed("TellerStatus", "TSNT", 18) {
    token = IERC20(tokenAddress);
  }

  function exchangeRate (uint256 excludeAmount) public view returns (uint256) {
    if (totalSupply() == 0) return 1000000000000000000;
    return wdiv(token.balanceOf(address(this)), totalSupply());
  }

  function estimatedTokens(uint256 value) public view returns (uint256) {
    uint256 rate = exchangeRate(value);
    return wdiv(value, wdiv(rate, 1000000000000000000));
  }

  function deposit (uint256 amount) public payable {
    uint256 equivalentTokens = estimatedTokens(amount);
    token.transferFrom(msg.sender, address(this), amount);
    _mint(msg.sender, equivalentTokens);
  }

  function withdraw (uint256 amount) public {
    uint256 rate = exchangeRate(0);
    burn(amount);
    token.transfer(msg.sender, wmul(amount, wdiv(rate, 1000000000000000000)));
 }

}