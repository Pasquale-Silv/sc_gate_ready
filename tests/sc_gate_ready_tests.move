#[test_only]
module sc_gate_ready::sc_gate_ready_tests;

use iota::coin::{Self, Coin};
use iota::iota::IOTA;
use iota::test_scenario::{Self, Scenario};
use sc_gate_ready::sc_gate_ready::{Self, PurchaseOrder};
use std::string;

// === Test addresses ===
const SELLER: address    = @0xA1;
const BUYER: address     = @0xB2;
const VALIDATOR: address = @0xC3;
const STRANGER: address  = @0xD4;

// === Order params ===
const PRICE: u64 = 100;
const QTY: u64   = 2;

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────

fun setup_order_with_validator(): Scenario {
    let mut scenario = test_scenario::begin(SELLER);
    sc_gate_ready::create_order(
        BUYER,
        vector[VALIDATOR],
        string::utf8(b"Widget"),
        string::utf8(b"A useful widget"),
        PRICE,
        QTY,
        test_scenario::ctx(&mut scenario),
    );
    scenario
}

fun setup_order_no_validators(): Scenario {
    let mut scenario = test_scenario::begin(SELLER);
    sc_gate_ready::create_order(
        BUYER,
        vector[],
        string::utf8(b"Widget"),
        string::utf8(b"A useful widget"),
        PRICE,
        QTY,
        test_scenario::ctx(&mut scenario),
    );
    scenario
}

