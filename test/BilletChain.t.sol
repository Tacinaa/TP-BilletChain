// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BilletChain.sol";
import "./mocks/MockOracle.sol";

contract BilletChainTest is Test {

    BilletChain bc;
    MockOracle  oracle;

    address organizer = makeAddr("organizer");
    address alice     = makeAddr("alice");
    address bob       = makeAddr("bob");

    // Taux : 2000 EUR/ETH à 8 décimales
    // Prix en wei : 50 * 1e26 / 2000e8 = 25e15 (0.025 ETH)
    int256  constant RATE      = 2000e8;
    uint256 constant EUR_PRICE = 50;
    uint256 constant TOTAL     = 3;      // petit pour tester SoldOut facilement
    uint256 constant WEI_PRICE = 25e15;

    uint256 nextTokenId; // suit les tokenIds séquentiels (commence à 0)

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        oracle = new MockOracle(RATE);
        vm.prank(organizer);
        bc = new BilletChain(TOTAL, EUR_PRICE, address(oracle));
        nextTokenId = 0;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _buy(address buyer) internal returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        vm.deal(buyer, WEI_PRICE);
        vm.prank(buyer);
        bc.buyTicket{value: WEI_PRICE}();
    }

    function _listAndApprove(address seller, uint256 tokenId, uint256 price) internal {
        vm.startPrank(seller);
        bc.approve(address(bc), tokenId);
        bc.listForResale(tokenId, price);
        vm.stopPrank();
    }

    // ── Vente initiale — cas nominal ──────────────────────────────────────────

    function test_buyTicket_happyPath() public {
        uint256 tokenId = _buy(alice);

        assertEq(bc.ownerOf(tokenId), alice);
        assertEq(bc.purchasePrice(tokenId), WEI_PRICE);
        assertEq(bc.pendingWithdrawals(organizer), WEI_PRICE);
    }

    function test_buyTicket_emitsEvent() public {
        vm.deal(alice, WEI_PRICE);
        vm.expectEmit(true, true, false, true);
        emit BilletChain.TicketMinted(0, alice, WEI_PRICE);
        vm.prank(alice);
        bc.buyTicket{value: WEI_PRICE}();
    }

    // ── Vente initiale — cas d'erreur ─────────────────────────────────────────

    function test_buyTicket_revert_paymentTooLow() public {
        vm.deal(alice, WEI_PRICE);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(BilletChain.WrongPayment.selector, WEI_PRICE, WEI_PRICE - 1)
        );
        bc.buyTicket{value: WEI_PRICE - 1}();
    }

    function test_buyTicket_revert_paymentTooHigh() public {
        vm.deal(alice, WEI_PRICE + 1);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(BilletChain.WrongPayment.selector, WEI_PRICE, WEI_PRICE + 1)
        );
        bc.buyTicket{value: WEI_PRICE + 1}();
    }

    function test_buyTicket_revert_soldOut() public {
        _buy(alice);
        _buy(alice);
        _buy(alice); // épuise les 3 billets

        vm.deal(bob, WEI_PRICE);
        vm.prank(bob);
        vm.expectRevert(BilletChain.SoldOut.selector);
        bc.buyTicket{value: WEI_PRICE}();
    }

    // ── Oracle ────────────────────────────────────────────────────────────────

    function test_buyTicket_revert_staleOracle() public {
        // Avancer le temps au-delà de MAX_STALENESS (1h) depuis le dernier update
        // MockOracle._updatedAt est fixé à block.timestamp lors du déploiement
        vm.warp(block.timestamp + bc.MAX_STALENESS() + 1);

        vm.deal(alice, WEI_PRICE);
        vm.prank(alice);
        vm.expectRevert(BilletChain.StaleOracle.selector);
        bc.buyTicket{value: WEI_PRICE}();
    }

    function test_buyTicket_revert_invalidOracleAnswer() public {
        oracle.setAnswer(0);

        vm.deal(alice, WEI_PRICE);
        vm.prank(alice);
        vm.expectRevert(BilletChain.InvalidOracleAnswer.selector);
        bc.buyTicket{value: WEI_PRICE}();
    }

    function test_buyTicket_revert_negativeOracleAnswer() public {
        oracle.setAnswer(-1);

        vm.deal(alice, WEI_PRICE);
        vm.prank(alice);
        vm.expectRevert(BilletChain.InvalidOracleAnswer.selector);
        bc.buyTicket{value: WEI_PRICE}();
    }

    // ── Mise en vente secondaire — cas nominal ────────────────────────────────

    function test_listForResale_happyPath() public {
        uint256 tokenId = _buy(alice);

        _listAndApprove(alice, tokenId, WEI_PRICE);

        assertEq(bc.resalePrice(tokenId), WEI_PRICE);
    }

    function test_listForResale_atExactCap() public {
        uint256 tokenId  = _buy(alice);
        uint256 maxPrice = WEI_PRICE * 110 / 100;

        _listAndApprove(alice, tokenId, maxPrice); // doit passer

        assertEq(bc.resalePrice(tokenId), maxPrice);
    }

    // ── Mise en vente secondaire — cas d'erreur ───────────────────────────────

    function test_listForResale_revert_notOwner() public {
        uint256 tokenId = _buy(alice);

        vm.prank(bob);
        vm.expectRevert(BilletChain.NotTicketOwner.selector);
        bc.listForResale(tokenId, WEI_PRICE);
    }

    function test_listForResale_revert_priceTooHigh() public {
        uint256 tokenId  = _buy(alice);
        uint256 maxPrice = WEI_PRICE * 110 / 100;
        uint256 overPrice = maxPrice + 1;

        vm.startPrank(alice);
        bc.approve(address(bc), tokenId);
        vm.expectRevert(
            abi.encodeWithSelector(BilletChain.PriceTooHigh.selector, maxPrice, overPrice)
        );
        bc.listForResale(tokenId, overPrice);
        vm.stopPrank();
    }

    function test_listForResale_revert_notApproved() public {
        uint256 tokenId = _buy(alice);

        vm.prank(alice);
        vm.expectRevert(BilletChain.NotApproved.selector);
        bc.listForResale(tokenId, WEI_PRICE);
    }

    // ── Achat secondaire — cas nominal ───────────────────────────────────────

    function test_buyResale_happyPath() public {
        uint256 tokenId  = _buy(alice);
        uint256 resaleP  = WEI_PRICE * 105 / 100; // 105 %, sous le plafond

        _listAndApprove(alice, tokenId, resaleP);

        vm.deal(bob, resaleP);
        vm.prank(bob);
        bc.buyResale{value: resaleP}(tokenId);

        assertEq(bc.ownerOf(tokenId), bob);
        assertEq(bc.resalePrice(tokenId), 0);
        assertEq(bc.pendingWithdrawals(alice), resaleP);
    }

    function test_buyResale_emitsEvent() public {
        uint256 tokenId = _buy(alice);
        _listAndApprove(alice, tokenId, WEI_PRICE);

        vm.deal(bob, WEI_PRICE);
        vm.expectEmit(true, true, true, true);
        emit BilletChain.TicketSold(tokenId, bob, alice, WEI_PRICE);
        vm.prank(bob);
        bc.buyResale{value: WEI_PRICE}(tokenId);
    }

    // ── Achat secondaire — cas d'erreur ──────────────────────────────────────

    function test_buyResale_revert_notForSale() public {
        uint256 tokenId = _buy(alice);

        vm.deal(bob, WEI_PRICE);
        vm.prank(bob);
        vm.expectRevert(BilletChain.NotForSale.selector);
        bc.buyResale{value: WEI_PRICE}(tokenId);
    }

    function test_buyResale_revert_wrongPayment() public {
        uint256 tokenId = _buy(alice);
        _listAndApprove(alice, tokenId, WEI_PRICE);

        vm.deal(bob, WEI_PRICE + 1);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(BilletChain.WrongPayment.selector, WEI_PRICE, WEI_PRICE + 1)
        );
        bc.buyResale{value: WEI_PRICE + 1}(tokenId);
    }

    function test_buyResale_revert_approvalRevoked() public {
        uint256 tokenId = _buy(alice);
        _listAndApprove(alice, tokenId, WEI_PRICE);

        // Alice révoque l'approbation après la mise en vente
        vm.prank(alice);
        bc.approve(address(0), tokenId);

        vm.deal(bob, WEI_PRICE);
        vm.prank(bob);
        vm.expectRevert(BilletChain.NotApproved.selector);
        bc.buyResale{value: WEI_PRICE}(tokenId);
    }

    // ── Retrait ───────────────────────────────────────────────────────────────

    function test_withdraw_organizer() public {
        _buy(alice);
        uint256 before = organizer.balance;

        vm.prank(organizer);
        bc.withdraw();

        assertEq(organizer.balance, before + WEI_PRICE);
        assertEq(bc.pendingWithdrawals(organizer), 0);
    }

    function test_withdraw_seller() public {
        uint256 tokenId = _buy(alice);
        uint256 resaleP = WEI_PRICE * 110 / 100;
        _listAndApprove(alice, tokenId, resaleP);

        vm.deal(bob, resaleP);
        vm.prank(bob);
        bc.buyResale{value: resaleP}(tokenId);

        uint256 before = alice.balance;
        vm.prank(alice);
        bc.withdraw();

        assertEq(alice.balance, before + resaleP);
        assertEq(bc.pendingWithdrawals(alice), 0);
    }

    function test_withdraw_revert_nothingToWithdraw() public {
        vm.prank(alice);
        vm.expectRevert(BilletChain.NothingToWithdraw.selector);
        bc.withdraw();
    }

    // ── Consultation ──────────────────────────────────────────────────────────

    function test_countForSale_partialListing() public {
        uint256 t0 = _buy(alice);
        uint256 t1 = _buy(alice);
        uint256 t2 = _buy(bob);

        _listAndApprove(alice, t0, WEI_PRICE);
        _listAndApprove(alice, t1, WEI_PRICE);
        // t2 non listé

        uint256[] memory ids = new uint256[](3);
        ids[0] = t0; ids[1] = t1; ids[2] = t2;

        assertEq(bc.countForSale(ids), 2);
    }

    function test_countForSale_emptyList() public view {
        assertEq(bc.countForSale(new uint256[](0)), 0);
    }

    function test_countForSale_noneForSale() public {
        uint256 t0 = _buy(alice);
        uint256[] memory ids = new uint256[](1);
        ids[0] = t0;
        assertEq(bc.countForSale(ids), 0);
    }

    // ── Fuzz : le plafond 110 % n'est jamais dépassable ──────────────────────

    function testFuzz_listForResale_capNeverExceeded(uint256 price) public {
        uint256 tokenId  = _buy(alice);
        uint256 maxPrice = WEI_PRICE * 110 / 100;
        price = bound(price, maxPrice + 1, type(uint256).max);

        vm.startPrank(alice);
        bc.approve(address(bc), tokenId);
        vm.expectRevert();
        bc.listForResale(tokenId, price);
        vm.stopPrank();
    }
}
