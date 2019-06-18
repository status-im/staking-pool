// /*global contract, config, it, assert*/
const StakingPool = require('Embark/contracts/StakingPool');

let iuri, jonathan, richard;

// For documentation please see https://embark.status.im/docs/contracts_testing.html
config({
  contracts: {
    "StakingPool": {
    }
  }
}, (_err, accounts) => {
  iuri = accounts[0];
  jonathan = accounts[1];
  richard = accounts[2];
});

// TODO: add asserts for balances

contract("StakingPool", function () {
  this.timeout(0);

  describe("initial state", () => {
    it("initial exchangeRate should be 1", async function () {
      let rate = await StakingPool.methods.exchangeRate(0).call();
      assert.strictEqual(rate, "1000000000000000000");
    });

    it("initial token supply should be 0", async function () {
      let rate = await StakingPool.methods.totalSupply().call();
      assert.strictEqual(rate, "0");
    });

    it("initial balance should be 0", async function () {
      let rate = await web3.eth.getBalance(StakingPool.address);
      assert.strictEqual(rate, "0");
    });
  })

  describe("depositing before contributions", () => {
    before("deposit 11 ETH", async () => {
      await StakingPool.methods.deposit().send({value: "11000000000000000000", from: jonathan})
    })

    it("exchangeRate should remain 1", async function () {
      let rate = await StakingPool.methods.exchangeRate(0).call();
      assert.strictEqual(rate, "1000000000000000000");
    });

    it("token supply should be 12", async function () {
      let rate = await StakingPool.methods.totalSupply().call();
      assert.strictEqual(rate, "11000000000000000000");
    });

    it("balance should be 12", async function () {
      let rate = await web3.eth.getBalance(StakingPool.address);
      assert.strictEqual(rate, "11000000000000000000");
    });
  });

  describe("2nd person depositing before contributions", () => {
    before("deposit 5 ETH", async () => {
      await StakingPool.methods.deposit().send({value: "5000000000000000000", from: iuri})
    })

    it("exchangeRate should remain 1", async function () {
      let rate = await StakingPool.methods.exchangeRate(0).call();
      assert.strictEqual(rate, "1000000000000000000");
    });

    it("token supply should be 17", async function () {
      let rate = await StakingPool.methods.totalSupply().call();
      assert.strictEqual(rate, "16000000000000000000");
    });

    it("balance should be 17", async function () {
      let rate = await web3.eth.getBalance(StakingPool.address);
      assert.strictEqual(rate, "16000000000000000000");
    });
  });

  describe("contributions", () => {
    before("contribute 10 ETH", async () => {
      await web3.eth.sendTransaction({value: "10000000000000000000", to: StakingPool.address})
    })

    it("exchangeRate should increase", async function () {
      let rate = await StakingPool.methods.exchangeRate(0).call();
      assert.strictEqual(rate, "1625000000000000000");
    });

    it("token supply should remain at 17", async function () {
      let rate = await StakingPool.methods.totalSupply().call();
      assert.strictEqual(rate, "16000000000000000000");
    });

    it("balance should be 27", async function () {
      let rate = await web3.eth.getBalance(StakingPool.address);
      assert.strictEqual(rate, "26000000000000000000");
    });
  });

  describe("withdrawing 5 tokens after contributions", () => {
    before("withdraw 5 tokens", async () => {
      await StakingPool.methods.withdraw("5000000000000000000").send({from: jonathan})
    })

    it("exchangeRate should remain the same", async function () {
      let rate = await StakingPool.methods.exchangeRate(0).call();
      assert.strictEqual(rate, "1625000000000000000");
    });

    it("token supply should decrease to 11", async function () {
      let rate = await StakingPool.methods.totalSupply().call();
      assert.strictEqual(rate, "11000000000000000000");
    });

    it("balance should decrease by correct exchange rate", async function () {
      let rate = await web3.eth.getBalance(StakingPool.address);
      // 5000000000000000000 tokens x 1.625 rate
      // => 8125000000000000000 ETH
      // 26000000000000000000 - 8125000000000000000 = 17875000000000000000
      assert.strictEqual(rate, "17875000000000000000");
    });
  });

  describe("depositing after contributions", () => {
    before("deposit 8 ETH", async () => {
      await StakingPool.methods.deposit().send({value: "8000000000000000000", from: richard})
    })

    it("exchangeRate should remain the same", async function () {
      let rate = await StakingPool.methods.exchangeRate(0).call();
      assert.strictEqual(rate, "1625000000000000000");
    });

    it("token supply should increase by correct exchange rate", async function () {
      let rate = await StakingPool.methods.totalSupply().call();
      assert.strictEqual(rate, "15923076923076923077");
    });

    it("balance should increase", async function () {
      let rate = await web3.eth.getBalance(StakingPool.address);
      // 17875000000000000000 + 8000000000000000000
      assert.strictEqual(rate, "25875000000000000000");
    });
  });

});