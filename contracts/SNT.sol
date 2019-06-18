pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";

contract SNT is ERC20, ERC20Detailed, ERC20Mintable {
  uint private INITIAL_SUPPLY = 10000000000000000000000;

  constructor () public ERC20Detailed("Status", "SNT", 18) {
    _mint(msg.sender, INITIAL_SUPPLY);
  }

}