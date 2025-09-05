;; ClariBounty Reputation Contract
;; Purpose: Track contributor reputation points and success metrics
;; Author: ClariBounty Team

;; Import utils contract functions

;; ===== DATA STORAGE =====

;; Map principal to reputation points
(define-map reputation-points
    principal
    uint
)

;; Map principal to number of successful bounty completions
(define-map successful-completions
    principal
    uint
)

;; Map principal to total bounties participated in
(define-map total-participations
    principal
    uint
)

;; Map principal to total earnings in uSTX
(define-map total-earnings
    principal
    uint
)

;; Map principal to join timestamp
(define-map contributor-joined
    principal
    uint
)

;; Total reputation points awarded across all contributors
(define-data-var total-reputation-awarded uint u0)

;; Total number of unique contributors
(define-data-var total-contributors uint u0)

;; ===== PRIVATE FUNCTIONS =====

;; Check if contributor exists in system
(define-private (contributor-exists (contributor principal))
    (is-some (map-get? reputation-points contributor))
)

;; Initialize a new contributor
(define-private (initialize-contributor (contributor principal))
    (if (not (contributor-exists contributor))
        (begin
            (map-set reputation-points contributor u0)
            (map-set successful-completions contributor u0)
            (map-set total-participations contributor u0)
            (map-set total-earnings contributor u0)
            (map-set contributor-joined contributor stacks-block-height)
            (var-set total-contributors (+ (var-get total-contributors) u1))
            true
        )
        false
    )
)

;; ===== PUBLIC INTERFACE =====

;; Add reputation points for successful bounty completion
;; @param contributor: principal who completed the bounty
;; @param points: reputation points to award
;; @param earnings: amount earned from bounty in uSTX
;; @returns: (ok true) on success, error otherwise
(define-public (add-reputation
        (contributor principal)
        (points uint)
        (earnings uint)
    )
    (let (
            (current-points (default-to u0 (map-get? reputation-points contributor)))
            (current-completions (default-to u0 (map-get? successful-completions contributor)))
            (current-earnings (default-to u0 (map-get? total-earnings contributor)))
        )
        (begin
            ;; Only bounty registry or arbitrator can award reputation
            (asserts!
                (or
                    (is-eq contract-caller .bounty-registry)
                    (is-eq contract-caller .arbitrator)
                )
                (err u100)
            )

            ;; Validate parameters
            (asserts! (> points u0) (err u101))
            (asserts! (> earnings u0) (err u101))

            ;; Initialize contributor if new
            (initialize-contributor contributor)

            ;; Update reputation and completion stats
            (map-set reputation-points contributor (+ current-points points))
            (map-set successful-completions contributor
                (+ current-completions u1)
            )
            (map-set total-earnings contributor (+ current-earnings earnings))

            ;; Update global tracking
            (var-set total-reputation-awarded
                (+ (var-get total-reputation-awarded) points)
            )

            (ok true)
        )
    )
)

;; Record participation in a bounty (called when staking)
;; @param contributor: principal participating in bounty
;; @returns: (ok true) on success, error otherwise
(define-public (record-participation (contributor principal))
    (let ((current-participations (default-to u0 (map-get? total-participations contributor))))
        (begin
            ;; Only staking contract can record participation
            (asserts! (is-eq contract-caller .staking) (err u100))

            ;; Initialize contributor if new
            (initialize-contributor contributor)

            ;; Update participation count
            (map-set total-participations contributor
                (+ current-participations u1)
            )

            (ok true)
        )
    )
)

;; Penalize contributor for failed dispute or bad behavior
;; @param contributor: principal to penalize
;; @param penalty-points: points to deduct (cannot go below 0)
;; @returns: (ok true) on success, error otherwise
(define-public (penalize-contributor
        (contributor principal)
        (penalty-points uint)
    )
    (let ((current-points (default-to u0 (map-get? reputation-points contributor))))
        (begin
            ;; Only arbitrator can impose penalties
            (asserts! (is-eq contract-caller .arbitrator) (err u100))

            ;; Validate penalty
            (asserts! (> penalty-points u0) (err u101))

            ;; Apply penalty (minimum 0 points)
            (let ((new-points (if (>= current-points penalty-points)
                    (- current-points penalty-points)
                    u0
                )))
                (map-set reputation-points contributor new-points)
                (ok true)
            )
        )
    )
)

;; ===== READ-ONLY FUNCTIONS =====

;; Get reputation points for a contributor
;; @param contributor: principal to check
;; @returns: reputation points
(define-read-only (get-reputation (contributor principal))
    (default-to u0 (map-get? reputation-points contributor))
)

;; Get number of successful completions for a contributor
;; @param contributor: principal to check
;; @returns: number of successful bounty completions
(define-read-only (get-successful-completions (contributor principal))
    (default-to u0 (map-get? successful-completions contributor))
)
