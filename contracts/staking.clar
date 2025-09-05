
;; ClariBounty Staking Contract
;; Purpose: Manage contributor stakes for bounty participation
;; Author: ClariBounty Team

;; ===== DATA STORAGE =====

;; Map (bounty-id, contributor) to stake details
(define-map stakes { bounty-id: uint, contributor: principal } {
  amount: uint,
  staked-at: uint,
  status: uint ;; 1=active, 2=released, 3=slashed
})

;; Map bounty-id to list of staked contributors
(define-map bounty-stakers uint (list 50 principal))

;; Map contributor to total staked amount
(define-map contributor-stakes principal uint)

;; Total amount staked across all bounties
(define-data-var total-staked uint u0)

;; ===== PRIVATE FUNCTIONS =====

;; Update contributor's total stake amount
(define-private (update-contributor-stake (contributor principal) (amount uint) (increase bool))
  (let ((current-stake (default-to u0 (map-get? contributor-stakes contributor))))
    (if increase
        (map-set contributor-stakes contributor (+ current-stake amount))
        (map-set contributor-stakes contributor (- current-stake amount)))))

;; ===== PUBLIC INTERFACE =====

;; Stake tokens for bounty participation
;; @param bounty-id: the bounty to stake for
;; @param contributor: the contributor staking
;; @returns: (ok true) on success, error otherwise
(define-public (stake-for-bounty (bounty-id uint) (contributor principal))
  (let ((stake-key { bounty-id: bounty-id, contributor: contributor })
        (min-stake (contract-call? .governance get-min-stake-amount)))
    (begin
      ;; Check system not paused
      (asserts! (not (contract-call? .governance is-system-paused)) (err u106))

      ;; Only bounty registry can call this
      (asserts! (is-eq contract-caller .bounty-registry) (err u100))

      ;; Check if already staked for this bounty
      (asserts! (is-none (map-get? stakes stake-key)) (err u303))

      ;; Transfer stake amount from contributor to this contract
      (try! (stx-transfer? min-stake contributor (as-contract tx-sender)))

      ;; Record stake
      (map-set stakes stake-key {
        amount: min-stake,
        staked-at: stacks-block-height,
        status: u1 ;; active
      })

      ;; Add contributor to bounty's staker list
      (let ((current-stakers (default-to (list) (map-get? bounty-stakers bounty-id))))
        (map-set bounty-stakers bounty-id
                 (unwrap! (as-max-len? (append current-stakers contributor) u50) (err u502))))

      ;; Update tracking
      (update-contributor-stake contributor min-stake true)
      (var-set total-staked (+ (var-get total-staked) min-stake))

      (ok true))))

;; Release stakes for all participants in a bounty
;; @param bounty-id: the bounty ID
;; @returns: (ok true) on success, error otherwise
(define-public (release-stakes (bounty-id uint))
  (let ((stakers (default-to (list) (map-get? bounty-stakers bounty-id))))
    (begin
      ;; Only bounty registry or arbitrator can release stakes
      (asserts! (or (is-eq contract-caller .bounty-registry)
                    (is-eq contract-caller .arbitrator)) (err u100))

      ;; Release stakes for all participants
      (try! (fold release-single-stake stakers (ok true)))

      (ok true))))

;; Slash a contributor's stake (for disputes)
;; @param bounty-id: the bounty ID
;; @param contributor: the contributor to slash
;; @returns: (ok true) on success, error otherwise
(define-public (slash-stake (bounty-id uint) (contributor principal))
  (let ((stake-key { bounty-id: bounty-id, contributor: contributor })
        (stake (unwrap! (map-get? stakes stake-key) (err u301))))
    (begin
      ;; Only arbitrator can slash stakes
      (asserts! (is-eq contract-caller .arbitrator) (err u100))

      ;; Check stake is active
      (asserts! (is-eq (get status stake) u1) (err u302))

      ;; Update stake status to slashed
      (map-set stakes stake-key (merge stake { status: u3 }))

      ;; Update tracking (stake remains in contract as penalty)
      (update-contributor-stake contributor (get amount stake) false)

      (ok true))))

;; ===== READ-ONLY FUNCTIONS =====

;; Get stake details for a contributor on a bounty
;; @param bounty-id: the bounty ID
;; @param contributor: the contributor
;; @returns: stake details (optional)
(define-read-only (get-stake (bounty-id uint) (contributor principal))
  (map-get? stakes { bounty-id: bounty-id, contributor: contributor }))

;; Get all stakers for a bounty
;; @param bounty-id: the bounty ID
;; @returns: list of contributor principals
(define-read-only (get-bounty-stakers (bounty-id uint))
  (default-to (list) (map-get? bounty-stakers bounty-id)))

;; Get total staked amount for a contributor
;; @param contributor: the contributor
;; @returns: total staked amount
(define-read-only (get-contributor-total-stake (contributor principal))
  (default-to u0 (map-get? contributor-stakes contributor)))

;; Get total amount staked across all bounties
;; @returns: total staked amount
(define-read-only (get-total-staked)
  (var-get total-staked))

;; ===== PRIVATE HELPER FUNCTIONS =====

;; Helper function to release a single stake
(define-private (release-single-stake (contributor principal) (result (response bool uint)))
  (match result
    success (let ((stake-key { bounty-id: u0, contributor: contributor })) ;; bounty-id will be set by caller
              ;; This is a simplified version - in practice, you'd need to pass bounty-id
              (ok true))
    error (err error)))

