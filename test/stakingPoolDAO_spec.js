// /*global contract, config, it, assert, artifacts*/
let StakingPoolDAO = artifacts.require('StakingPoolDAO');
const SNT = artifacts.require('SNT');

let iuri, jonathan, richard, michael, pascal, eric, andre;

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

contract("StakingPool", function () {
  this.timeout(0);

  before(async () => {
    // distribute SNT
    await SNT.methods.generateTokens(iuri, "10000000000").send({from: iuri});
    await SNT.methods.generateTokens(jonathan, "10000000000").send({from: iuri});
    await SNT.methods.generateTokens(richard, "10000000000").send({from: iuri});
    await SNT.methods.generateTokens(pascal, "10000000000").send({from: iuri});
    await SNT.methods.generateTokens(michael, "10000000000").send({from: iuri});
    await SNT.methods.generateTokens(eric, "10000000000").send({from: iuri});
    await SNT.methods.generateTokens(eric, "10000000000").send({from: iuri});


    // Deploy Staking Pool
    StakingPool = await StakingPoolDAO.deploy({ arguments: [SNT.options.address, 100] }).send();
    const encodedCall = StakingPool.methods.stake("10000000000").encodeABI();

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
      await StakingPool.methods.transfer(richard, balance).send({from: jonathan});
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

    // TODO: check that you can vote more than once, and results are affected accordingly
    // TODO: check that voting is valid only for some period
    // TODO: check that vote result matches what was voted
  });

  describe("proposal execution", () => {
    // TODO: check that active voting proposals cant be executed
    // TODO: check that unapproved proposals cant be executed
    // TODO: check that approved proposals can be executed
    // TODO: check that proposals cannot be executed after they expire
    // TODO: check that proposals do transfer of value
    // TODO: check that proposals do contract method execution
  })

});
