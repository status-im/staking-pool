pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Burnable.sol";
import "./math.sol";
import "./token/ApproveAndCallFallBack.sol";

contract StakingPool is ERC20, ERC20Detailed, ERC20Burnable, DSMath, ApproveAndCallFallBack {
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
    _deposit(msg.sender, amount);
  }

  function _deposit(address _from, uint256 amount) internal {
    uint256 equivalentTokens = estimatedTokens(amount);
    require(token.transferFrom(_from, address(this), amount), "Couldn't transfer");
    _mint(_from, equivalentTokens);
  }

  function withdraw (uint256 amount) public {
    uint256 rate = exchangeRate(0);
    burn(amount);
    require(token.transfer(msg.sender, wmul(amount, wdiv(rate, 1000000000000000000))), "Couldn't transfer");
 }

  /**
   * @notice Support for "approveAndCall". Callable only by `token()`.
   * @param _from Who approved.
   * @param _amount Amount being approved,
   * @param _token Token being approved, need to be equal `token()`.
   * @param _data Abi encoded data`.
   */
  function receiveApproval(address _from, uint256 _amount, address _token, bytes memory _data) public {
    require(_token == address(token), "Wrong token");
    require(_token == address(msg.sender), "Wrong call");
    require(_data.length == 36, "Wrong data length");

    bytes4 sig;
    uint amount;
    (sig, amount) = abiDecodeRegister(_data);

    require(amount == _amount, "Amounts mismatch");
    require(sig == 0xb6b55f25, "Wrong method selector"); // deposit(uint256)
    _deposit(_from, amount);
  }

  function abiDecodeRegister(bytes memory _data) private returns(
    bytes4 sig,
    uint256 amount
  ) {
    assembly {
      sig := mload(add(_data, add(0x20, 0)))
      amount := mload(add(_data, 36))
    }
  }
}