;; ClariBounty Utils Contract
;; Purpose: Shared constants, error codes, and utility functions for the ClariBounty system
;; Author: ClariBounty Team

;; ===== CONSTANTS =====

;; System constants
(define-constant ONE_8 u100000000) ;; 10^8 for precision
(define-constant USTX_PER_STX u1000000) ;; 1 STX = 1,000,000 uSTX
(define-constant MAX_STRING_LEN u256)
(define-constant MAX_IPFS_HASH_LEN u128)
(define-constant MIN_BOUNTY_AMOUNT u1000000) ;; 1 STX minimum bounty
(define-constant DEFAULT_STAKE_AMOUNT u100000) ;; 0.1 STX default stake
(define-constant MAX_BOUNTY_DURATION u1000000) ;; Maximum blocks for bounty duration
(define-constant MIN_DISPUTE_WINDOW u144) ;; Minimum 144 blocks (~24 hours) dispute window

;; ===== ERROR CODES =====

;; Generic errors (u100-u199)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_PARAMS (err u101))
(define-constant ERR_INSUFFICIENT_FUNDS (err u102))
(define-constant ERR_TRANSFER_FAILED (err u103))
(define-constant ERR_ALREADY_EXISTS (err u104))
(define-constant ERR_NOT_FOUND (err u105))
(define-constant ERR_INVALID_STATE (err u106))
(define-constant ERR_EXPIRED (err u107))
(define-constant ERR_TOO_EARLY (err u108))

;; Bounty-specific errors (u200-u299)
(define-constant ERR_BOUNTY_NOT_FOUND (err u200))
(define-constant ERR_NOT_BOUNTY_OWNER (err u201))
(define-constant ERR_BOUNTY_EXPIRED (err u202))
(define-constant ERR_BOUNTY_ALREADY_CLAIMED (err u203))
(define-constant ERR_BOUNTY_NOT_ACTIVE (err u204))
(define-constant ERR_SUBMISSION_NOT_FOUND (err u205))
(define-constant ERR_ALREADY_SUBMITTED (err u206))
(define-constant ERR_BOUNTY_NOT_EXPIRED (err u207))

;; Staking-specific errors (u300-u399)
(define-constant ERR_INSUFFICIENT_STAKE (err u300))
(define-constant ERR_STAKE_NOT_FOUND (err u301))
(define-constant ERR_STAKE_LOCKED (err u302))
(define-constant ERR_ALREADY_STAKED (err u303))

;; Arbitration-specific errors (u400-u499)
(define-constant ERR_DISPUTE_NOT_FOUND (err u400))
(define-constant ERR_DISPUTE_ALREADY_EXISTS (err u401))
(define-constant ERR_DISPUTE_WINDOW_EXPIRED (err u402))
(define-constant ERR_NOT_ARBITRATOR (err u403))
(define-constant ERR_DISPUTE_ALREADY_RESOLVED (err u404))

;; NFT-specific errors (u500-u599)
(define-constant ERR_NFT_NOT_FOUND (err u500))
(define-constant ERR_NFT_ALREADY_EXISTS (err u501))
(define-constant ERR_INVALID_TOKEN_ID (err u502))

;; ===== DATA STRUCTURES =====

;; Bounty status enumeration
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_COMPLETED u2)
(define-constant STATUS_CANCELLED u3)
(define-constant STATUS_DISPUTED u4)
(define-constant STATUS_REFUNDED u5)

;; Submission status enumeration
(define-constant SUBMISSION_PENDING u1)
(define-constant SUBMISSION_ACCEPTED u2)
(define-constant SUBMISSION_REJECTED u3)

;; Dispute status enumeration
(define-constant DISPUTE_PENDING u1)
(define-constant DISPUTE_RESOLVED_FOR_CONTRIBUTOR u2)
(define-constant DISPUTE_RESOLVED_FOR_OWNER u3)

;; ===== PUBLIC INTERFACE =====

;; Public functions for validation and utilities

;; Validate that a string is not empty and within length limits
;; @param str: the string to validate
;; @param max-len: maximum allowed length
;; @returns: (ok true) if valid, error otherwise
(define-public (validate-string
        (str (string-ascii 256))
        (max-len uint)
    )
    (let ((str-len (len str)))
        (if (and (> str-len u0) (<= str-len max-len))
            (ok true)
            ERR_INVALID_PARAMS
        )
    )
)

;; Validate that an amount meets minimum requirements
;; @param amount: the amount to validate in uSTX
;; @param min-amount: minimum required amount
;; @returns: (ok true) if valid, error otherwise
(define-public (validate-amount
        (amount uint)
        (min-amount uint)
    )
    (if (>= amount min-amount)
        (ok true)
        ERR_INSUFFICIENT_FUNDS
    )
)

;; Validate that a deadline is in the future and within reasonable bounds
;; @param deadline: block height for deadline
;; @returns: (ok true) if valid, error otherwise
(define-public (validate-deadline (deadline uint))
    (let (
            (current-height stacks-block-height)
            (max-deadline (+ current-height MAX_BOUNTY_DURATION))
        )
        (if (and (> deadline current-height) (<= deadline max-deadline))
            (ok true)
            ERR_INVALID_PARAMS
        )
    )
)

;; Check if a bounty has expired based on deadline
;; @param deadline: the bounty deadline block height
;; @returns: true if expired, false otherwise
(define-public (is-expired (deadline uint))
    (ok (> stacks-block-height deadline))
)

;; Calculate fee amount based on a base amount and fee rate (in basis points)
;; @param amount: base amount in uSTX
;; @param fee-rate: fee rate in basis points (e.g., 250 = 2.5%)
;; @returns: fee amount in uSTX
(define-public (calculate-fee
        (amount uint)
        (fee-rate uint)
    )
    (ok (/ (* amount fee-rate) u10000))
)

;; Helper to check if caller is contract owner/admin
;; @param caller: principal to check
;; @param owner: expected owner principal
;; @returns: (ok true) if authorized, error otherwise
(define-public (check-authorization
        (caller principal)
        (owner principal)
    )
    (if (is-eq caller owner)
        (ok true)
        ERR_UNAUTHORIZED
    )
)

;; Convert STX to uSTX (micro-STX)
;; @param stx-amount: amount in STX
;; @returns: amount in uSTX
(define-public (stx-to-ustx (stx-amount uint))
    (ok (* stx-amount USTX_PER_STX))
)

;; Convert uSTX to STX (for display purposes)
;; @param ustx-amount: amount in uSTX
;; @returns: amount in STX
(define-public (ustx-to-stx (ustx-amount uint))
    (ok (/ ustx-amount USTX_PER_STX))
)
