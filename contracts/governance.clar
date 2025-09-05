;; ClariBounty Governance Contract
;; Purpose: Admin-controlled settings and governance functions for the ClariBounty system
;; Author: ClariBounty Team

;; Import utils contract functions

;; ===== DATA STORAGE =====

;; Admin principal who can modify system settings
(define-data-var admin principal tx-sender)

;; Fee rate in basis points (e.g., 250 = 2.5%)
(define-data-var fee-rate uint u250)

;; Dispute window in blocks (time contributors have to open disputes)
(define-data-var dispute-window uint u1440) ;; ~10 days at 10min/block

;; Minimum stake amount required for participation
(define-data-var min-stake-amount uint u100000) ;; 0.1 STX

;; Maximum bounty duration in blocks
(define-data-var max-bounty-duration uint u144000) ;; ~100 days

;; System pause status for emergency stops
(define-data-var system-paused bool false)

;; Badge NFT threshold (successful bounties needed to earn a badge)
(define-data-var badge-threshold uint u5)

;; ===== PRIVATE FUNCTIONS =====

;; Check if caller is admin
(define-private (is-admin (caller principal))
    (is-eq caller (var-get admin))
)

;; ===== PUBLIC INTERFACE =====

;; Admin Functions

;; Set new admin (only current admin can do this)
;; @param new-admin: principal to set as new admin
;; @returns: (ok true) on success, error otherwise
(define-public (set-admin (new-admin principal))
    (begin
        (asserts! (is-admin tx-sender)
            (contract-call? .utils check-authorization tx-sender (var-get admin))
        )
        (var-set admin new-admin)
        (ok true)
    )
)

;; Set system fee rate
;; @param new-fee-rate: fee rate in basis points (max 1000 = 10%)
;; @returns: (ok true) on success, error otherwise
(define-public (set-fee-rate (new-fee-rate uint))
    (begin
        (asserts! (is-admin tx-sender)
            (contract-call? .utils check-authorization tx-sender (var-get admin))
        )
        (asserts! (<= new-fee-rate u1000) (err u101)) ;; Max 10% fee
        (var-set fee-rate new-fee-rate)
        (ok true)
    )
)

;; Set dispute window duration
;; @param new-dispute-window: dispute window in blocks (minimum 144 blocks)
;; @returns: (ok true) on success, error otherwise
(define-public (set-dispute-window (new-dispute-window uint))
    (begin
        (asserts! (is-admin tx-sender)
            (contract-call? .utils check-authorization tx-sender (var-get admin))
        )
        (asserts! (>= new-dispute-window u144) (err u101)) ;; Minimum ~1 day
        (var-set dispute-window new-dispute-window)
        (ok true)
    )
)

;; Set minimum stake amount
;; @param new-min-stake: minimum stake amount in uSTX
;; @returns: (ok true) on success, error otherwise
(define-public (set-min-stake-amount (new-min-stake uint))
    (begin
        (asserts! (is-admin tx-sender)
            (contract-call? .utils check-authorization tx-sender (var-get admin))
        )
        (asserts! (> new-min-stake u0) (err u101))
        (var-set min-stake-amount new-min-stake)
        (ok true)
    )
)

;; Set maximum bounty duration
;; @param new-max-duration: maximum duration in blocks
;; @returns: (ok true) on success, error otherwise
(define-public (set-max-bounty-duration (new-max-duration uint))
    (begin
        (asserts! (is-admin tx-sender)
            (contract-call? .utils check-authorization tx-sender (var-get admin))
        )
        (asserts! (> new-max-duration u0) (err u101))
        (var-set max-bounty-duration new-max-duration)
        (ok true)
    )
)

;; Pause or unpause the system
;; @param paused: true to pause, false to unpause
;; @returns: (ok true) on success, error otherwise
(define-public (set-system-paused (paused bool))
    (begin
        (asserts! (is-admin tx-sender)
            (contract-call? .utils check-authorization tx-sender (var-get admin))
        )
        (var-set system-paused paused)
        (ok true)
    )
)

;; Set badge threshold (successful bounties needed for badge)
;; @param new-threshold: number of successful bounties required
;; @returns: (ok true) on success, error otherwise
(define-public (set-badge-threshold (new-threshold uint))
    (begin
        (asserts! (is-admin tx-sender)
            (contract-call? .utils check-authorization tx-sender (var-get admin))
        )
        (asserts! (> new-threshold u0) (err u101))
        (var-set badge-threshold new-threshold)
        (ok true)
    )
)

;; ===== READ-ONLY FUNCTIONS =====

;; Get current admin
;; @returns: admin principal
(define-read-only (get-admin)
    (var-get admin)
)

;; Get current fee rate
;; @returns: fee rate in basis points
(define-read-only (get-fee-rate)
    (var-get fee-rate)
)

;; Get dispute window duration
;; @returns: dispute window in blocks
(define-read-only (get-dispute-window)
    (var-get dispute-window)
)

;; Get minimum stake amount
;; @returns: minimum stake amount in uSTX
(define-read-only (get-min-stake-amount)
    (var-get min-stake-amount)
)

;; Get maximum bounty duration
;; @returns: maximum bounty duration in blocks
(define-read-only (get-max-bounty-duration)
    (var-get max-bounty-duration)
)

;; Check if system is paused
;; @returns: true if paused, false otherwise
(define-read-only (is-system-paused)
    (var-get system-paused)
)

;; Get badge threshold
;; @returns: number of successful bounties needed for badge
(define-read-only (get-badge-threshold)
    (var-get badge-threshold)
)

;; Check if a principal is the admin
;; @param principal: principal to check
;; @returns: true if admin, false otherwise
(define-read-only (is-admin-check (principal principal))
    (is-admin principal)
)

;; Get all current governance settings as a tuple
;; @returns: tuple with all governance settings
(define-read-only (get-governance-info)
    {
        admin: (var-get admin),
        fee-rate: (var-get fee-rate),
        dispute-window: (var-get dispute-window),
        min-stake-amount: (var-get min-stake-amount),
        max-bounty-duration: (var-get max-bounty-duration),
        system-paused: (var-get system-paused),
        badge-threshold: (var-get badge-threshold),
    }
)
