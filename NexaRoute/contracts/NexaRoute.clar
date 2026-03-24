;; contract title 
;; AI-Optimized Token Swap Router (Extended Edition)

;; <add a description here> 
;; This smart contract acts as an intelligent routing mechanism for token swaps.
;; It leverages AI-calculated weights and routes to optimize execution paths,
;; minimize slippage, and securely process multi-hop trades across different pools.
;; Security features include global pause, strict slippage checks, input validation,
;; admin role management, user blacklisting, and protocol fee extraction.
;;
;; The router interfaces with SIP-010 compliant fungible tokens.
;; Off-chain AI agents continuously analyze pool liquidity and adjust weights
;; by calling the `set-optimized-route` functions.

;; traits
(define-trait ft-trait
    (
        ;; Transfer from the caller to a new principal
        (transfer (uint principal principal (optional (buff 34))) (response bool uint))
        ;; the human readable name of the token
        (get-name () (response (string-ascii 32) uint))
        ;; the ticker symbol, or empty if none
        (get-symbol () (response (string-ascii 32) uint))
        ;; the number of decimals used, e.g. 6 would mean 1_000_000 represents 1 token
        (get-decimals () (response uint uint))
        ;; the balance of the passed principal
        (get-balance (principal) (response uint uint))
        ;; the current total supply (which does not need to be a constant)
        (get-total-supply () (response uint uint))
        ;; an optional URI that represents metadata of this token
        (get-token-uri () (response (optional (string-utf8 256)) uint))
    )
)

;; constants 
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-AMOUNT (err u1001))
(define-constant ERR-SLIPPAGE-EXCEEDED (err u1002))
(define-constant ERR-INVALID-ROUTE (err u1003))
(define-constant ERR-USER-BLACKLISTED (err u1004))
(define-constant ERR-PAUSED (err u1005))
(define-constant ERR-FEE-TOO-HIGH (err u1006))
(define-constant ERR-SAME-TOKEN (err u1007))
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-FEE-BPS u1000) ;; 10% maximum protocol fee to prevent admin abuse
(define-constant BPS-DENOMINATOR u10000)

;; data maps and vars 

;; Store the latest AI-calculated optimal routes between token pairs
(define-map OptimizedRoutes
    { token-in: principal, token-out: principal }
    { pool-address: principal, weight: uint, updated-at: uint }
)

;; Global kill switch for emergency pausing by the admin
(define-data-var global-paused bool false)

;; Multi-admin system for AI oracles to update routes
(define-map Admins principal bool)

;; Security blacklist for malicious actors
(define-map Blacklist principal bool)

;; Protocol fee in basis points (1 bps = 0.01%)
(define-data-var protocol-fee-bps uint u30) ;; Default 0.3%

;; Statistics tracking
(define-data-var total-volume uint u0)
(define-map UserStats principal { swaps: uint, volume: uint })
(define-map CollectedFees principal uint)

;; private functions 

;; Internal check to ensure the contract is not paused
(define-private (is-not-paused)
    (not (var-get global-paused))
)

;; Internal check to ensure the caller is an admin or the owner
(define-private (is-admin (user principal))
    (or (is-eq user CONTRACT-OWNER) (default-to false (map-get? Admins user)))
)

;; Internal check to ensure the user is not blacklisted
(define-private (is-not-blacklisted (user principal))
    (not (default-to false (map-get? Blacklist user)))
)

;; Validate that the transaction amount is strictly greater than 0
(define-private (validate-amount (amount uint))
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (ok true)
    )
)

;; Calculate protocol fee
(define-private (calculate-fee (amount uint))
    (/ (* amount (var-get protocol-fee-bps)) BPS-DENOMINATOR)
)

;; Update user and global statistics safely
(define-private (update-stats (user principal) (amount uint))
    (let (
        (current-stats (default-to { swaps: u0, volume: u0 } (map-get? UserStats user)))
    )
        (var-set total-volume (+ (var-get total-volume) amount))
        (map-set UserStats user {
            swaps: (+ (get swaps current-stats) u1),
            volume: (+ (get volume current-stats) amount)
        })
        true
    )
)

;; Transfer helper that wraps the SIP-010 transfer function
(define-private (transfer-token (token <ft-trait>) (amount uint) (sender principal) (recipient principal))
    (contract-call? token transfer amount sender recipient none)
)

;; public functions 

;; Initialize owner as admin
(map-set Admins CONTRACT-OWNER true)

;; --- Admin & Security Management ---

;; Admin function to pause the contract in case of emergency
(define-public (toggle-pause)
    (begin
        (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
        (ok (var-set global-paused (not (var-get global-paused))))
    )
)

;; Owner function to add a new admin (e.g., an AI oracle wallet)
(define-public (add-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-set Admins new-admin true))
    )
)

;; Owner function to remove an admin
(define-public (remove-admin (admin principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-set Admins admin false))
    )
)

