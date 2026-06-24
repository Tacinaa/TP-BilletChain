# To-do — BilletChain

## 0. Setup du projet
- [x] Initialiser un projet Foundry (`forge init`) — Foundry v1.7.1, Solc 0.8.35
- [x] Vérifier que `forge build` et `forge test` tournent sur un projet vide
- [x] Installer OpenZeppelin (`lib/openzeppelin-contracts`) + remappings dans `foundry.toml`

---

## 1. Conception de l'architecture (avant de coder)
- [x] **1 contrat unique** (`BilletChain.sol`) — pas de séparation NFT/marketplace. Moins de surface d'attaque, pas d'appels cross-contrat, plus économe en gas.
- [x] **ERC-721** (OpenZeppelin) — billets non fongibles, chaque `tokenId` = une place identifiée.
- [x] **Oracle** : interface `IExchangeRateOracle` calquée sur Chainlink `AggregatorV3Interface` — `latestRoundData()` retourne le prix ETH/EUR (nb de EUR pour 1 ETH, 8 décimales). Prix en wei = `ticketPriceEur * 1e26 / ethPriceInEur`.
- [x] **Pull payment** — `mapping(address => uint256) pendingWithdrawals`, pas de push ETH. Élimine la réentrance sur les transferts.

### Structures de données retenues
```
uint256 public  totalTickets          // fixé au déploiement
uint256 public  ticketPriceEur        // prix nominal en euros (entier)
address public  organizer             // reçoit les ventes initiales
IExchangeRateOracle public oracle

mapping(uint256 => uint256) purchasePrice   // wei payé à l'achat initial (plafond revente)
mapping(uint256 => uint256) resalePrice     // 0 = pas en vente
mapping(address => uint256) pendingWithdrawals

uint256 private _nextTokenId          // auto-incrément
```

---

## 2. Interface Oracle (mock + réel)
- [x] Créer l'interface `IExchangeRateOracle` → `src/IExchangeRateOracle.sol`
- [x] Créer `MockOracle.sol` → `test/mocks/MockOracle.sol` (`setAnswer` + `setUpdatedAt` pour simuler un oracle périmé)
- [x] Vérification de fraîcheur dans `_getTicketPriceWei()` : `block.timestamp - updatedAt > MAX_STALENESS` → `revert StaleOracle()`

---

## 3. Smart contract principal — `BilletChain.sol`
- [x] Hériter d'**ERC-721** + `ReentrancyGuard` (OpenZeppelin)
- [x] Stocker à la création : `totalTickets`, `ticketPriceEur`, `oracle`, `organizer`
- [x] **Vente initiale** : `buyTicket()` — prix calculé via oracle, paiement exact, mint, mémorise `purchasePrice`, crédite `organizer`
- [x] **Mise en vente secondaire** : `listForResale(tokenId, price)` — vérif propriété, plafond 110 %, approbation contract requise
- [x] **Achat secondaire** : `buyResale(tokenId)` — paiement exact, re-vérif approbation, état avant transfert, crédite vendeur
- [x] **Retrait** : `withdraw()` — pull payment, checks-effects-interactions, `nonReentrant`
- [x] **Consultation gas-efficiente** : `countForSale(uint256[] calldata)` — `calldata` + `unchecked ++i`
- [x] **Events** : `TicketMinted`, `TicketListed`, `TicketSold`, `Withdrawn`
- [x] **Custom errors** : `SoldOut`, `WrongPayment`, `NotTicketOwner`, `PriceTooHigh`, `NotForSale`, `NotApproved`, `NothingToWithdraw`, `StaleOracle`, `InvalidOracleAnswer`

---

## 4. Sécurité — checklist avant de finir le contrat
- [x] **Réentrance** : `nonReentrant` sur `buyTicket`, `buyResale`, `withdraw` + état mis à jour avant tout `call`
- [x] **Contrôle d'accès** : `ownerOf(tokenId) != msg.sender` → revert dans `listForResale`
- [x] **Oracle périmé** : `MAX_STALENESS = 1 hours`, revert `StaleOracle`
- [x] **Paiement exact** : `msg.value != price` → `revert WrongPayment(expected, sent)`
- [x] **Plafond revente** : `purchasePrice[tokenId] * 110 / 100` — Solidity 0.8 protège l'overflow

---

## 5. Tests Foundry — `test/BilletChain.t.sol`
- [x] Setup : MockOracle déployé avec RATE=2000e8, WEI_PRICE=25e15 déduit
- [x] Test achat normal (happy path) + event `TicketMinted`
- [x] Test achat — paiement trop faible → `WrongPayment`
- [x] Test achat — paiement trop élevé → `WrongPayment`
- [x] Test achat — événement complet → `SoldOut`
- [x] Test oracle périmé → `StaleOracle` (via `vm.warp`)
- [x] Test oracle réponse invalide (0 et -1) → `InvalidOracleAnswer`
- [x] Test mise en vente — happy path + exact plafond 110 %
- [x] Test mise en vente — prix > 110 % → `PriceTooHigh`
- [x] Test mise en vente — non propriétaire → `NotTicketOwner`
- [x] Test mise en vente — sans approbation → `NotApproved`
- [x] Test achat secondaire — happy path + event `TicketSold`
- [x] Test achat secondaire — billet non listé → `NotForSale`
- [x] Test achat secondaire — mauvais paiement → `WrongPayment`
- [x] Test achat secondaire — approbation révoquée → `NotApproved`
- [x] Test retrait — organisateur récupère ses fonds
- [x] Test retrait — vendeur récupère ses fonds après revente
- [x] Test retrait — solde nul → `NothingToWithdraw`
- [x] Test `countForSale` — listing partiel, liste vide, aucun en vente
- [x] **(Bonus)** Fuzz test plafond 110 % — 256 runs, toujours revert au-dessus du cap

**Résultat : 25/25 tests verts**

---

## 6. Partie théorique
- [ ] Q1 — Déterminisme + impossibilité d'appeler une API depuis un contrat
- [ ] Q2 — Signature / clé privée / vérification sans révéler la clé
- [ ] Q3 — ERC-721 vs ERC-20, cas d'usage fongible
- [ ] Q4 — 2 vulnérabilités + protection dans votre code
- [ ] Q5 — 2 décisions concrètes de réduction de gas

---

## 7. Note de déploiement (½ page)
- [ ] Réseau de test : Sepolia (Chainlink y a des price feeds EUR/ETH)
- [ ] Valeurs passées au constructeur : `totalTickets`, `priceInEuros`, adresse oracle Chainlink
- [ ] Adresse du price feed : chercher sur `docs.chain.link` → Sepolia → EUR/ETH

---

## 8. Bonus (si temps restant)
- [ ] Frais de plateforme sur les reventes
- [ ] Remboursement du trop-perçu
- [ ] Pause d'urgence (`Pausable` OpenZeppelin)
- [ ] Fuzz test plafond 110 %
