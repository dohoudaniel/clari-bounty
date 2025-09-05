;; ClariBounty Escrow Contract
;; Purpose: Hold and manage funds for bounties with secure release mechanisms
;; Author: ClariBounty Team

;; Import utils contract functions

;; ===== DATA STORAGE =====

;; Map bounty-id to escrow amount
(define-map bounty-escrow
    uint
    uint
)

;; Map bounty-id to bounty owner
(define-map bounty-owner
    uint
    principal
)

;; Map bounty-id to escrow status
(define-map escrow-status
    uint
    uint
) ;; 1=active, 2=released, 3=refunded

;; Total escrowed amount across all bounties
(define-data-var total-escrowed uint u0)

;; Contract balance tracking
(define-data-var contract-balance uint u0)

;; ===== PRIVATE FUNCTIONS =====

;; Update contract balance tracking
(define-private (update-balance
        (amount uint)
        (increase bool)
    )
    (if increase
        (var-set contract-balance (+ (var-get contract-balance) amount))
        (var-set contract-balance (- (var-get contract-balance) amount))
    )
)

;; ===== PUBLIC INTERFACE =====

;; Escrow funds for a bounty (called by bounty registry)
;; @param bounty-id: unique identifier for the bounty
;; @param owner: principal who owns the bounty
;; @param amount: amount to escrow in uSTX
;; @returns: (ok true) on success, error otherwise
(define-public (escrow-funds
        (bounty-id uint)
        (owner principal)
        (amount uint)
    )
    (let ((current-escrow (default-to u0 (map-get? bounty-escrow bounty-id))))
        (begin
            ;; Check system not paused
            (asserts! (not (contract-call? .governance is-system-paused))
                (err u106)
            )

            ;; Verify bounty doesn't already have funds escrowed
            (asserts! (is-eq current-escrow u0) (err u104))

            ;; Validate amount
            (asserts! (> amount u0) (err u101))

            ;; Validate caller authorization (should be bounty registry or owner)
            (asserts!
                (or
                    (is-eq tx-sender owner)
                    (is-eq contract-caller .bounty-registry)
                )
                (err u100)
            )

            ;; Transfer funds from owner to this contract
            (match (stx-transfer? amount owner (as-contract tx-sender))
                success (begin
                    ;; Record escrow details
                    (map-set bounty-escrow bounty-id amount)
                    (map-set bounty-owner bounty-id owner)
                    (map-set escrow-status bounty-id u1) ;; active

                    ;; Update tracking
                    (var-set total-escrowed (+ (var-get total-escrowed) amount))
                    (update-balance amount true)

                    (ok true)
                )
                error (err u103)
            )
        )
    )
)

;; Release escrowed funds to contributor (called by bounty registry or arbitrator)
;; @param bounty-id: unique identifier for the bounty
;; @param recipient: principal to receive the funds
;; @returns: (ok true) on success, error otherwise
(define-public (release-funds
        (bounty-id uint)
        (recipient principal)
    )
    (let (
            (escrow-amount (default-to u0 (map-get? bounty-escrow bounty-id)))
            (status (default-to u0 (map-get? escrow-status bounty-id)))
            (fee-rate (contract-call? .governance get-fee-rate))
        )
        (begin
            ;; Verify escrow exists and is active
            (asserts! (> escrow-amount u0) (err u105))
            (asserts! (is-eq status u1) (err u106))

            ;; Verify caller authorization (bounty registry or arbitrator)
            (asserts!
                (or
                    (is-eq contract-caller .bounty-registry)
                    (is-eq contract-caller .arbitrator)
                )
                (err u100)
            )

            ;; Calculate fee and net amount
            (let (
                    (fee-amount (unwrap!
                        (contract-call? .utils calculate-fee escrow-amount
                            fee-rate
                        )
                        (err u101)
                    ))
                    (net-amount (- escrow-amount fee-amount))
                    (admin (contract-call? .governance get-admin))
                )
                ;; Transfer net amount to recipient
                (match (as-contract (stx-transfer? net-amount tx-sender recipient))
                    success-recipient
                    ;; Transfer fee to admin if fee > 0
                    (if (> fee-amount u0)
                        (match (as-contract (stx-transfer? fee-amount tx-sender admin))
                            success-admin (begin
                                ;; Update escrow status
                                (map-set escrow-status bounty-id u2) ;; released

                                ;; Update tracking
                                (var-set total-escrowed
                                    (- (var-get total-escrowed) escrow-amount)
                                )
                                (update-balance escrow-amount false)

                                (ok true)
                            )
                            error-admin (err u103)
                        )
                        (begin
                            ;; No fee case
                            (map-set escrow-status bounty-id u2) ;; released
                            (var-set total-escrowed
                                (- (var-get total-escrowed) escrow-amount)
                            )
                            (update-balance escrow-amount false)
                            (ok true)
                        )
                    )
                    error-recipient
                    (err u103)
                )
            )
        )
    )
)

