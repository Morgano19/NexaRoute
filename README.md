# NexaRoute: AI-Optimized Token Swap Router

## Overview

**NexaRoute** is an enterprise-grade, high-performance smart contract written in **Clarity** for the Stacks blockchain. It serves as a sophisticated liquidity routing layer designed to bridge the gap between complex off-chain machine learning capabilities and on-chain execution.

In the rapidly evolving DeFi landscape, static routing often fails to capture the most efficient capital paths due to fragmented liquidity and volatile pool weights. NexaRoute solves this by utilizing an **"AI-in-the-Loop"** architecture. Off-chain agents continuously monitor SIP-010 token pools, calculating optimal weights and paths based on real-time slippage data, depth, and historical performance. These optimized routes are then committed to the blockchain by authorized AI Oracles (Admins), ensuring that users always interact with the most capital-efficient execution paths available.

---

## Technical Architecture

The contract is built on a modular framework that prioritizes security, scalability, and transparency.

### Core Components
1.  **Routing Engine:** A dynamic mapping system that stores AI-calculated weights for both single and multi-hop swaps.
2.  **Administrative Layer:** A multi-admin RBAC (Role-Based Access Control) system allowing for decentralized or automated oracle management.
3.  **Security Firewall:** Integrated global pause (circuit breaker), user blacklisting, and strict slippage validation.
4.  **Economic Model:** A basis-point (BPS) driven fee system with protected withdrawal logic for protocol sustainability.

### Error Reference Table

| Code | Constant | Description |
| :--- | :--- | :--- |
| `u1000` | `ERR-NOT-AUTHORIZED` | Caller lacks the administrative privileges required. |
| `u1001` | `ERR-INVALID-AMOUNT` | The provided amount is zero or negative. |
| `u1002` | `ERR-SLIPPAGE-EXCEEDED` | The calculated output falls below the user's `min-amount-out`. |
| `u1003` | `ERR-INVALID-ROUTE` | No optimized route has been defined for this token pair. |
| `u1004` | `ERR-USER-BLACKLISTED` | The user has been restricted from protocol interaction. |
| `u1005` | `ERR-PAUSED` | The contract is currently under emergency pause. |
| `u1006` | `ERR-FEE-TOO-HIGH` | The proposed protocol fee exceeds the `MAX-FEE-BPS` (10%). |
| `u1007` | `ERR-SAME-TOKEN` | Input and output tokens must be distinct principals. |

---

## Detailed Function Specification

### 1. Private Functions
These internal helpers manage the contract's state logic and security checks, ensuring code reusability and minimizing the attack surface.

* **`is-not-paused`**: Returns a boolean indicating if the contract is active. Used as a gatekeeper for all state-changing swap functions.
* **`is-admin`**: Validates whether a given principal is either the `CONTRACT-OWNER` or exists in the `Admins` map.
* **`is-not-blacklisted`**: Checks the `Blacklist` map to ensure the transaction initiator is authorized to use the protocol.
* **`validate-amount`**: A simple assertion check to ensure `amount > 0`.
* **`calculate-fee`**: Computes the protocol's cut based on the current `protocol-fee-bps`.
* **`update-stats`**: Safely increments global volume and individual user metrics (`swaps` and `volume`) after a successful trade.
* **`transfer-token`**: A wrapper for the SIP-010 `transfer` trait, facilitating the movement of assets between users, the contract, and liquidity pools.

### 2. Public Functions
The primary interface for users, AI oracles, and the protocol owner.

#### **Admin & Security Management**
* **`toggle-pause`**: Allows an admin to instantly halt all swap activities in the event of an exploit or extreme market volatility.
* **`add-admin / remove-admin`**: Enables the `CONTRACT-OWNER` to manage the fleet of AI oracles authorized to update routing data.
* **`blacklist-user / unblacklist-user`**: Provides the ability to restrict malicious actors (e.g., known exploiters) from the platform.
* **`set-protocol-fee`**: Dynamically adjusts the fee (bps). It includes a hard cap of 10% to protect users from "owner-griefing."
* **`withdraw-fees`**: Securely transfers accumulated fees for a specific SIP-010 token to the protocol treasury.

#### **AI Route Management**
* **`set-optimized-route`**: The core data-entry point. Admins provide `token-in`, `token-out`, the target `pool-address`, and a `weight`. This weight represents the optimized exchange rate inclusive of the AI's predicted slippage.

#### **Swap Execution**
* **`execute-single-swap`**: Processes a direct trade between two tokens. It calculates fees, verifies the AI-provided weight, checks against the user's slippage tolerance, updates statistics, and emits an event for off-chain tracking.
* **`execute-ai-optimized-multi-hop-swap`**: The router’s flagship feature. It routes a swap through an intermediary "mid-token" (e.g., STX or USDA). It fetches two distinct optimized legs, compounds the weights, and ensures the final output meets the user's `min-amount-out` requirements.

### 3. Read-Only Functions
Non-state-changing queries used by frontend applications and off-chain AI monitoring agents.

* **`get-user-stats`**: Returns a tuple containing the total number of swaps and total volume generated by a specific principal.
* **`preview-single-swap`**: Simulates a single-hop swap based on current AI weights and protocol fees, allowing users to see their expected return before committing gas.
* **`preview-multi-hop-swap`**: Simulates the full multi-hop path (A -> B -> C), providing a comprehensive output estimate inclusive of all intermediate steps and fees.

---

## Deployment & Integration

To integrate with NexaRoute, developers must ensure their tokens are SIP-010 compliant. 

### Integration Steps
1.  **AI Oracle Setup:** Deploy an off-chain worker that queries DEX liquidity (e.g., Alex, Velar) and calls `set-optimized-route` when price deviations occur.
2.  **Slippage Management:** When calling swap functions, always calculate `min-amount-out` on the client side to prevent losses from front-running or stale AI data.
3.  **Event Listening:** Monitor the `ai-single-swap` and `ai-multi-hop-swap-executed` print events to update UI state in real-time.

---

## MIT License

```text
Copyright (c) 2026 NexaRoute Protocol

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Contribution Guidelines

We maintain a strict standard for code quality and security.
1.  **Bug Reports:** Please open an issue with a clear description and steps to reproduce.
2.  **Feature Requests:** Proposals for new routing logic or optimizations should include a brief technical specification.
3.  **Pull Requests:** All PRs must pass the existing Clarinet test suite and include new tests for added functionality.

---

## Disclaimer
NexaRoute is provided "as is". While the contract includes multiple security features, the use of off-chain AI agents introduces a dependency on the integrity of the admins. Users should verify the reputation of the protocol operators. Smart contract interactions involve inherent risks, including the total loss of funds.
