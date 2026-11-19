const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  // Custom labels read as their English text.
  resolver: "<rootDir>/jest-mocks/labelResolver.js",
  moduleNameMapper: {
    ...jestConfig.moduleNameMapper,
    // Lightning modules sfdx-lwc-jest doesn't stub.
    "^lightning/modal$": "<rootDir>/jest-mocks/lightning/modal",
    "^lightning/illustration$": "<rootDir>/jest-mocks/lightning/illustration"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};
