// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/IExchangeRateOracle.sol";

/// Simule un oracle Chainlink ETH/EUR pour les tests.
/// Permet de contrôler le taux et le timestamp afin de tester
/// les cas nominaux et le cas "données périmées".
contract MockOracle is IExchangeRateOracle {
    int256  private _answer;
    uint256 private _updatedAt;

    constructor(int256 initialAnswer) {
        _answer    = initialAnswer;
        _updatedAt = block.timestamp;
    }

    function setAnswer(int256 answer) external {
        _answer    = answer;
        _updatedAt = block.timestamp;
    }

    /// Permet de simuler un oracle périmé en fixant manuellement le timestamp.
    function setUpdatedAt(uint256 updatedAt) external {
        _updatedAt = updatedAt;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        )
    {
        return (1, _answer, _updatedAt, _updatedAt, 1);
    }
}
