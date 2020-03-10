module.exports = {
  // applies to all environments
  default: {
    enabled: true,
    client: "geth"
  },

  // default environment, merges with the settings in default
  // assumed to be the intended environment by `embark run` and `embark blockchain`
  development: {
    client: "ganache-cli",
    clientConfig: {
      miningMode: 'dev'
    }
  },

  // merges with the settings in default
  // used with "embark run privatenet" and/or "embark blockchain privatenet"
  privatenet: {
    clientConfig: {
      miningMode: 'auto'
    },
    datadir: ".embark/privatenet/datadir",
    accounts: [
      {
        nodeAccounts: true,
        password: "config/privatenet/password" // Password to unlock the account
      }
    ]
  }
};