;; Refund escrowed funds to original owner (called by bounty registry or arbitrator)
;; @param bounty-id: unique identifier for the bounty
;; @returns: (ok true) on success, error otherwise
(define-public (refund-funds (bounty-id uint))
    (let (
            (escrow-amount (default-to u0 (map-get? bounty-escrow bounty-id)))
            (owner (unwrap! (map-get? bounty-owner bounty-id) (err u105)))
            (status (default-to u0 (map-get? escrow-status bounty-id)))
        )
        (begin
            ;; Verify escrow exists and is active
            (asserts! (> escrow-amount u0) (err u105))
            (asserts! (is-eq status u1) (err u106))

            ;; Verify caller authorization (bounty registry or arbitrator)
            (asserts!
                (or
                    (is-eq contract-caller .bounty-registry)
                    (is-eq contract-caller .arbitrator)
                )
                (err u100)
            )

            ;; Refund full amount to owner (no fees on refunds)
            (match (as-contract (stx-transfer? escrow-amount tx-sender owner))
                success (begin
                    ;; Update escrow status
                    (map-set escrow-status bounty-id u3) ;; refunded

                    ;; Update tracking
                    (var-set total-escrowed
                        (- (var-get total-escrowed) escrow-amount)
                    )
                    (update-balance escrow-amount false)

                    (ok true)
                )
                error (err u103)
            )
        )
    )
)

;; ===== READ-ONLY FUNCTIONS =====

;; Get escrowed amount for a bounty
;; @param bounty-id: bounty identifier
;; @returns: escrowed amount in uSTX
(define-read-only (get-escrowed-amount (bounty-id uint))
    (default-to u0 (map-get? bounty-escrow bounty-id))
)

;; Get bounty owner
;; @param bounty-id: bounty identifier
;; @returns: owner principal (optional)
(define-read-only (get-bounty-owner (bounty-id uint))
    (map-get? bounty-owner bounty-id)
)

;; Get escrow status for a bounty
;; @param bounty-id: bounty identifier
;; @returns: status (1=active, 2=released, 3=refunded)
(define-read-only (get-escrow-status (bounty-id uint))
    (default-to u0 (map-get? escrow-status bounty-id))
)

;; Get total amount currently escrowed across all bounties
;; @returns: total escrowed amount in uSTX
(define-read-only (get-total-escrowed)
    (var-get total-escrowed)
)

;; Get contract balance
;; @returns: contract balance in uSTX
(define-read-only (get-contract-balance)
    (var-get contract-balance)
)

;; Get complete escrow info for a bounty
;; @param bounty-id: bounty identifier
;; @returns: tuple with escrow details
(define-read-only (get-escrow-info (bounty-id uint))
    {
        amount: (get-escrowed-amount bounty-id),
        owner: (get-bounty-owner bounty-id),
        status: (get-escrow-status bounty-id),
    }
)

;; Check if funds are available for release/refund
;; @param bounty-id: bounty identifier
;; @returns: true if funds can be moved, false otherwise
(define-read-only (can-release-funds (bounty-id uint))
    (let (
            (status (get-escrow-status bounty-id))
            (amount (get-escrowed-amount bounty-id))
        )
        (and (> amount u0) (is-eq status u1))
    )
)
