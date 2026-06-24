# Note de déploiement — BilletChain

On déploierait sur **Sepolia**, le testnet Ethereum principal, car Chainlink y propose
des price feeds actifs dont ETH/EUR.

Valeurs passées au constructeur :
- `totalTickets` : nombre de places de la salle (ex. 500)
- `ticketPriceEur` : prix en euros (ex. 50)
- `oracle` : adresse du price feed ETH/EUR Chainlink sur Sepolia, disponible sur
  docs.chain.link → Price Feeds → Sepolia

```bash
forge create src/BilletChain.sol:BilletChain \
  --rpc-url $SEPOLIA_RPC \
  --private-key $DEPLOYER_KEY \
  --constructor-args 500 50 <adresse_oracle>
```