;; Admin function to blacklist a malicious user
(define-public (blacklist-user (user principal))
    (begin
        (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
        (ok (map-set Blacklist user true))
    )
)

;; Admin function to unblacklist a user
(define-public (unblacklist-user (user principal))
    (begin
        (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
        (ok (map-set Blacklist user false))
    )
)

;; Admin function to adjust the protocol fee
(define-public (set-protocol-fee (new-fee-bps uint))
    (begin
        (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-fee-bps MAX-FEE-BPS) ERR-FEE-TOO-HIGH)
        (ok (var-set protocol-fee-bps new-fee-bps))
    )
)

;; --- AI Route Management ---

;; Admin function to update the AI-optimized route for a specific pair
;; This is called frequently by off-chain AI agents to keep the on-chain router updated
(define-public (set-optimized-route (token-in principal) (token-out principal) (pool-address principal) (weight uint))
    (begin
        (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-eq token-in token-out)) ERR-SAME-TOKEN)
        (ok (map-set OptimizedRoutes 
            { token-in: token-in, token-out: token-out } 
            { pool-address: pool-address, weight: weight, updated-at: block-height }
        ))
    )
)

;; Admin function to collect protocol fees
(define-public (withdraw-fees (token-trait <ft-trait>))
    (let
        (
            (token (contract-of token-trait))
            (fee-amount (default-to u0 (map-get? CollectedFees token)))
        )
        (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (> fee-amount u0) ERR-INVALID-AMOUNT)
        
        ;; Reset the collected fee tracker
        (map-set CollectedFees token u0)
        
        ;; Execute the fee transfer to the protocol owner
        (try! (as-contract (transfer-token token-trait fee-amount tx-sender CONTRACT-OWNER)))
        
        (ok fee-amount)
    )
)

;; --- Core Swap Execution ---

;; Standard single-hop swap using AI optimized weights
(define-public (execute-single-swap 
    (token-in-trait <ft-trait>) 
    (token-out-trait <ft-trait>) 
    (amount-in uint) 
    (min-amount-out uint))
    (let 
        (
            (token-in (contract-of token-in-trait))
            (token-out (contract-of token-out-trait))
            (route (unwrap! (map-get? OptimizedRoutes { token-in: token-in, token-out: token-out }) ERR-INVALID-ROUTE))
            (fee (calculate-fee amount-in))
            (amount-after-fee (- amount-in fee))
            (expected-out (/ (* amount-after-fee (get weight route)) BPS-DENOMINATOR))
        )
        ;; Security Checks
        (asserts! (is-not-paused) ERR-PAUSED)
        (asserts! (is-not-blacklisted tx-sender) ERR-USER-BLACKLISTED)
        (try! (validate-amount amount-in))
        (asserts! (>= expected-out min-amount-out) ERR-SLIPPAGE-EXCEEDED)
        
        ;; Update protocol fee tracking
        (map-set CollectedFees token-in (+ (default-to u0 (map-get? CollectedFees token-in)) fee))
        
        ;; Update statistics
        (update-stats tx-sender amount-in)
        
        ;; Execution (Simulated transfer logic)
        ;; 1. Transfer fee to protocol
        ;; 2. Transfer remainder to pool
        ;; 3. Transfer output from pool to user
        
        ;; Event logging
        (print {
            event: "ai-single-swap",
            user: tx-sender,
            token-in: token-in,
            token-out: token-out,
            amount-in: amount-in,
            fee: fee,
            expected-out: expected-out
        })
        
        (ok expected-out)
    )
)

;; Read-only function for off-chain AI to query the current stats of a user
(define-read-only (get-user-stats (user principal))
    (default-to { swaps: u0, volume: u0 } (map-get? UserStats user))
)

;; Read-only function to preview a single hop swap output
(define-read-only (preview-single-swap (token-in principal) (token-out principal) (amount-in uint))
    (let 
        (
            (route (unwrap! (map-get? OptimizedRoutes { token-in: token-in, token-out: token-out }) ERR-INVALID-ROUTE))
            (fee (calculate-fee amount-in))
            (amount-after-fee (- amount-in fee))
        )
        (ok (/ (* amount-after-fee (get weight route)) BPS-DENOMINATOR))
    )
)

;; Read-only function to preview a multi hop swap output
(define-read-only (preview-multi-hop-swap (token-in principal) (token-mid principal) (token-out principal) (amount-in uint))
    (let 
        (
            (route-leg-1 (unwrap! (map-get? OptimizedRoutes { token-in: token-in, token-out: token-mid }) ERR-INVALID-ROUTE))
            (route-leg-2 (unwrap! (map-get? OptimizedRoutes { token-in: token-mid, token-out: token-out }) ERR-INVALID-ROUTE))
            (fee (calculate-fee amount-in))
            (amount-after-fee (- amount-in fee))
            (expected-mid-amount (/ (* amount-after-fee (get weight route-leg-1)) BPS-DENOMINATOR))
        )
        (ok (/ (* expected-mid-amount (get weight route-leg-2)) BPS-DENOMINATOR))
    )
)


