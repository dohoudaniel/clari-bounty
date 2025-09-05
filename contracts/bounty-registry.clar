;; ClariBounty Registry Contract
;; Purpose: Core contract for creating, managing, and completing bounties
;; Author: ClariBounty Team

;; ===== DATA STORAGE =====

;; Map bounty-id to bounty details
(define-map bounties
    uint
    {
        owner: principal,
        title: (string-ascii 256),
        description: (string-ascii 1024),
        amount: uint,
        deadline: uint,
        status: uint, ;; 1=active, 2=completed, 3=cancelled, 4=disputed, 5=refunded
        created-at: uint,
        winner: (optional principal),
    }
)

;; Map bounty-id to submission details
(define-map submissions
    uint
    {
        bounty-id: uint,
        contributor: principal,
        submission-hash: (string-ascii 128),
        submitted-at: uint,
        status: uint, ;; 1=pending, 2=accepted, 3=rejected
    }
)

;; Map bounty-id to list of submission IDs
(define-map bounty-submissions
    uint
    (list 50 uint)
)

;; Next bounty ID counter
(define-data-var next-bounty-id uint u1)

;; Next submission ID counter
(define-data-var next-submission-id uint u1)

;; Total bounties created
(define-data-var total-bounties uint u0)

;; ===== PRIVATE FUNCTIONS =====

;; Check if bounty exists and is active
(define-private (is-bounty-active (bounty-id uint))
    (match (map-get? bounties bounty-id)
        bounty (and
            (is-eq (get status bounty) u1)
            (< stacks-block-height (get deadline bounty))
        )
        false
    )
)

;; ===== PUBLIC INTERFACE =====

;; Create a new bounty
;; @param title: bounty title
;; @param description: bounty description
;; @param amount: bounty amount in uSTX
;; @param deadline: deadline block height
;; @returns: (ok bounty-id) on success, error otherwise
(define-public (create-bounty
        (title (string-ascii 256))
        (description (string-ascii 1024))
        (amount uint)
        (deadline uint)
    )
    (let ((bounty-id (var-get next-bounty-id)))
        (begin
            ;; Check system not paused
            (asserts! (not (contract-call? .governance is-system-paused))
                (err u106)
            )

            ;; Validate inputs
            (try! (contract-call? .utils validate-string title u256))
            ;; Validate description length manually since it's longer than utils max
            (asserts! (and (> (len description) u0) (<= (len description) u1024))
                (err u101)
            )
            (try! (contract-call? .utils validate-amount amount u1000000))
            (try! (contract-call? .utils validate-deadline deadline))

            ;; Escrow the bounty amount
            (try! (contract-call? .escrow escrow-funds bounty-id tx-sender amount))

            ;; Create bounty record
            (map-set bounties bounty-id {
                owner: tx-sender,
                title: title,
                description: description,
                amount: amount,
                deadline: deadline,
                status: u1, ;; active
                created-at: stacks-block-height,
                winner: none,
            })

            ;; Update counters
            (var-set next-bounty-id (+ bounty-id u1))
            (var-set total-bounties (+ (var-get total-bounties) u1))

            (ok bounty-id)
        )
    )
)

;; Submit work for a bounty
;; @param bounty-id: the bounty to submit to
;; @param submission-hash: IPFS hash of the submission
;; @returns: (ok submission-id) on success, error otherwise
(define-public (submit-work
        (bounty-id uint)
        (submission-hash (string-ascii 128))
    )
    (let (
            (submission-id (var-get next-submission-id))
            (bounty (unwrap! (map-get? bounties bounty-id) (err u200)))
        )
        (begin
            ;; Check bounty is active
            (asserts! (is-bounty-active bounty-id) (err u204))

            ;; Validate submission hash
            (asserts! (> (len submission-hash) u0) (err u101))

            ;; Record participation and stake
            (try! (contract-call? .staking stake-for-bounty bounty-id tx-sender))
            (try! (contract-call? .reputation record-participation tx-sender))

            ;; Create submission record
            (map-set submissions submission-id {
                bounty-id: bounty-id,
                contributor: tx-sender,
                submission-hash: submission-hash,
                submitted-at: stacks-block-height,
                status: u1, ;; pending
            })

            ;; Add to bounty's submission list
            (let ((current-submissions (default-to (list) (map-get? bounty-submissions bounty-id))))
                (map-set bounty-submissions bounty-id
                    (unwrap!
                        (as-max-len? (append current-submissions submission-id)
                            u50
                        )
                        (err u502)
                    ))
            )

            ;; Update counter
            (var-set next-submission-id (+ submission-id u1))

            (ok submission-id)
        )
    )
)

;; Accept a submission and complete the bounty
;; @param submission-id: the submission to accept
;; @returns: (ok true) on success, error otherwise
(define-public (accept-submission (submission-id uint))
    (let (
            (submission (unwrap! (map-get? submissions submission-id) (err u205)))
            (bounty (unwrap! (map-get? bounties (get bounty-id submission)) (err u200)))
        )
        (begin
            ;; Only bounty owner can accept submissions
            (asserts! (is-eq tx-sender (get owner bounty)) (err u201))

            ;; Check bounty is still active
            (asserts! (is-eq (get status bounty) u1) (err u204))

            ;; Check submission is pending
            (asserts! (is-eq (get status submission) u1) (err u206))

            ;; Update submission status
            (map-set submissions submission-id (merge submission { status: u2 }))

            ;; Update bounty status and winner
            (map-set bounties (get bounty-id submission)
                (merge bounty {
                    status: u2,
                    winner: (some (get contributor submission)),
                })
            )

            ;; Release funds to contributor
            (try! (contract-call? .escrow release-funds (get bounty-id submission)
                (get contributor submission)
            ))

            ;; Award reputation points
            (try! (contract-call? .reputation add-reputation
                (get contributor submission) u20 (get amount bounty)
            ))

            ;; Release stakes for all participants
            (try! (contract-call? .staking release-stakes (get bounty-id submission)))

            (ok true)
        )
    )
)

;; ===== READ-ONLY FUNCTIONS =====

;; Get bounty details
;; @param bounty-id: the bounty ID
;; @returns: bounty details (optional)
(define-read-only (get-bounty (bounty-id uint))
    (map-get? bounties bounty-id)
)

;; Get submission details
;; @param submission-id: the submission ID
;; @returns: submission details (optional)
(define-read-only (get-submission (submission-id uint))
    (map-get? submissions submission-id)
)

;; Get all submissions for a bounty
;; @param bounty-id: the bounty ID
;; @returns: list of submission IDs
(define-read-only (get-bounty-submissions (bounty-id uint))
    (default-to (list) (map-get? bounty-submissions bounty-id))
)

;; Get total number of bounties
;; @returns: total bounties created
(define-read-only (get-total-bounties)
    (var-get total-bounties)
)

;; Check if bounty is active
;; @param bounty-id: the bounty ID
;; @returns: true if active, false otherwise
(define-read-only (is-active (bounty-id uint))
    (is-bounty-active bounty-id)
)
