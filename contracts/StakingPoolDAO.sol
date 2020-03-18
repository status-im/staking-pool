
/* solium-disable security/no-block-members */
/* solium-disable security/no-inline-assembly */
pragma solidity >=0.5.0 <0.6.0;

import "./StakingPool.sol";
import "./common/Controlled.sol";
import "openzeppelin-solidity/contracts/drafts/ERC20Snapshot.sol";

contract StakingPoolDAO is StakingPool, ERC20Snapshot, Controlled {

  enum VoteStatus {NONE, YES, NO}

  struct Proposal {
    address destination;
    uint value;
    bool executed;
    uint snapshotId;
    uint dateLimit;
    bytes data;
    bytes details; // Store proposal information here

    mapping(bool => uint) votes;
    mapping(address => VoteStatus) voters;
  }

  uint public proposalCount;
  mapping(uint => Proposal) public proposals;

  uint public proposalVoteLength = 13290; // ~2d.  Voting available during this period
  uint public proposalExpiration = 6640; // ~1d. Proposals should be executed up to 1 day after they have ended


  event NewProposal(uint indexed proposalId);
  event Vote(uint indexed proposalId, address indexed voter, VoteStatus indexed choice);
  event Execution(uint indexed proposalId);
  event ExecutionFailure(uint indexed proposalId);

  constructor (address _tokenAddress, uint _stakingPeriodLen) public
    StakingPool(_tokenAddress, _stakingPeriodLen) {
      changeController(address(uint160(address(this))));
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
        dateLimit: block.number + proposalVoteLength
    });

    proposalCount++;

    emit NewProposal(proposalId);
  }

  function vote(uint proposalId, bool choice) external {
    Proposal storage proposal = proposals[proposalId];

    require(proposal.dateLimit > block.number, "Proposal has already ended");

    VoteStatus vote = choice ? VoteStatus.YES : VoteStatus.NO;
    uint voterBalance = balanceOfAt(msg.sender, proposal.snapshotId);

    require(voterBalance > 0, "Not enough tokens at the moment of proposal creation");

    VoteStatus oldVote = proposal.voters[msg.sender];

    if(oldVote != VoteStatus.NONE){ // Reset
      proposal.votes[choice] -= voterBalance;
    }

    proposal.votes[choice] += voterBalance;
    proposal.voters[msg.sender] = vote;

    emit Vote(proposalId, msg.sender, vote);
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
    require(block.number > proposal.dateLimit, "Voting is still active");
    require(block.number <= proposal.dateLimit + proposalExpiration, "Proposal is already expired");
    require(proposal.votes[true] > proposal.votes[false], "Proposal wasn't approved");

    proposal.executed = true;

    bool result = external_call(proposal.destination, proposal.value, proposal.data.length, proposal.data);
    require(result, "Execution Failed");
    emit Execution(proposalId);
  }
}
