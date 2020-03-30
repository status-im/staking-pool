
/* solium-disable security/no-block-members */
/* solium-disable security/no-inline-assembly */
pragma solidity >=0.5.0 <0.6.0;

import "./StakingPool.sol";
import "./common/Controlled.sol";
import "@openzeppelin/contracts/drafts/ERC20Snapshot.sol";
import "@openzeppelin/contracts/GSN/GSNRecipient.sol";
import "@openzeppelin/contracts/GSN/IRelayHub.sol";

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

    mapping(bool => uint) cancelVotes;
    mapping(address => VoteStatus) cancelVoters;
  }

  uint public proposalCount;
  mapping(uint => Proposal) public proposals;

  uint public proposalVoteLength; // Voting available during this period
  uint public proposalExpirationLength; // Proposals should be executed up to some time after they have ended
  uint public proposalCancelLength; // Voting for canceling a proposal can be done up to some time after the approval was done

  uint public minimumParticipation;  // Minimum participation percentage with 2 decimals. 10000 == 100.00
  uint public minimumParticipationForCancel; // Minimum participation percentage with 2 decimals. Required to consider the call for cancel
  uint public minimumCancelApprovalPercentage; // Minimum percentage to consider a approved proposal as canceled. Uses 2 decimals

  event NewProposal(uint indexed proposalId);
  event Vote(uint indexed proposalId, address indexed voter, VoteStatus indexed choice);
  event CancelVote(uint indexed proposalId, address indexed voter, VoteStatus indexed choice);
  event Execution(uint indexed proposalId);
  event ExecutionFailure(uint indexed proposalId);

  /**
   * @dev constructor
   * @param _tokenAddress SNT token address
   * @param _stakingPeriodLen Length in blocks for the period where user will be able to stake SNT
   * @param _proposalVoteLength Length in blocks for the period where voting will be available for proposals
   * @param _proposalCancelLength Length in blocks for the period where a proposal can be voted for cancel
   * @param _proposalExpirationLength Length in blocks where a proposal must be executed after voting before it is considered expired
   * @param _minimumParticipation Percentage of participation required for a proposal to be considered valid
   * @param _minimumParticipationForCancel Percentage of participation required for a proposal to be considered canceled
   * @param _minimumCancelApprovalPercentage Cancel votes should reach this percentage of the votes done in the cancel period for a proposal to be considered canceled
   */
  constructor (
    address _tokenAddress,
    uint _stakingPeriodLen,
    uint _proposalVoteLength,
    uint _proposalCancelLength,
    uint _proposalExpirationLength,
    uint _minimumParticipation,
    uint _minimumParticipationForCancel,
    uint _minimumCancelApprovalPercentage
  ) public
    StakingPool(_tokenAddress, _stakingPeriodLen) {
      proposalVoteLength = _proposalVoteLength;
      proposalCancelLength = _proposalCancelLength;
      proposalExpirationLength = _proposalExpirationLength;
      minimumParticipation = _minimumParticipation;
      minimumParticipationForCancel = _minimumParticipationForCancel;
      minimumCancelApprovalPercentage = _minimumCancelApprovalPercentage;
  }

  /**
   * @dev Set voting period length in blocks. Can only be executed by the contract's controller
   * @param _newProposalVoteLength Length in blocks for the period where voting will be available for proposals
   */
  function setProposalVoteLength(uint _newProposalVoteLength) public onlyController {
    proposalVoteLength = _newProposalVoteLength;
  }

  /**
   * @dev Set length in blocks where a proposal can be voted for cancel. Can only be executed by the contract's controller
   * @param _proposalCancelLength Length in blocks where a proposal can be voted for cancel
   */
  function setProposalCancelLength(uint _proposalCancelLength) public onlyController {
    proposalCancelLength = _proposalCancelLength;
  }

  /**
   * @dev Set length in blocks where a proposal must be executed before it is considered as expired. Can only be executed by the contract's controller
   * @param _newProposalExpirationLength Length in blocks where a proposal must be executed after voting before it is considered expired
   */
  function setProposalExpirationLength(uint _newProposalExpirationLength) public onlyController {
    proposalExpirationLength = _newProposalExpirationLength;
  }

  /**
   * @dev Set minimum participation percentage for proposals to be considered valid. Can only be executed by the contract's controller
   * @param _newMinimumParticipation Percentage of participation required for a proposal to be considered valid
   */
  function setMinimumParticipation(uint _newMinimumParticipation) public onlyController {
    minimumParticipation = _newMinimumParticipation;
  }

  /**
   * @dev Set minimum participation percentage for cancels to be considered valid. Can only be executed by the contract's controller
   * @param _minimumParticipationForCancel Percentage of participation required for a proposal to be considered valid
   */
  function setMinimumParticipationForCancel(uint _minimumParticipationForCancel) public onlyController {
    minimumParticipationForCancel = _minimumParticipationForCancel;
  }

  /**
   * @dev Set minimum percentage of votes for a proposal to be considered canceled
   * @param _minimumCancelApprovalPercentage Cancel votes should reach this percentage of the votes done in the cancel period for a proposal to be considered canceled   */
  function setMinimumCancelApprovalPercentage(uint _minimumCancelApprovalPercentage) public onlyController {
    minimumCancelApprovalPercentage = _minimumCancelApprovalPercentage;
  }

  /**
   * @notice Adds a new proposal
   * @param _destination Transaction target address
   * @param _value Transaction ether value
   * @param _data Transaction data payload
   * @param _details Proposal details
   * @return Returns proposal ID
   */
  function addProposal(address _destination, uint _value, bytes calldata _data, bytes calldata _details) external returns (uint proposalId)
  {
    require(balanceOf(msg.sender) > 0, "Token balance is required to perform this operation");

    assert(_destination != address(0));

    proposalId = proposalCount;
    proposals[proposalId] = Proposal({
        destination: _destination,
        value: _value,
        data: _data,
        executed: false,
        snapshotId: snapshot(),
        details: _details,
        voteEndingBlock: block.number + proposalVoteLength
    });

    proposalCount++;

    emit NewProposal(proposalId);
  }

  /**
   * @notice Vote for a proposal
   * @param _proposalId Id of the proposal to vote
   * @param _choice True for voting yes, False for no
   */
  function vote(uint _proposalId, bool _choice) external {
    Proposal storage proposal = proposals[_proposalId];

    require(proposal.voteEndingBlock > block.number, "Proposal voting has already ended");

    address sender = _msgSender();

    uint voterBalance = balanceOfAt(sender, proposal.snapshotId);
    require(voterBalance > 0, "Not enough tokens at the moment of proposal creation");

    VoteStatus oldVote = proposal.voters[sender];

    if(oldVote != VoteStatus.NONE){ // Reset
      bool oldChoice = oldVote == VoteStatus.YES ? true : false;
      proposal.votes[oldChoice] -= voterBalance;
    }

    VoteStatus enumVote = _choice ? VoteStatus.YES : VoteStatus.NO;

    proposal.votes[_choice] += voterBalance;
    proposal.voters[sender] = enumVote;

    lastActivity[sender] = block.timestamp;

    emit Vote(_proposalId, sender, enumVote);
  }

  /**
   * @notice Vote to cancel a proposal
   * @param _proposalId Id of the proposal to vote
   * @param _choice True for voting yes, False for no
   */
  function cancel(uint _proposalId, bool _choice) external {
    Proposal storage proposal = proposals[_proposalId];

    require(proposal.voteEndingBlock + proposalCancelLength > block.number, "Proposal cancel period has already ended");
    require(proposal.voteEndingBlock <= block.number, "Proposal cancel period has not started yet");

    address sender = _msgSender();

    uint voterBalance = balanceOfAt(sender, proposal.snapshotId);
    require(voterBalance > 0, "Not enough tokens at the moment of proposal creation");

    VoteStatus oldVote = proposal.cancelVoters[sender];

    if(oldVote != VoteStatus.NONE){ // Reset
      bool oldChoice = oldVote == VoteStatus.YES ? true : false;
      proposal.cancelVotes[oldChoice] -= voterBalance;
    }

    VoteStatus enumVote = _choice ? VoteStatus.YES : VoteStatus.NO;

    proposal.cancelVotes[_choice] += voterBalance;
    proposal.cancelVoters[sender] = enumVote;

    lastActivity[sender] = block.timestamp;

    emit CancelVote(_proposalId, sender, enumVote);
  }

  /**
   * @dev Execute a transaction
   * @param _destination Transaction target address.
   * @param _value Transaction ether value.
   * @param _dataLength Transaction data payload length
   * @param _data Transaction data payload.
   */
  function external_call(address _destination, uint _value, uint _dataLength, bytes memory _data) internal returns (bool) {
    bool result;
    assembly {
      let x := mload(0x40)   // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
      let d := add(_data, 32) // First 32 bytes are the padded length of data, so exclude that
      result := call(
        sub(gas, 34710),   // 34710 is the value that solidity is currently emitting
                            // It includes callGas (700) + callVeryLow (3, to pay for SUB) + callValueTransferGas (9000) +
                            // callNewAccountGas (25000, in case the destination address does not exist and needs creating)
        _destination,
        _value,
        d,
        _dataLength,        // Size of the input (in bytes) - this is what fixes the padding problem
        x,
        0                  // Output is ignored, therefore the output size is zero
      )
    }
    return result;
  }

  /**
   * @notice Execute an approved non-expired proposal
   * @param _proposalId Proposal ID.
   */
  function executeTransaction(uint _proposalId) public {
    Proposal storage proposal = proposals[_proposalId];

    require(proposal.executed == false, "Proposal already executed");
    require(block.number > proposal.voteEndingBlock + proposalCancelLength, "Voting is still active");
    require(block.number <= proposal.voteEndingBlock + proposalCancelLength + proposalExpirationLength, "Proposal is already expired");
    
    require(proposal.votes[true] > proposal.votes[false], "Proposal wasn't approved");

    uint totalParticipation = ((proposal.votes[true] + proposal.votes[false]) * 10000) / totalSupply();
    require(totalParticipation >= minimumParticipation, "Did not meet the minimum required participation");

    uint totalCancelVotes = proposal.cancelVotes[true] + proposal.cancelVotes[false];
    uint totalCancelParticipation = (totalCancelVotes * 10000) / totalSupply();

    if(totalCancelVotes > 0){
      uint cancelApprovalPercentage = (proposal.cancelVotes[false] * 10000) / totalCancelVotes;
      require(totalCancelParticipation < minimumParticipationForCancel &&
            cancelApprovalPercentage < minimumCancelApprovalPercentage, "Proposal was canceled");
    }

    proposal.executed = true;

    bool result = external_call(proposal.destination, proposal.value, proposal.data.length, proposal.data);
    require(result, "Execution Failed");
    emit Execution(_proposalId);
  }

  /**
   * @notice Get the number of votes for a proposal choice
   * @param _proposalId Proposal ID
   * @param _choice True for voting yes, False for no
   * @return Number of votes for the selected choice
   */
  function votes(uint _proposalId, bool _choice) public view returns (uint) {
    return proposals[_proposalId].votes[_choice];
  }

  /**
   * @notice Get the vote of an account
   * @param _account Account to obtain the vote from
   * @param _proposalId Proposal ID
   * @return Vote cast by an account
   */
  function voteOf(address _account, uint _proposalId) public view returns (VoteStatus) {
    return proposals[_proposalId].voters[_account];
  }

  /**
   * @notice Check if a proposal is approved or not
   * @param _proposalId Proposal ID
   * @return approved Indicates if the proposal was approved or not
   * @return executed Indicates if the proposal was executed or not
   */
  function isProposalApproved(uint _proposalId) public view returns (bool approved, bool executed){
    Proposal storage proposal = proposals[_proposalId];

  ///////////////////////////////
  // TODO
  ///////////////////////////////

    uint totalParticipation = ((proposal.votes[true] + proposal.votes[false]) * 10000) / totalSupply();
    if(block.number <= proposal.voteEndingBlock || totalParticipation < minimumParticipation) {
      approved = false;
    } else {
      approved = proposal.votes[true] > proposal.votes[false];
    }
    executed = proposal.executed;
  }

  function() external payable {
    //
  }

  // ========================================================================
  // Gas station network

  enum GSNErrorCodes {
    FUNCTION_NOT_AVAILABLE,
    HAS_ETH_BALANCE,
    GAS_PRICE,
    TRX_TOO_SOON,
    ALREADY_VOTED,
    NO_TOKEN_BALANCE
  }

  bytes4 constant VOTE_SIGNATURE = bytes4(keccak256("vote(uint256,bool)"));
  bytes4 constant CANCEL_SIGNATURE = bytes4(keccak256("cancel(uint256,bool)"));

  /**
   * @dev Function returning if we accept or not the relayed call (do we pay or not for the gas)
   * @param from Address of the buyer getting a free transaction
   * @param encodedFunction Function that will be called on the Escrow contract
   * @param gasPrice Gas price
   * @dev relay and transaction_fee are useless in our relay workflow
   */
  function acceptRelayedCall(
      address /*relay*/,
      address from,
      bytes calldata encodedFunction,
      uint256 /*transactionFee*/,
      uint256 gasPrice,
      uint256 /*gasLimit*/,
      uint256 /*nonce*/,
      bytes calldata /*approvalData*/,
      uint256 /*maxPossibleCharge*/
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

  /**
   * @dev Evaluates if the sender conditions are valid for relaying a escrow transaction
   * @param _from Sender
   * @param _gasPrice Gas Price
   * @param _functionSignature Function Signature
   * @param _proposalId Proposal ID
   */
  function _evaluateConditions(
    address _from,
    bytes4 _functionSignature,
    uint _proposalId,
    uint _gasPrice
  ) internal view returns (uint256, bytes memory) {
    if(_functionSignature != VOTE_SIGNATURE || _functionSignature != CANCEL_SIGNATURE) return _rejectRelayedCall(uint256(GSNErrorCodes.FUNCTION_NOT_AVAILABLE));

    Proposal storage proposal = proposals[_proposalId];

    if(balanceOfAt(_from, proposal.snapshotId) == 0) return _rejectRelayedCall(uint256(GSNErrorCodes.NO_TOKEN_BALANCE));

    if(_gasPrice > 20000000000) return _rejectRelayedCall(uint256(GSNErrorCodes.GAS_PRICE)); // 20 gwei

    if((lastActivity[_from] + 15 minutes) > block.timestamp) return _rejectRelayedCall(uint256(GSNErrorCodes.TRX_TOO_SOON));

    if(proposal.voters[_from] != VoteStatus.NONE) return _rejectRelayedCall(uint256(GSNErrorCodes.ALREADY_VOTED));

    return _approveRelayedCall();
  }

  mapping(address => uint) public lastActivity;

  /**
   * @dev Function executed before the relay. Unused by us
   */
  function _preRelayedCall(bytes memory context) internal returns (bytes32) {
  }

  /**
   * @dev Function executed after the relay. Unused by us
   */
  function _postRelayedCall(bytes memory context, bool, uint256 actualCharge, bytes32) internal {
  }

  /**
   * @notice Withdraw the ETH used for relay trxs
   * @dev Only contract owner can execute this function
   */
  function withdraw() external onlyController {
    IRelayHub rh = IRelayHub(getHubAddr());
    uint balance = rh.balanceOf(address(this));
    _withdrawDeposits(balance, msg.sender);
  }

  /**
   * @notice Set gas station network hub address
   * @dev Only contract owner can execute this function
   * @param _relayHub New relay hub address
   */
  function setRelayHubAddress(address _relayHub) external onlyController {
    _upgradeRelayHub(_relayHub);
  }

}
