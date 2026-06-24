# BilletChain

Projet réalisé dans le cadre de mon M2 pour la matière Blockchain.

BilletChain est un smart contract de vente et gestion de billets de concert sur la blockchain Ethereum. Chaque billet est un NFT (ERC-721), le prix est affiché en euros et converti en ETH via un oracle Chainlink, et les détenteurs peuvent revendre leurs billets dans la limite de 110% du prix d'achat initial.

## Fonctionnalités

- Vente initiale de billets (prix calculé dynamiquement via oracle ETH/EUR)
- Marché secondaire avec plafond de revente à 110%
- Retrait des fonds en pull payment (sécurisé contre la réentrance)
- Frais de plateforme de 5% sur les reventes
- Remboursement automatique du trop-perçu
- Pause d'urgence réservée à l'organisateur

## Stack

- Solidity 0.8.35
- Foundry (Forge, Anvil)
- OpenZeppelin Contracts

## Lancer les tests

```shell
forge test
```

## Déploiement (Sepolia)

```shell
forge create src/BilletChain.sol:BilletChain \
  --rpc-url $SEPOLIA_RPC \
  --private-key $DEPLOYER_KEY \
  --constructor-args <totalTickets> <ticketPriceEur> <adresse_oracle_chainlink>
```
