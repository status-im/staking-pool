// /*global contract, config, it, assert, artifacts*/
let StakingPoolDAO = artifacts.require('StakingPoolDAO');
const SNT = artifacts.require('SNT');

let iuri, jonathan, richard, michael, pascal, eric, andre;
const VoteStatus = {
  NONE: 0,
  YES: 1,
  NO: 2
};

// For documentation please see https://embark.status.im/docs/contracts_testing.html
config({
  contracts: {
    deploy:
      {
        "MiniMeToken": {"deploy": false},
        "MiniMeTokenFactory": {},
        "SNT": {
          "instanceOf": "MiniMeToken",
          "args": [
            "$MiniMeTokenFactory",
            "0x0000000000000000000000000000000000000000",
            0,
            "TestMiniMeToken",
            18,
            "STT",
            true
          ]
        },
        "StakingPoolDAO": {
          "deploy": false,
          "args": ["$SNT"]
        }
      }
  }
}, (_err, accounts) => {
  iuri = accounts[0];
  jonathan = accounts[1];
  richard = accounts[2];
  pascal = accounts[3];
  michael = accounts[4];
  eric = accounts[5];
  andre = accounts[6];
});

// TODO: add asserts for balances

let StakingPool;

contract("StakingPoolDAO", function () {
  this.timeout(0);

  before(async () => {
    // distribute SNT
    await SNT.methods.generateTokens(iuri, "10000000000").send({from: iuri});
    await SNT.methods.generateTokens(jonathan, "10000000000").send({from: iuri});
    await SNT.methods.generateTokens(richard, "10000000000").send({from: iuri});
    await SNT.methods.generateTokens(pascal, "10000000000").send({from: iuri});
    await SNT.methods.generateTokens(michael, "10000000000").send({from: iuri});
    await SNT.methods.generateTokens(eric, "10000000000").send({from: iuri});


    // Deploy Staking Pool
    StakingPool = await StakingPoolDAO.deploy({ arguments: [SNT.options.address, 100, 20, 10, 0] }).send();
    const encodedCall = StakingPool.methods.stake("10000000000").encodeABI();

    await web3.eth.sendTransaction({from: iuri, to: StakingPool.options.address, value: "100000000000000000"});

    await SNT.methods.approveAndCall(StakingPool.options.address, "10000000000", encodedCall).send({from: iuri});
    await SNT.methods.approveAndCall(StakingPool.options.address, "10000000000", encodedCall).send({from: jonathan});
    await SNT.methods.approveAndCall(StakingPool.options.address, "10000000000", encodedCall).send({from: richard});
    await SNT.methods.approveAndCall(StakingPool.options.address, "10000000000", encodedCall).send({from: pascal});
    await SNT.methods.approveAndCall(StakingPool.options.address, "10000000000", encodedCall).send({from: michael});
    await SNT.methods.approveAndCall(StakingPool.options.address, "10000000000", encodedCall).send({from: eric});

    // Mine 100 blocks
    for(let i = 0; i < 100; i++){
      await mineAtTimestamp(12345678);
    }
  })

  describe("contract functionality", () => {
    it("contract should be owned by itself", async () => {
      const controller = await StakingPool.methods.controller().call();
      assert.strictEqual(controller, StakingPool.options.address);
    });
  });

  describe("proposal creation", () => {
    it("non token holders can not submit proposals", async () => {
      const toSend = StakingPool.methods.addProposal(andre, 1, "0x", "0x");
      await assert.reverts(toSend, {from: andre}, "Returned error: VM Exception while processing transaction: revert Token balance is required to perform this operation");
    });

    it("token holders can create proposals", async () => {
      const receipt = await StakingPool.methods.addProposal(richard, 1, "0x", "0x").send({from: richard});
      assert.eventEmitted(receipt, 'NewProposal');
    });
  });

  describe("voting", () => {
    before(async () => {
      const balance = await StakingPool.methods.balanceOf(jonathan).call();
      await StakingPool.methods.transfer(eric, balance).send({from: jonathan});
    });

    let proposalId;
    beforeEach(async () => {
      const receipt = await StakingPool.methods.addProposal(richard, 1, "0x", "0x").send({from: richard});
      proposalId = receipt.events.NewProposal.returnValues.proposalId;
    });

    it("only those having balance can vote on a proposal", async () => {
      const toSend = StakingPool.methods.vote(proposalId, true);
      await assert.reverts(toSend, {from: jonathan}, "Returned error: VM Exception while processing transaction: revert Not enough tokens at the moment of proposal creation");
      await StakingPool.methods.vote(proposalId, true).send({from: eric});
    });

    it("accounts can vote more than once and results are affected accordingly", async () => {
      let votesY = await StakingPool.methods.votes(proposalId, true).call(); 
      let votesN = await StakingPool.methods.votes(proposalId, true).call();
      let myVote = await StakingPool.methods.voteOf(richard, proposalId).call();

      assert.strictEqual(votesY, "0");
      assert.strictEqual(votesN, "0");

      let receipt = await StakingPool.methods.vote(proposalId, true).send({from: richard});

      votesY = await StakingPool.methods.votes(proposalId, true).call(); 
      votesN = await StakingPool.methods.votes(proposalId, false).call();
      

      assert.strictEqual(votesY, "10000000000");
      assert.strictEqual(votesN, "0");

      receipt = await StakingPool.methods.vote(proposalId, false).send({from: richard});

      votesY = await StakingPool.methods.votes(proposalId, true).call(); 
      votesN = await StakingPool.methods.votes(proposalId, false).call();
      
      assert.strictEqual(votesY, "0");
      assert.strictEqual(votesN, "10000000000");
    });

    it("voting is only valid during the period it is active", async () => {
      const toSend = await StakingPool.methods.vote(proposalId, false);

      await toSend.send({from: richard});

      // Mine 20 blocks
      for(let i = 0; i < 20; i++){
        await mineAtTimestamp(12345678);
      }

      await assert.reverts(toSend, {from: richard}, "Returned error: VM Exception while processing transaction: revert Proposal has already ended");
    });

    it("check that vote result matches what was voted", async () => {
      await StakingPool.methods.vote(proposalId, true).send({from: eric});
      await StakingPool.methods.vote(proposalId, true).send({from: michael});
      await StakingPool.methods.vote(proposalId, false).send({from: pascal});
      await StakingPool.methods.vote(proposalId, false).send({from: richard});

      // Mine 20 blocks
      for(let i = 0; i < 20; i++){
        await mineAtTimestamp(12345678);
      }

      let votesY = await StakingPool.methods.votes(proposalId, true).call(); 
      let votesN = await StakingPool.methods.votes(proposalId, false).call();

      const result = await StakingPool.methods.isProposalApproved(proposalId).call();
      
      assert.strictEqual(votesY, "30000000000");
      assert.strictEqual(votesN, "20000000000");
      assert.strictEqual(result.approved, true);
      assert.strictEqual(result.executed, false);
    });
  });

  describe("proposal execution", () => {
    let proposalId;
    beforeEach(async () => {
      const receipt = await StakingPool.methods.addProposal("0x00000000000000000000000000000000000000AA", 12345, "0x", "0x").send({from: richard});
      proposalId = receipt.events.NewProposal.returnValues.proposalId;
    });

    it("active voting proposals cant be executed", async () => {
      await StakingPool.methods.vote(proposalId, true).send({from: richard});
      const toSend = StakingPool.methods.executeTransaction(proposalId);
      await assert.reverts(toSend, {from: richard}, "Returned error: VM Exception while processing transaction: revert Voting is still active");
    });

    it("unapproved proposals cant be executed", async () => {
      await StakingPool.methods.vote(proposalId, false).send({from: richard});
      
      // Mine 20 blocks
      for(let i = 0; i < 20; i++){
        await mineAtTimestamp(12345678);
      }

      const toSend = StakingPool.methods.executeTransaction(proposalId);
      await assert.reverts(toSend, {from: iuri}, "Returned error: VM Exception while processing transaction: revert Proposal wasn't approved");
    });

    it("approved proposals can be executed", async () => {
      await StakingPool.methods.vote(proposalId, true).send({from: richard});
      
      // Mine 20 blocks
      for(let i = 0; i < 20; i++){
        await mineAtTimestamp(12345678);
      }

      let result = await StakingPool.methods.isProposalApproved(proposalId).call();
      assert.strictEqual(result.approved, true);
      assert.strictEqual(result.executed, false);
      
      const receipt = await StakingPool.methods.executeTransaction(proposalId).send({from: iuri});

      const destinationBalance = await web3.eth.getBalance("0x00000000000000000000000000000000000000AA");
      assert.strictEqual(destinationBalance, "12345");

      result = await StakingPool.methods.isProposalApproved(proposalId).call();
      assert.strictEqual(result.executed, true);
    });

    it("approved proposals can't be executed twice", async () => {
      await StakingPool.methods.vote(proposalId, true).send({from: richard});

      // Mine 20 blocks
      for(let i = 0; i < 20; i++){
        await mineAtTimestamp(12345678);
      }

      await StakingPool.methods.executeTransaction(proposalId).send({from: iuri});
      await assert.reverts(StakingPool.methods.executeTransaction(proposalId), {from: iuri}, "Returned error: VM Exception while processing transaction: revert Proposal already executed");
    });

    it("approved proposals can't be executed after they expire", async () => {
      await StakingPool.methods.vote(proposalId, true).send({from: richard});
      // Mine 40 blocks
      for(let i = 0; i < 40; i++){
        await mineAtTimestamp(12345678);
      }
      await assert.reverts(StakingPool.methods.executeTransaction(proposalId), {from: iuri}, "Returned error: VM Exception while processing transaction: revert Proposal is already expired");
    });


    it("proposals can execute contract functions", async () => {
      const initialBalance = await SNT.methods.balanceOf("0xAA000000000000000000000000000000000000AA").call();
      assert.strictEqual(initialBalance, "0");

      const encodedCall = SNT.methods.transfer("0xAA000000000000000000000000000000000000AA", "12345").encodeABI();
      const receipt = await StakingPool.methods.addProposal(SNT.options.address, 0, encodedCall, "0x").send({from: richard});
      proposalId = receipt.events.NewProposal.returnValues.proposalId;

      await StakingPool.methods.vote(proposalId, true).send({from: richard});

      // Mine 20 blocks
      for(let i = 0; i < 20; i++){
        await mineAtTimestamp(12345678);
      }

      await StakingPool.methods.executeTransaction(proposalId).send({from: iuri});

      const finalBalance = await SNT.methods.balanceOf("0xAA000000000000000000000000000000000000AA").call();
      assert.strictEqual(finalBalance, "12345");
    });

    it("set minimum participation", async () => {
      // Change minimum participation
      const encodedCall = StakingPool.methods.setMinimumParticipation("5000").encodeABI();
      const receipt = await StakingPool.methods.addProposal(StakingPool.options.address, 0, encodedCall, "0x").send({from: richard});
      proposalId = receipt.events.NewProposal.returnValues.proposalId;

      await StakingPool.methods.vote(proposalId, true).send({from: richard});

      // Mine 20 blocks
      for(let i = 0; i < 20; i++){
        await mineAtTimestamp(12345678);
      }

      await StakingPool.methods.executeTransaction(proposalId).send({from: iuri});

      const minimumParticipation = await StakingPool.methods.minimumParticipation().call();
      assert.strictEqual(minimumParticipation, "5000");
    });

    it("requires a minimum participation to execute a proposal", async () => {
      const encodedCall = SNT.methods.transfer("0xAA000000000000000000000000000000000000BB", "12345").encodeABI();
      const receipt = await StakingPool.methods.addProposal(SNT.options.address, 0, encodedCall, "0x").send({from: richard});
      proposalId = receipt.events.NewProposal.returnValues.proposalId;

      await StakingPool.methods.vote(proposalId, true).send({from: richard});

      // Mine 20 blocks
      for(let i = 0; i < 20; i++){
        await mineAtTimestamp(12345678);
      }

      await assert.reverts(StakingPool.methods.executeTransaction(proposalId), {from: iuri}, "Returned error: VM Exception while processing transaction: revert Did not meet the minimum required participation");
    });

    it("proposal can be executed if it meets the minimum participation", async () => {
      const encodedCall = SNT.methods.transfer("0xAA000000000000000000000000000000000000BB", "12345").encodeABI();
      const receipt = await StakingPool.methods.addProposal(SNT.options.address, 0, encodedCall, "0x").send({from: richard});
      proposalId = receipt.events.NewProposal.returnValues.proposalId;

      await StakingPool.methods.vote(proposalId, true).send({from: iuri});
      await StakingPool.methods.vote(proposalId, true).send({from: richard});
      await StakingPool.methods.vote(proposalId, true).send({from: pascal});

      // Mine 20 blocks
      for(let i = 0; i < 20; i++){
        await mineAtTimestamp(12345678);
      }

      await StakingPool.methods.executeTransaction(proposalId).send({from: iuri});
    });
  });
});
