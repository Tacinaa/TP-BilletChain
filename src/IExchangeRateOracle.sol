// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IExchangeRateOracle {
    /// @return roundId        identifiant du round Chainlink
    /// @return answer         prix ETH/EUR avec 8 décimales (ex : 200000000000 = 2000 EUR/ETH)
    /// @return startedAt      timestamp de début du round
    /// @return updatedAt      timestamp de la dernière mise à jour (utilisé pour la vérification de fraîcheur)
    /// @return answeredInRound roundId du round où la réponse a été calculée
    function latestRoundData()
        external
        view
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        );
}
