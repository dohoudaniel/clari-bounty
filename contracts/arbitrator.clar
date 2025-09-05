
;; ClariBounty Arbitrator Contract
;; Purpose: Handle disputes and arbitration for bounty submissions
;; Author: ClariBounty Team

;; ===== DATA STORAGE =====

;; Map dispute-id to dispute details
(define-map disputes uint {
  bounty-id: uint,
  contributor: principal,
  owner: principal,
  created-at: uint,
  status: uint, ;; 1=pending, 2=resolved-for-contributor, 3=resolved-for-owner
  resolution: (optional (string-ascii 256))
})

;; Map bounty-id to dispute-id (one dispute per bounty)
(define-map bounty-disputes uint uint)

;; Next dispute ID counter
(define-data-var next-dispute-id uint u1)

;; Total disputes created
(define-data-var total-disputes uint u0)

;; ===== PRIVATE FUNCTIONS =====

;; Check if caller is admin (from governance contract)
(define-private (is-admin (caller principal))
  (contract-call? .governance is-admin-check caller))

;; ===== PUBLIC INTERFACE =====

;; Create a dispute for a bounty submission
;; @param bounty-id: the bounty being disputed
;; @param contributor: the contributor involved
;; @param owner: the bounty owner
;; @returns: (ok dispute-id) on success, error otherwise
(define-public (create-dispute (bounty-id uint) (contributor principal) (owner principal))
  (let ((dispute-id (var-get next-dispute-id)))
    (begin
      ;; Check if dispute already exists for this bounty
      (asserts! (is-none (map-get? bounty-disputes bounty-id)) (err u401))

      ;; Only bounty registry can create disputes
      (asserts! (is-eq contract-caller .bounty-registry) (err u100))

      ;; Create dispute record
      (map-set disputes dispute-id {
        bounty-id: bounty-id,
        contributor: contributor,
        owner: owner,
        created-at: stacks-block-height,
        status: u1, ;; pending
        resolution: none
      })

      ;; Map bounty to dispute
      (map-set bounty-disputes bounty-id dispute-id)

      ;; Update counters
      (var-set next-dispute-id (+ dispute-id u1))
      (var-set total-disputes (+ (var-get total-disputes) u1))

      (ok dispute-id))))

;; Resolve a dispute (admin only)
;; @param dispute-id: the dispute to resolve
;; @param resolution-for-contributor: true if resolved in favor of contributor
;; @param resolution-note: optional resolution explanation
;; @returns: (ok true) on success, error otherwise
(define-public (resolve-dispute (dispute-id uint) (resolution-for-contributor bool) (resolution-note (optional (string-ascii 256))))
  (let ((dispute (unwrap! (map-get? disputes dispute-id) (err u400))))
    (begin
      ;; Only admin can resolve disputes
      (asserts! (is-admin tx-sender) (err u403))

      ;; Check dispute is still pending
      (asserts! (is-eq (get status dispute) u1) (err u404))

      ;; Update dispute with resolution
      (map-set disputes dispute-id (merge dispute {
        status: (if resolution-for-contributor u2 u3),
        resolution: resolution-note
      }))

      ;; Call appropriate contract functions based on resolution
      (if resolution-for-contributor
          ;; Release funds to contributor and award reputation
          (begin
            (try! (contract-call? .escrow release-funds (get bounty-id dispute) (get contributor dispute)))
            (try! (contract-call? .reputation add-reputation (get contributor dispute) u10 u0)))
          ;; Refund to owner and penalize contributor
          (begin
            (try! (contract-call? .escrow refund-funds (get bounty-id dispute)))
            (try! (contract-call? .reputation penalize-contributor (get contributor dispute) u5))))

      (ok true))))

;; ===== READ-ONLY FUNCTIONS =====

;; Get dispute details
;; @param dispute-id: the dispute ID
;; @returns: dispute details (optional)
(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes dispute-id))

;; Get dispute ID for a bounty
;; @param bounty-id: the bounty ID
;; @returns: dispute ID (optional)
(define-read-only (get-bounty-dispute (bounty-id uint))
  (map-get? bounty-disputes bounty-id))

;; Get total number of disputes
;; @returns: total disputes created
(define-read-only (get-total-disputes)
  (var-get total-disputes))

;; Check if a bounty has an active dispute
;; @param bounty-id: the bounty ID
;; @returns: true if dispute exists and is pending
(define-read-only (has-active-dispute (bounty-id uint))
  (match (map-get? bounty-disputes bounty-id)
    dispute-id (match (map-get? disputes dispute-id)
                 dispute (is-eq (get status dispute) u1)
                 false)
    false))
