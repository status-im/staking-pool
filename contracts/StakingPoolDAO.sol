
/* solium-disable security/no-block-members */
/* solium-disable security/no-inline-assembly */
pragma solidity >=0.5.0 <0.6.0;

import "./StakingPool.sol";
import "./common/Controlled.sol";
import "@openzeppelin/contracts/drafts/ERC20Snapshot.sol";
import "@openzeppelin/contracts/GSN/GSNRecipient.sol";

contract StakingPoolDAO is StakingPool, GSNRecipient, ERC20Snapshot, Controlled {

  enum VoteStatus {NONE, YES, NO}

  struct Proposal {
    address destination;
    uint value;
    bool executed;
    uint snapshotId;
    uint voteEndingBlock;
    bytes data;
    bytes details; // Store proposal information here

    mapping(bool => uint) votes;
    mapping(address => VoteStatus) voters;
  }

  uint public proposalCount;
  mapping(uint => Proposal) public proposals;

  uint public proposalVoteLength; // Voting available during this period
  uint public proposalExpirationLength; // Proposals should be executed up to 1 day after they have ended
  
  uint public minimumParticipation;  // Minimum participation percentage with 2 decimals 10000 == 100.00

  event NewProposal(uint indexed proposalId);
  event Vote(uint indexed proposalId, address indexed voter, VoteStatus indexed choice);
  event Execution(uint indexed proposalId);
  event ExecutionFailure(uint indexed proposalId);

  constructor (address _tokenAddress, uint _stakingPeriodLen, uint _proposalVoteLength, uint _proposalExpirationLength, uint _minimumParticipation) public
    StakingPool(_tokenAddress, _stakingPeriodLen) {
      proposalVoteLength = _proposalVoteLength;
      proposalExpirationLength = _proposalExpirationLength;
      minimumParticipation = _minimumParticipation;
  }

  function setProposalVoteLength(uint _newProposalVoteLength) public onlyController {
    proposalVoteLength = _newProposalVoteLength;
  }

  function setProposalExpirationLength(uint _newProposalExpirationLength) public onlyController {
    proposalExpirationLength = _newProposalExpirationLength;
  }

  function setMinimumParticipation(uint _newMinimumParticipation) public onlyController {
    minimumParticipation = _newMinimumParticipation;
  }

  /// @dev Adds a new proposal
  /// @param destination Transaction target address.
  /// @param value Transaction ether value.
  /// @param data Transaction data payload.
  /// @param details Proposal details
  /// @return Returns proposal ID.
  function addProposal(address destination, uint value, bytes calldata data, bytes calldata details) external returns (uint proposalId)
  {
    require(balanceOf(msg.sender) > 0, "Token balance is required to perform this operation");

    // TODO: should proposals have a cost? or require a minimum amount of tokens?

    assert(destination != address(0));

    proposalId = proposalCount;
    proposals[proposalId] = Proposal({
        destination: destination,
        value: value,
        data: data,
        executed: false,
        snapshotId: snapshot(),
        details: details,
        voteEndingBlock: block.number + proposalVoteLength
    });

    proposalCount++;

    emit NewProposal(proposalId);
  }

  function vote(uint proposalId, bool choice) external {
    Proposal storage proposal = proposals[proposalId];

    require(proposal.voteEndingBlock > block.number, "Proposal has already ended");

    address sender = _msgSender();

    uint voterBalance = balanceOfAt(sender, proposal.snapshotId);
    require(voterBalance > 0, "Not enough tokens at the moment of proposal creation");

    VoteStatus oldVote = proposal.voters[sender];

    if(oldVote != VoteStatus.NONE){ // Reset
      bool oldChoice = oldVote == VoteStatus.YES ? true : false;
      proposal.votes[oldChoice] -= voterBalance;
    }

    VoteStatus enumVote = choice ? VoteStatus.YES : VoteStatus.NO;

    proposal.votes[choice] += voterBalance;
    proposal.voters[sender] = enumVote;

    lastActivity[sender] = block.timestamp;

    emit Vote(proposalId, sender, enumVote);
  }

  // call has been separated into its own function in order to take advantage
  // of the Solidity's code generator to produce a loop that copies tx.data into memory.
  function external_call(address destination, uint value, uint dataLength, bytes memory data) internal returns (bool) {
    bool result;
    assembly {
      let x := mload(0x40)   // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
      let d := add(data, 32) // First 32 bytes are the padded length of data, so exclude that
      result := call(
        sub(gas, 34710),   // 34710 is the value that solidity is currently emitting
                            // It includes callGas (700) + callVeryLow (3, to pay for SUB) + callValueTransferGas (9000) +
                            // callNewAccountGas (25000, in case the destination address does not exist and needs creating)
        destination,
        value,
        d,
        dataLength,        // Size of the input (in bytes) - this is what fixes the padding problem
        x,
        0                  // Output is ignored, therefore the output size is zero
      )
    }
    return result;
  }

  /// @dev Allows anyone to execute an approved non-expired proposal
  /// @param proposalId Proposal ID.
  function executeTransaction(uint proposalId) public {
    Proposal storage proposal = proposals[proposalId];

    require(proposal.executed == false, "Proposal already executed");
    require(block.number > proposal.voteEndingBlock, "Voting is still active");
    require(block.number <= proposal.voteEndingBlock + proposalExpirationLength, "Proposal is already expired");
    require(proposal.votes[true] > proposal.votes[false], "Proposal wasn't approved");

    uint totalParticipation = ((proposal.votes[true] + proposal.votes[false]) * 10000) / totalSupply();
    require(totalParticipation >= minimumParticipation, "Did not meet the minimum required participation");


    proposal.executed = true;

    bool result = external_call(proposal.destination, proposal.value, proposal.data.length, proposal.data);
    require(result, "Execution Failed");
    emit Execution(proposalId);
  }

  function votes(uint proposalId, bool choice) public view returns (uint) {
    return proposals[proposalId].votes[choice];
  }

  function voteOf(address account, uint proposalId) public view returns (VoteStatus) {
    return proposals[proposalId].voters[account];
  }

  function isProposalApproved(uint proposalId) public view returns (bool approved, bool executed){
    Proposal storage proposal = proposals[proposalId];
    if(block.number <= proposal.voteEndingBlock) {
      approved = false;
    } else {
      approved = proposal.votes[true] > proposal.votes[false];
    }
    executed = proposal.executed;
  }

  function() external payable {
    //
  }

  enum GSNErrorCodes {
    FUNCTION_NOT_AVAILABLE,
    HAS_ETH_BALANCE,
    GAS_PRICE,
    TRX_TOO_SOON,
    ALREADY_VOTED,
    NO_TOKEN_BALANCE
  }

  bytes4 constant VOTE_SIGNATURE = bytes4(keccak256("vote(uint256,bool)"));

  function acceptRelayedCall(
      address relay,
      address from,
      bytes calldata encodedFunction,
      uint256 transactionFee,
      uint256 gasPrice,
      uint256 gasLimit,
      uint256 nonce,
      bytes calldata approvalData,
      uint256 maxPossibleCharge
  ) external view returns (uint256, bytes memory) {

    bytes memory abiEncodedFunc = encodedFunction; // Call data elements cannot be accessed directly
    bytes4 functionSignature;
    uint proposalId;

    assembly {
      functionSignature := mload(add(abiEncodedFunc, add(0x20, 0)))
      proposalId := mload(add(abiEncodedFunc, 36))
    }

    return _evaluateConditions(from, functionSignature, proposalId, gasPrice);
  }

  function _evaluateConditions(
    address _from,
    bytes4 _functionSignature,
    uint _proposalId,
    uint _gasPrice
  ) internal view returns (uint256, bytes memory) {
    if(_functionSignature != VOTE_SIGNATURE) return _rejectRelayedCall(uint256(GSNErrorCodes.FUNCTION_NOT_AVAILABLE));

    Proposal storage proposal = proposals[_proposalId];

    if(balanceOfAt(_from, proposal.snapshotId) == 0) return _rejectRelayedCall(uint256(GSNErrorCodes.NO_TOKEN_BALANCE));

    /* ?
    if(from.balance > 600000 * gasPrice) return _rejectRelayedCall(uint256(GSNErrorCodes.HAS_ETH_BALANCE));
    */

    if(_gasPrice > 20000000000) return _rejectRelayedCall(uint256(GSNErrorCodes.GAS_PRICE)); // 20 gwei

    if((lastActivity[_from] + 15 minutes) > block.timestamp) return _rejectRelayedCall(uint256(GSNErrorCodes.TRX_TOO_SOON));

    if(proposal.voters[_from] != VoteStatus.NONE) return _rejectRelayedCall(uint256(GSNErrorCodes.ALREADY_VOTED));

    return _approveRelayedCall();
  }

  mapping(address => uint) public lastActivity;

  function _preRelayedCall(bytes memory context) internal returns (bytes32) {
  }

  function _postRelayedCall(bytes memory context, bool, uint256 actualCharge, bytes32) internal {
  }
}
