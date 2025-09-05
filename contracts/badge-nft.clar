
;; ClariBounty Badge NFT Contract
;; Purpose: Issue achievement badges as NFTs to successful contributors
;; Author: ClariBounty Team

;; ===== NFT DEFINITION =====

;; Define the badge NFT
(define-non-fungible-token badge-nft uint)

;; ===== DATA STORAGE =====

;; Map token-id to badge metadata
(define-map badge-metadata uint {
  recipient: principal,
  badge-type: (string-ascii 64),
  earned-at: uint,
  bounties-completed: uint
})

;; Map principal to list of badge token IDs they own
(define-map user-badges principal (list 50 uint))

;; Next token ID counter
(define-data-var next-token-id uint u1)

;; Total badges minted
(define-data-var total-badges uint u0)

;; ===== PRIVATE FUNCTIONS =====

;; Check if caller is authorized (reputation contract or admin)
(define-private (is-authorized (caller principal))
  (or (is-eq caller .reputation)
      (contract-call? .governance is-admin-check caller)))

;; ===== PUBLIC INTERFACE =====

;; Mint a badge NFT for a contributor
;; @param recipient: principal to receive the badge
;; @param badge-type: type of badge being awarded
;; @param bounties-completed: number of bounties completed
;; @returns: (ok token-id) on success, error otherwise
(define-public (mint-badge (recipient principal) (badge-type (string-ascii 64)) (bounties-completed uint))
  (let ((token-id (var-get next-token-id)))
    (begin
      ;; Only authorized contracts can mint badges
      (asserts! (is-authorized contract-caller) (err u100))

      ;; Validate badge type
      (asserts! (> (len badge-type) u0) (err u101))

      ;; Mint the NFT
      (try! (nft-mint? badge-nft token-id recipient))

      ;; Store badge metadata
      (map-set badge-metadata token-id {
        recipient: recipient,
        badge-type: badge-type,
        earned-at: stacks-block-height,
        bounties-completed: bounties-completed
      })

      ;; Update user's badge list
      (let ((current-badges (default-to (list) (map-get? user-badges recipient))))
        (map-set user-badges recipient (unwrap! (as-max-len? (append current-badges token-id) u50) (err u502))))

      ;; Update counters
      (var-set next-token-id (+ token-id u1))
      (var-set total-badges (+ (var-get total-badges) u1))

      (ok token-id))))

;; Transfer badge NFT (standard NFT transfer)
;; @param token-id: the badge token ID
;; @param sender: current owner
;; @param recipient: new owner
;; @returns: (ok true) on success, error otherwise
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    ;; Check ownership and authorization
    (asserts! (is-eq tx-sender sender) (err u100))
    (try! (nft-transfer? badge-nft token-id sender recipient))

    ;; Update badge lists
    (let ((sender-badges (default-to (list) (map-get? user-badges sender)))
          (recipient-badges (default-to (list) (map-get? user-badges recipient))))
      ;; Remove from sender's list
      (map-set user-badges sender (filter is-not-token-id sender-badges))
      ;; Add to recipient's list
      (map-set user-badges recipient (unwrap! (as-max-len? (append recipient-badges token-id) u50) (err u502))))

    (ok true)))

;; ===== READ-ONLY FUNCTIONS =====

;; Get badge metadata
;; @param token-id: the badge token ID
;; @returns: badge metadata (optional)
(define-read-only (get-badge-metadata (token-id uint))
  (map-get? badge-metadata token-id))

;; Get owner of a badge
;; @param token-id: the badge token ID
;; @returns: owner principal (optional)
(define-read-only (get-owner (token-id uint))
  (nft-get-owner? badge-nft token-id))

;; Get all badges owned by a user
;; @param user: the user principal
;; @returns: list of token IDs
(define-read-only (get-user-badges (user principal))
  (default-to (list) (map-get? user-badges user)))

;; Get total number of badges minted
;; @returns: total badges count
(define-read-only (get-total-badges)
  (var-get total-badges))

;; Get last token ID
;; @returns: last minted token ID
(define-read-only (get-last-token-id)
  (- (var-get next-token-id) u1))

;; ===== PRIVATE HELPER FUNCTIONS =====

;; Helper function for filtering token IDs
(define-private (is-not-token-id (id uint))
  (not (is-eq id (var-get next-token-id))))

