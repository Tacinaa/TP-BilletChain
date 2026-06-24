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
- [ ] Prévoir la vérification de **fraîcheur** du taux (timestamp périmé → rejet) — sera dans `BilletChain.sol`

---

## 3. Smart contract principal — `BilletChain.sol`
- [ ] Hériter d'**ERC-721** (OpenZeppelin)
- [ ] Stocker à la création : nombre total de billets, prix en euros, adresse oracle
- [ ] **Vente initiale** : `buyTicket()` — calcul prix en wei via oracle, paiement exact, mint NFT, mémoriser prix d'achat
- [ ] **Mise en vente secondaire** : `listForResale(tokenId, price)` — vérifier propriété, vérifier plafond 110 %, appeler `approve(address(this), tokenId)`
- [ ] **Achat secondaire** : `buyResale(tokenId)` — paiement exact, `transferFrom`, créditer vendeur (pull)
- [ ] **Retrait** : `withdraw()` — pull payment pattern, protection réentrance
- [ ] **Consultation gas-efficiente** : `countForSale(uint[] tokenIds)` — lecture pure, pas d'écriture
- [ ] Émettre les **events** : `TicketMinted`, `TicketListed`, `TicketSold`, `Withdrawn`
- [ ] Utiliser des **custom errors** (plus économes que `require("string")`)
- [ ] Ajouter `ReentrancyGuard` (OpenZeppelin) sur les fonctions qui bougent des fonds

---

## 4. Sécurité — checklist avant de finir le contrat
- [ ] **Réentrance** : `ReentrancyGuard` + pull payment (pas de call avant mise à jour d'état)
- [ ] **Contrôle d'accès** : seul le propriétaire peut lister, seul l'organisateur retire sa part
- [ ] **Oracle périmé** : vérifier `updatedAt` + seuil max (ex : 1h)
- [ ] **Paiement exact** : `msg.value != prixCalculé` → revert (pas de tolérance silencieuse)
- [ ] **Plafond revente** : calcul 110 % sans overflow (Solidity ≥ 0.8 protège, mais vérifier)

---

## 5. Tests Foundry — `test/BilletChain.t.sol`
- [ ] Setup : déployer avec MockOracle, fixer un taux
- [ ] Test achat normal (happy path)
- [ ] Test achat — paiement trop faible → revert
- [ ] Test achat — paiement trop élevé → revert
- [ ] Test achat — événement complet → revert
- [ ] Test mise en vente — prix > 110 % → revert
- [ ] Test mise en vente — non propriétaire → revert
- [ ] Test achat secondaire — billet non listé → revert
- [ ] Test retrait — vendeur récupère ses fonds
- [ ] Test retrait — solde nul → revert
- [ ] Test oracle périmé → revert
- [ ] Test `countForSale` — retourne le bon décompte
- [ ] **(Bonus)** Fuzz test : `listForResale(tokenId, price)` → price jamais > 110 %

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