/// Brings order to Confirmed state (buyer + validator both accept).
fun confirm_order(scenario: &mut Scenario) {
    test_scenario::next_tx(scenario, BUYER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(scenario);
    sc_gate_ready::accept_order(&mut order, test_scenario::ctx(scenario));
    test_scenario::return_shared(order);

    test_scenario::next_tx(scenario, VALIDATOR);
    let mut order = test_scenario::take_shared<PurchaseOrder>(scenario);
    sc_gate_ready::accept_order(&mut order, test_scenario::ctx(scenario));
    test_scenario::return_shared(order);
}

// ─────────────────────────────────────────────
// create_order
// ─────────────────────────────────────────────

/// Shared object is created and accessible after create_order.
#[test]
fun test_create_order_object_exists() {
    let mut scenario = setup_order_with_validator();
    test_scenario::next_tx(&mut scenario, SELLER);
    let order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

// ─────────────────────────────────────────────
// accept_order — confirmation logic
// ─────────────────────────────────────────────

/// Buyer + validator both accept → order is Confirmed.
/// Proved by store_notarization succeeding (requires Confirmed).
#[test]
fun test_buyer_and_validator_confirms() {
    let mut scenario = setup_order_with_validator();
    confirm_order(&mut scenario);

    test_scenario::next_tx(&mut scenario, SELLER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::store_notarization(
        &mut order,
        string::utf8(b"doc_hash"),
        string::utf8(b"ts_hash"),
        test_scenario::ctx(&mut scenario),
    );
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

/// Buyer accepts with no validators → order is Confirmed immediately.
#[test]
fun test_buyer_only_no_validators_confirms() {
    let mut scenario = setup_order_no_validators();

    test_scenario::next_tx(&mut scenario, BUYER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::accept_order(&mut order, test_scenario::ctx(&mut scenario));
    test_scenario::return_shared(order);

    // store_notarization succeeds → state is Confirmed
    test_scenario::next_tx(&mut scenario, SELLER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::store_notarization(
        &mut order,
        string::utf8(b"h"),
        string::utf8(b"t"),
        test_scenario::ctx(&mut scenario),
    );
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

/// Buyer accepts but validators are present and haven't acted → still Created.
/// Proved by validator being able to reject afterward (requires Created).
#[test]
fun test_buyer_alone_with_validators_stays_created() {
    let mut scenario = setup_order_with_validator();

    test_scenario::next_tx(&mut scenario, BUYER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::accept_order(&mut order, test_scenario::ctx(&mut scenario));
    test_scenario::return_shared(order);

    // reject_order works → state is still Created
    test_scenario::next_tx(&mut scenario, VALIDATOR);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::reject_order(&mut order, test_scenario::ctx(&mut scenario));
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

/// Validator accepts but buyer hasn't → still Created.
/// Proved by buyer being able to reject afterward.
#[test]
fun test_validator_alone_stays_created() {
    let mut scenario = setup_order_with_validator();

    test_scenario::next_tx(&mut scenario, VALIDATOR);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::accept_order(&mut order, test_scenario::ctx(&mut scenario));
    test_scenario::return_shared(order);

    test_scenario::next_tx(&mut scenario, BUYER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::reject_order(&mut order, test_scenario::ctx(&mut scenario));
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

// ─────────────────────────────────────────────
// reject_order
// ─────────────────────────────────────────────

/// Buyer rejects → Rejected. Proved by accept_order failing afterward.
#[test, expected_failure(abort_code = sc_gate_ready::EInvalidState)]
fun test_buyer_rejects_blocks_accept() {
    let mut scenario = setup_order_with_validator();

    test_scenario::next_tx(&mut scenario, BUYER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::reject_order(&mut order, test_scenario::ctx(&mut scenario));
    test_scenario::return_shared(order);

    // This must abort — state is Rejected
    test_scenario::next_tx(&mut scenario, VALIDATOR);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::accept_order(&mut order, test_scenario::ctx(&mut scenario));
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

/// Validator rejects → Rejected.
#[test, expected_failure(abort_code = sc_gate_ready::EInvalidState)]
fun test_validator_rejects_blocks_accept() {
    let mut scenario = setup_order_with_validator();

    test_scenario::next_tx(&mut scenario, VALIDATOR);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::reject_order(&mut order, test_scenario::ctx(&mut scenario));
    test_scenario::return_shared(order);

    test_scenario::next_tx(&mut scenario, BUYER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::accept_order(&mut order, test_scenario::ctx(&mut scenario));
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

// ─────────────────────────────────────────────
// Authorization guards
// ─────────────────────────────────────────────

#[test, expected_failure(abort_code = sc_gate_ready::ENotAuthorized)]
fun test_stranger_cannot_accept() {
    let mut scenario = setup_order_with_validator();
    test_scenario::next_tx(&mut scenario, STRANGER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::accept_order(&mut order, test_scenario::ctx(&mut scenario));
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = sc_gate_ready::ENotAuthorized)]
fun test_stranger_cannot_reject() {
    let mut scenario = setup_order_with_validator();
    test_scenario::next_tx(&mut scenario, STRANGER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::reject_order(&mut order, test_scenario::ctx(&mut scenario));
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

// ─────────────────────────────────────────────
// store_notarization
// ─────────────────────────────────────────────

#[test]
fun test_store_notarization_success() {
    let mut scenario = setup_order_with_validator();
    confirm_order(&mut scenario);

    test_scenario::next_tx(&mut scenario, SELLER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::store_notarization(
        &mut order,
        string::utf8(b"doc_hash_abc"),
        string::utf8(b"ts_hash_xyz"),
        test_scenario::ctx(&mut scenario),
    );
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = sc_gate_ready::ENotSeller)]
fun test_store_notarization_not_seller_aborts() {
    let mut scenario = setup_order_with_validator();
    confirm_order(&mut scenario);

    test_scenario::next_tx(&mut scenario, BUYER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::store_notarization(
        &mut order,
        string::utf8(b"h"),
        string::utf8(b"t"),
        test_scenario::ctx(&mut scenario),
    );
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = sc_gate_ready::EInvalidState)]
fun test_store_notarization_on_created_aborts() {
    let mut scenario = setup_order_with_validator();
    // Order still in Created state
    test_scenario::next_tx(&mut scenario, SELLER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    sc_gate_ready::store_notarization(
        &mut order,
        string::utf8(b"h"),
        string::utf8(b"t"),
        test_scenario::ctx(&mut scenario),
    );
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

// ─────────────────────────────────────────────
// pay_order
// ─────────────────────────────────────────────

/// Full payment flow: buyer pays correct amount → order becomes Paid,
/// seller receives the coin.
#[test]
fun test_pay_order_success() {
    let mut scenario = setup_order_with_validator();
    confirm_order(&mut scenario);

    test_scenario::next_tx(&mut scenario, BUYER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    let ctx = test_scenario::ctx(&mut scenario);
    let payment = coin::mint_for_testing<IOTA>(PRICE * QTY, ctx);
    sc_gate_ready::pay_order(&mut order, payment, ctx);
    test_scenario::return_shared(order);

    // Seller must have received the coin
    test_scenario::next_tx(&mut scenario, SELLER);
    let received = test_scenario::take_from_sender<Coin<IOTA>>(&scenario);
    assert!(coin::value(&received) == PRICE * QTY, 0);
    test_scenario::return_to_sender(&scenario, received);

    test_scenario::end(scenario);
}

/// Double-payment is impossible: second pay_order aborts (state = Paid).
#[test, expected_failure(abort_code = sc_gate_ready::EInvalidState)]
fun test_pay_twice_aborts() {
    let mut scenario = setup_order_with_validator();
    confirm_order(&mut scenario);

    test_scenario::next_tx(&mut scenario, BUYER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    let ctx = test_scenario::ctx(&mut scenario);
    let payment = coin::mint_for_testing<IOTA>(PRICE * QTY, ctx);
    sc_gate_ready::pay_order(&mut order, payment, ctx);
    test_scenario::return_shared(order);

    // Second attempt must abort
    test_scenario::next_tx(&mut scenario, BUYER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    let ctx = test_scenario::ctx(&mut scenario);
    let payment = coin::mint_for_testing<IOTA>(PRICE * QTY, ctx);
    sc_gate_ready::pay_order(&mut order, payment, ctx);
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = sc_gate_ready::EInsufficientPayment)]
fun test_pay_wrong_amount_aborts() {
    let mut scenario = setup_order_with_validator();
    confirm_order(&mut scenario);

    test_scenario::next_tx(&mut scenario, BUYER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    let ctx = test_scenario::ctx(&mut scenario);
    let payment = coin::mint_for_testing<IOTA>(1, ctx); // wrong amount
    sc_gate_ready::pay_order(&mut order, payment, ctx);
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = sc_gate_ready::ENotBuyer)]
fun test_pay_not_buyer_aborts() {
    let mut scenario = setup_order_with_validator();
    confirm_order(&mut scenario);

    test_scenario::next_tx(&mut scenario, STRANGER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    let ctx = test_scenario::ctx(&mut scenario);
    let payment = coin::mint_for_testing<IOTA>(PRICE * QTY, ctx);
    sc_gate_ready::pay_order(&mut order, payment, ctx);
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = sc_gate_ready::EInvalidState)]
fun test_pay_on_created_aborts() {
    let mut scenario = setup_order_with_validator();
    // Order is still Created — not Confirmed
    test_scenario::next_tx(&mut scenario, BUYER);
    let mut order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    let ctx = test_scenario::ctx(&mut scenario);
    let payment = coin::mint_for_testing<IOTA>(PRICE * QTY, ctx);
    sc_gate_ready::pay_order(&mut order, payment, ctx);
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}

// ─────────────────────────────────────────────
// get_document_fields
// ─────────────────────────────────────────────

/// All document fields match what was passed to create_order.
#[test]
fun test_get_document_fields() {
    let mut scenario = setup_order_with_validator();
    test_scenario::next_tx(&mut scenario, SELLER);
    let order = test_scenario::take_shared<PurchaseOrder>(&scenario);
    let (seller, buyer, name, desc, price, qty) = sc_gate_ready::get_document_fields(&order);
    assert!(seller == SELLER, 0);
    assert!(buyer  == BUYER,  1);
    assert!(name   == string::utf8(b"Widget"),          2);
    assert!(desc   == string::utf8(b"A useful widget"), 3);
    assert!(price  == PRICE, 4);
    assert!(qty    == QTY,   5);
    test_scenario::return_shared(order);
    test_scenario::end(scenario);
}
