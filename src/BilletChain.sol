// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IExchangeRateOracle.sol";

contract BilletChain is ERC721, ReentrancyGuard, Pausable {

    // ── Errors ───────────────────────────────────────────────────────────────
    error SoldOut();
    error WrongPayment(uint256 expected, uint256 sent);
    error NotTicketOwner();
    error PriceTooHigh(uint256 maxAllowed, uint256 requested);
    error NotForSale();
    error NotApproved();
    error NothingToWithdraw();
    error StaleOracle();
    error InvalidOracleAnswer();

    // ── Events ───────────────────────────────────────────────────────────────
    event TicketMinted(uint256 indexed tokenId, address indexed buyer,  uint256 priceWei);
    event TicketListed(uint256 indexed tokenId, address indexed seller, uint256 priceWei);
    event TicketSold  (uint256 indexed tokenId, address indexed buyer,  address indexed seller, uint256 priceWei);
    event Withdrawn   (address indexed account, uint256 amount);

    // ── Constants ────────────────────────────────────────────────────────────
    uint256 public constant MAX_STALENESS    = 1 hours;
    uint256 public constant RESALE_CAP_PCT   = 110;
    uint256 public constant PLATFORM_FEE_PCT = 5;     // frais de plateforme sur les reventes

    // ── Immutables ───────────────────────────────────────────────────────────
    uint256 public immutable totalTickets;
    uint256 public immutable ticketPriceEur; // prix nominal en euros entiers (ex : 50)
    address public immutable organizer;
    IExchangeRateOracle public immutable oracle;

    // ── Storage ──────────────────────────────────────────────────────────────
    uint256 private _nextTokenId;

    // tokenId => wei payé lors de l'achat initial (base du plafond, ne change jamais)
    mapping(uint256 => uint256) public purchasePrice;

    // tokenId => prix de revente en wei (0 = pas en vente)
    mapping(uint256 => uint256) public resalePrice;

    // adresse => solde retirable (pull payment)
    mapping(address => uint256) public pendingWithdrawals;

    // ── Constructor ──────────────────────────────────────────────────────────
    constructor(
        uint256 totalTickets_,
        uint256 ticketPriceEur_,
        address oracle_
    ) ERC721("BilletChain", "BILLET") {
        totalTickets   = totalTickets_;
        ticketPriceEur = ticketPriceEur_;
        oracle         = IExchangeRateOracle(oracle_);
        organizer      = msg.sender;
    }

    // ── Internal : calcul du prix en wei via l'oracle ────────────────────────
    function _getTicketPriceWei() internal view returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = oracle.latestRoundData();

        if (answer <= 0) revert InvalidOracleAnswer();

        // La fenêtre d'une heure rend la manipulation par un validateur (~12 s) négligeable.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp - updatedAt > MAX_STALENESS) revert StaleOracle();

        // answer = prix ETH/EUR avec 8 décimales (ex : 2000 EUR/ETH → 200_000_000_000)
        // priceInWei = ticketPriceEur * 1e18 / (answer / 1e8) = ticketPriceEur * 1e26 / answer
        // Le cast est sûr : answer > 0 est vérifié juste au-dessus.
        // forge-lint: disable-next-line(unsafe-typecast)
        return ticketPriceEur * 1e26 / uint256(answer);
    }

    // ── Pause d'urgence (organisateur uniquement) ────────────────────────────
    function pause() external {
        require(msg.sender == organizer, "not organizer");
        _pause();
    }

    function unpause() external {
        require(msg.sender == organizer, "not organizer");
        _unpause();
    }

    // ── Vente initiale ───────────────────────────────────────────────────────
    function buyTicket() external payable nonReentrant whenNotPaused {
        if (_nextTokenId >= totalTickets) revert SoldOut();

        uint256 price = _getTicketPriceWei();
        if (msg.value < price) revert WrongPayment(price, msg.value);

        uint256 tokenId = _nextTokenId;
        unchecked { ++_nextTokenId; }

        uint256 excess = msg.value - price;

        purchasePrice[tokenId] = price;
        pendingWithdrawals[organizer] += price;

        _safeMint(msg.sender, tokenId);
        emit TicketMinted(tokenId, msg.sender, price);

        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            require(ok, "Refund failed");
        }
    }

    // ── Marché secondaire : mise en vente ────────────────────────────────────
    function listForResale(uint256 tokenId, uint256 price) external whenNotPaused {
        if (ownerOf(tokenId) != msg.sender) revert NotTicketOwner();

        uint256 maxPrice = purchasePrice[tokenId] * RESALE_CAP_PCT / 100;
        if (price > maxPrice) revert PriceTooHigh(maxPrice, price);

        // Le contrat doit être approuvé pour pouvoir transférer le billet au moment de la vente
        if (getApproved(tokenId) != address(this) && !isApprovedForAll(msg.sender, address(this)))
            revert NotApproved();

        resalePrice[tokenId] = price;
        emit TicketListed(tokenId, msg.sender, price);
    }

    // ── Marché secondaire : achat ────────────────────────────────────────────
    function buyResale(uint256 tokenId) external payable nonReentrant whenNotPaused {
        uint256 price = resalePrice[tokenId];
        if (price == 0) revert NotForSale();
        if (msg.value < price) revert WrongPayment(price, msg.value);

        address seller = ownerOf(tokenId);

        // Re-vérification de l'approbation au moment de l'achat (le vendeur a pu la révoquer)
        if (getApproved(tokenId) != address(this) && !isApprovedForAll(seller, address(this)))
            revert NotApproved();

        uint256 fee          = price * PLATFORM_FEE_PCT / 100;
        uint256 sellerAmount = price - fee;
        uint256 excess       = msg.value - price;

        // Mise à jour d'état avant tout transfert (protection réentrance)
        resalePrice[tokenId] = 0;
        pendingWithdrawals[seller]    += sellerAmount;
        pendingWithdrawals[organizer] += fee;

        _transfer(seller, msg.sender, tokenId);
        emit TicketSold(tokenId, msg.sender, seller, price);

        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            require(ok, "Refund failed");
        }
    }

    // ── Retrait (pull payment) ───────────────────────────────────────────────
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NothingToWithdraw();

        // Mise à zéro avant l'appel externe (checks-effects-interactions)
        pendingWithdrawals[msg.sender] = 0;

        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    // ── Consultation (gas-efficiente) ────────────────────────────────────────
    // calldata évite la copie en mémoire ; unchecked évite le check overflow sur ++i
    function countForSale(uint256[] calldata tokenIds) external view returns (uint256 count) {
        for (uint256 i = 0; i < tokenIds.length; ) {
            if (resalePrice[tokenIds[i]] > 0) ++count;
            unchecked { ++i; }
        }
    }
}
