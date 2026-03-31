# SC Gate Ready

Purchase Order notarization smart contract on the IOTA network, built with Move (edition 2024).

**Gate Ready** is a startup building logistics-sector tooling. This contract notarizes Purchase Orders on-chain after collecting approvals from all required parties.

## Deployed Contract

| Field     | Value |
|-----------|-------|
| **PackageID** | `0x54ea5a6939e911ee036cdc3a07f96954f6bad4409505153c80ddd773b8854feb` |
| **Module**    | `sc_gate_ready` |
| **Version**   | 1 |
| **Digest**    | `5Bg9XptQZ7AnZKXvXKinvzE13WTX4QRLV7J3Mx3sc1AR` |
| **Owner**     | `0xdf00d1f026245e82418d397e2c366fd689b4d0af50599cac5c3aaee627ca512b` |

## How It Works

The contract manages the full lifecycle of a Purchase Order as a **shared object**, accessible by all involved parties.

### Order Lifecycle

```
Created ──> Confirmed ──> Paid
   |
   └──────> Rejected
```

**Step 1 -- Create Order**
The seller creates the order, specifying the buyer address, an optional list of validator addresses, and product details (name, description, price, quantity). The order starts in `Created` state.

**Step 2 -- Accept or Reject**
The buyer and validators review the order:
- If the buyer **and** at least one validator accept, the order moves to `Confirmed`.
- If no validators were designated, only the buyer's acceptance is required.
- If any authorized party rejects, the order moves to `Rejected` immediately.

**Step 3 -- Notarize**
Once confirmed, the seller triggers notarization. The frontend retrieves the document fields (`seller`, `buyer`, `product_name`, `product_description`, `price`, `quantity`), generates a document, and hashes it. The seller then stores the `notarization_hash` and `timestamp_hash` on-chain.

**Step 4 -- Pay**
The buyer pays `price * quantity` IOTA to the seller. The order moves to `Paid`.

## Project Structure

```
sc_gate_ready/
  Move.toml                          # Package manifest
  sources/
    sc_gate_ready.move               # Main contract module
  tests/
    sc_gate_ready_tests.move         # Test suite (16 tests)
```

## Entry Functions

| Function | Caller | Required State | Description |
|----------|--------|----------------|-------------|
| `create_order` | Seller | -- | Creates a new shared `PurchaseOrder` object |
| `accept_order` | Buyer / Validator | `Created` | Records approval; auto-confirms when conditions are met |
| `reject_order` | Buyer / Validator | `Created` | Immediately rejects the order |
| `store_notarization` | Seller | `Confirmed` | Stores document hash and timestamp on-chain |
| `pay_order` | Buyer | `Confirmed` | Transfers `price * quantity` IOTA to the seller |

### Read-Only Functions

| Function | Description |
|----------|-------------|
| `get_document_fields` | Returns `(seller, buyer, product_name, product_description, price, quantity)` for document generation |

## Error Codes

| Constant | Code | Meaning |
|----------|------|---------|
| `ENotSeller` | 0 | Caller is not the seller |
| `ENotBuyer` | 1 | Caller is not the buyer |
| `EInvalidState` | 2 | Order is not in the required state for this operation |
| `EInsufficientPayment` | 3 | Payment amount does not match `price * quantity` |
| `ENotAuthorized` | 4 | Caller is neither the buyer nor a designated validator |

## Development

### Prerequisites

- [IOTA CLI](https://docs.iota.org/) installed and available as `iota`

### Build

```bash
iota move build
```

### Test

```bash
iota move test          # Run all 16 tests
iota move test <name>   # Run a single test by name
```

### Type Check

```bash
iota move check
```

## License

All rights reserved.
