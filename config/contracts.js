module.exports = {
  default: {
    dappConnection: [
      "$EMBARK",
      "$WEB3",
      "ws://localhost:8546",
      "http://localhost:8545"
    ],

    gas: "auto",

    strategy: 'explicit',

    deploy: {
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
      "StakingPool": {
        "args": ["$SNT"]
      }
    }
  },

  development: {
    dappConnection: [
      "$EMBARK",
      "ws://localhost:8546",
      "http://localhost:8545",
      "$WEB3"
    ]
  }
};
