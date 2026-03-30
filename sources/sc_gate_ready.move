module sc_gate_ready::sc_gate_ready;

use iota::coin::{Self, Coin};
use iota::iota::IOTA;
use iota::object::{Self, UID};
use iota::transfer;
use iota::tx_context::{Self, TxContext};
use std::option::{Self, Option};
use std::string::String;
use std::vector;

// === Order states ===
const STATE_CREATED: u8   = 0;
const STATE_CONFIRMED: u8 = 1;
const STATE_REJECTED: u8  = 2;
const STATE_PAID: u8      = 3;

// === Errors ===
const ENotSeller: u64          = 0;
const ENotBuyer: u64           = 1;
const EInvalidState: u64       = 2;
const EInsufficientPayment: u64 = 3;
const ENotAuthorized: u64      = 4;

// === Struct ===

public struct PurchaseOrder has key {
    id: UID,
    seller: address,
    buyer: address,
    /// Optional list of validators; empty means no validators required.
    validators: vector<address>,
    product_name: String,
    product_description: String,
    /// Unit price in IOTA (MIST).
    price: u64,
    quantity: u64,
    order_state: u8,
    /// Hash of the notarized document; populated after notarization.
    notarization_hash: Option<String>,
    /// Timestamp hash of notarization; populated after notarization.
    timestamp_hash: Option<String>,
    // Internal acceptance tracking
    buyer_approved: bool,
    any_validator_approved: bool,
}

// === Public entry functions ===

/// Step 1 — Seller creates a new purchase order as a shared object.
public entry fun create_order(
    buyer: address,
    validators: vector<address>,
    product_name: String,
    product_description: String,
    price: u64,
    quantity: u64,
    ctx: &mut TxContext,
) {
    let order = PurchaseOrder {
        id: object::new(ctx),
        seller: tx_context::sender(ctx),
        buyer,
        validators,
        product_name,
        product_description,
        price,
        quantity,
        order_state: STATE_CREATED,
        notarization_hash: option::none(),
        timestamp_hash: option::none(),
        buyer_approved: false,
        any_validator_approved: false,
    };
    transfer::share_object(order);
}

/// Step 2a — Buyer or a validator accepts the order.
/// Transitions to Confirmed when buyer + at least one validator have accepted
/// (or only buyer if no validators were designated).
public entry fun accept_order(order: &mut PurchaseOrder, ctx: &mut TxContext) {
    assert!(order.order_state == STATE_CREATED, EInvalidState);
    let caller = tx_context::sender(ctx);
    if (caller == order.buyer) {
        order.buyer_approved = true;
    } else {
        assert!(is_validator(order, caller), ENotAuthorized);
        order.any_validator_approved = true;
    };
    try_confirm(order);
}

/// Step 2b — Buyer or a validator rejects the order.
/// Immediately transitions to Rejected.
public entry fun reject_order(order: &mut PurchaseOrder, ctx: &mut TxContext) {
    assert!(order.order_state == STATE_CREATED, EInvalidState);
    let caller = tx_context::sender(ctx);
    assert!(caller == order.buyer || is_validator(order, caller), ENotAuthorized);
    order.order_state = STATE_REJECTED;
}

/// Step 3a — Returns the fields the frontend needs to compose the notarization document.
public fun get_document_fields(
    order: &PurchaseOrder,
): (address, address, String, String, u64, u64) {
    (
        order.seller,
        order.buyer,
        order.product_name,
        order.product_description,
        order.price,
        order.quantity,
    )
}

/// Step 3b — Seller stores the document hash and timestamp after notarization.
/// Only callable when the order is Confirmed.
public entry fun store_notarization(
    order: &mut PurchaseOrder,
    notarization_hash: String,
    timestamp_hash: String,
    ctx: &mut TxContext,
) {
    assert!(order.order_state == STATE_CONFIRMED, EInvalidState);
    assert!(tx_context::sender(ctx) == order.seller, ENotSeller);
    order.notarization_hash = option::some(notarization_hash);
    order.timestamp_hash = option::some(timestamp_hash);
}

/// Step 4 — Buyer pays (price * quantity) IOTA; transitions the order to Paid.
public entry fun pay_order(
    order: &mut PurchaseOrder,
    payment: Coin<IOTA>,
    ctx: &mut TxContext,
) {
    assert!(order.order_state == STATE_CONFIRMED, EInvalidState);
    assert!(tx_context::sender(ctx) == order.buyer, ENotBuyer);
    let required = order.price * order.quantity;
    assert!(coin::value(&payment) == required, EInsufficientPayment);
    transfer::public_transfer(payment, order.seller);
    order.order_state = STATE_PAID;
}

// === Internal helpers ===

fun try_confirm(order: &mut PurchaseOrder) {
    let no_validators = vector::is_empty(&order.validators);
    if (order.buyer_approved && (no_validators || order.any_validator_approved)) {
        order.order_state = STATE_CONFIRMED;
    };
}

fun is_validator(order: &PurchaseOrder, addr: address): bool {
    let len = vector::length(&order.validators);
    let mut i = 0;
    while (i < len) {
        if (*vector::borrow(&order.validators, i) == addr) {
            return true
        };
        i = i + 1;
    };
    false
}
