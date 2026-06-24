# Réponses théoriques — BilletChain

---

## Q1 — Fondamentaux

Un smart contract tourne sur tous les nœuds du réseau en même temps, et ils doivent tous
arriver au même résultat. Si le contrat pouvait appeler une API externe, chaque nœud
obtiendrait une valeur différente selon le moment où il l'appelle, ce qui casserait le
consensus.

C'est pour ça qu'on utilise un oracle : c'est un service tiers qui publie la donnée
(le taux de change) directement sur la blockchain via une transaction. Le contrat lit
ensuite cette valeur comme n'importe quelle autre donnée on-chain.

---

## Q2 — Cryptographie

Quand un utilisateur envoie une transaction, il la signe avec sa clé privée. Ça prouve
que c'est bien lui qui a autorisé l'opération.

Le réseau peut vérifier ça sans connaître la clé privée grâce à la cryptographie
asymétrique : à partir de la signature et du message, on peut retrouver la clé publique
(et donc l'adresse) de l'émetteur, mais on ne peut pas faire l'inverse (retrouver la
clé privée à partir de la clé publique).

---

## Q3 — Tokens

Les billets sont non fongibles : la place A15 n'est pas la même chose que la place B03,
elles ne sont pas interchangeables. ERC-721 est donc le bon standard car chaque token
est unique et identifié par un `tokenId`.

ERC-20 serait pertinent si on vendait par exemple des "tokens de boisson" utilisables
au bar de la salle : peu importe lequel tu as, ils valent tous la même chose.

---

## Q4 — Sécurité

**1. La réentrance**
Dans `withdraw()`, on envoie des ETH à l'utilisateur. Un contrat malveillant pourrait
rappeler `withdraw()` avant que le premier appel se termine pour vider les fonds.
On s'en protège en remettant le solde à zéro **avant** d'envoyer les ETH, et en
utilisant `nonReentrant` d'OpenZeppelin.

**2. Oracle périmé**
Si l'oracle tombe en panne, le taux de change ne serait plus à jour. On vérifie donc
que la donnée a été mise à jour il y a moins d'une heure (`MAX_STALENESS = 1 hours`),
sinon on rejette la transaction avec `StaleOracle`.

---

## Q5 — Gas

**1. `calldata` dans `countForSale`**
On passe le tableau en `calldata` au lieu de `memory`. Ça évite de copier les données
en mémoire, ce qui coûte moins de gas, surtout si le tableau est grand.

**2. Variables `immutable`**
Les variables qui ne changent pas (`totalTickets`, `ticketPriceEur`, etc.) sont
déclarées `immutable`. Elles sont stockées dans le bytecode et non dans le storage,
donc les lire coûte beaucoup moins cher qu'un `SLOAD` classique.

