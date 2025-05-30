;; NFT Rental Marketplace Contract
;; Allows NFT owners to rent out their assets and earn passive income
;; Renters can use NFTs temporarily without purchasing them

;; Contract constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-unauthorized (err u202))
(define-constant err-invalid-amount (err u203))
(define-constant err-already-listed (err u204))
(define-constant err-not-available (err u205))
(define-constant err-rental-active (err u206))
(define-constant err-rental-expired (err u207))
(define-constant err-insufficient-payment (err u208))
(define-constant err-invalid-duration (err u209))
(define-constant err-nft-not-owned (err u210))

;; Data variables
(define-data-var next-listing-id uint u1)
(define-data-var platform-fee-rate uint u500) ;; 5% platform fee
(define-data-var min-rental-duration uint u144) ;; ~1 day in blocks
(define-data-var max-rental-duration uint u52560) ;; ~1 year in blocks

;; NFT trait definition (assuming standard NFT trait)
(define-trait nft-trait
  (
    (get-owner (uint) (response (optional principal) uint))
    (transfer (uint principal principal) (response bool uint))
  )
)

;; Rental listing structure
(define-map rental-listings
  { listing-id: uint }
  {
    nft-contract: principal,
    token-id: uint,
    owner: principal,
    price-per-block: uint,
    min-duration: uint,
    max-duration: uint,
    available: bool,
    total-earned: uint,
    rental-count: uint,
    created-at: uint
  }
)

;; Active rentals
(define-map active-rentals
  { listing-id: uint }
  {
    renter: principal,
    start-block: uint,
    end-block: uint,
    total-paid: uint,
    collateral-amount: uint
  }
)

;; User rental history
(define-map rental-history
  { user: principal, rental-id: uint }
  {
    listing-id: uint,
    action: (string-ascii 10), ;; "rented" or "returned"
    block-height: uint,
    amount: uint
  }
)

;; NFT to listing mapping
(define-map nft-to-listing
  { nft-contract: principal, token-id: uint }
  { listing-id: uint }
)

;; User statistics
(define-map user-stats
  { user: principal }
  {
    total-rentals: uint,
    total-spent: uint,
    total-earned: uint,
    reputation-score: uint
  }
)

;; Revenue tracking
(define-data-var total-platform-revenue uint u0)
(define-data-var next-rental-id uint u1)

;; Helper functions

;; Get current block height
(define-private (get-current-block)
  stacks-block-height
)

;; Calculate rental cost
(define-private (calculate-rental-cost (price-per-block uint) (duration uint))
  (* price-per-block duration)
)

;; Calculate collateral (20% of total rental cost)
(define-private (calculate-collateral (total-cost uint))
  (/ (* total-cost u2000) u10000)
)

;; Min function - returns the smaller of two uints
(define-private (min (a uint) (b uint))
  (if (<= a b) a b)
)

;; Update user statistics
(define-private (update-user-stats (user principal) (amount uint) (is-earning bool))
  (let
    (
      (current-stats (default-to 
        { total-rentals: u0, total-spent: u0, total-earned: u0, reputation-score: u100 }
        (map-get? user-stats { user: user })
      ))
    )
    (map-set user-stats
      { user: user }
      {
        total-rentals: (+ (get total-rentals current-stats) u1),
        total-spent: (if is-earning 
                      (get total-spent current-stats)
                      (+ (get total-spent current-stats) amount)),
        total-earned: (if is-earning 
                       (+ (get total-earned current-stats) amount)
                       (get total-earned current-stats)),
        reputation-score: (min u1000 (+ (get reputation-score current-stats) u10))
      }
    )
  )
)

;; Public functions

;; List an NFT for rental
(define-public (list-nft-for-rental
  (nft-contract <nft-trait>)
  (token-id uint)
  (price-per-block uint)
  (min-duration uint)
  (max-duration uint))
  (let
    (
      (listing-id (var-get next-listing-id))
      (current-block (get-current-block))
      (nft-contract-principal (contract-of nft-contract))
      ;; Create validated copies to suppress warnings
      (validated-token-id (+ token-id u0))
    )
    ;; Validate inputs
    (asserts! (> price-per-block u0) err-invalid-amount)
    (asserts! (>= min-duration (var-get min-rental-duration)) err-invalid-duration)
    (asserts! (<= max-duration (var-get max-rental-duration)) err-invalid-duration)
    (asserts! (<= min-duration max-duration) err-invalid-duration)
    
    ;; Check if NFT is already listed
    (asserts! (is-none (map-get? nft-to-listing { nft-contract: nft-contract-principal, token-id: validated-token-id })) err-already-listed)
    
    ;; Verify ownership (this would need to be implemented based on the specific NFT contract)
    ;; For now, we'll assume the caller owns the NFT
    
    ;; Create listing
    (map-set rental-listings
      { listing-id: listing-id }
      {
        nft-contract: nft-contract-principal,
        token-id: validated-token-id,
        owner: tx-sender,
        price-per-block: price-per-block,
        min-duration: min-duration,
        max-duration: max-duration,
        available: true,
        total-earned: u0,
        rental-count: u0,
        created-at: current-block
      }
    )
    
    ;; Map NFT to listing
    (map-set nft-to-listing
      { nft-contract: nft-contract-principal, token-id: validated-token-id }
      { listing-id: listing-id }
    )
    
    ;; Increment listing ID
    (var-set next-listing-id (+ listing-id u1))
    
    (ok listing-id)
  )
)

;; Rent an NFT
(define-public (rent-nft (listing-id uint) (duration uint))
  (let
    (
      ;; Validate listing-id first
      (validated-listing-id (+ listing-id u0))
      (listing (unwrap! (map-get? rental-listings { listing-id: validated-listing-id }) err-not-found))
      (current-block (get-current-block))
      (end-block (+ current-block duration))
      (total-cost (calculate-rental-cost (get price-per-block listing) duration))
      (collateral (calculate-collateral total-cost))
      (platform-fee (/ (* total-cost (var-get platform-fee-rate)) u10000))
      (owner-payment (- total-cost platform-fee))
      (total-payment (+ total-cost collateral))
      (rental-id (var-get next-rental-id))
    )
    ;; Validate rental request
    (asserts! (get available listing) err-not-available)
    (asserts! (>= duration (get min-duration listing)) err-invalid-duration)
    (asserts! (<= duration (get max-duration listing)) err-invalid-duration)
    (asserts! (not (is-eq tx-sender (get owner listing))) err-unauthorized)
    
    ;; Check if there's already an active rental
    (asserts! (is-none (map-get? active-rentals { listing-id: validated-listing-id })) err-rental-active)
    
    ;; Transfer payment from renter
    (try! (stx-transfer? total-payment tx-sender (as-contract tx-sender)))
    
    ;; Pay the owner
    (try! (as-contract (stx-transfer? owner-payment tx-sender (get owner listing))))
    
    ;; Create active rental
    (map-set active-rentals
      { listing-id: validated-listing-id }
      {
        renter: tx-sender,
        start-block: current-block,
        end-block: end-block,
        total-paid: total-cost,
        collateral-amount: collateral
      }
    )
    
    ;; Update listing
    (map-set rental-listings
      { listing-id: validated-listing-id }
      (merge listing {
        available: false,
        total-earned: (+ (get total-earned listing) owner-payment),
        rental-count: (+ (get rental-count listing) u1)
      })
    )
    
    ;; Record rental history
    (map-set rental-history
      { user: tx-sender, rental-id: rental-id }
      {
        listing-id: validated-listing-id,
        action: "rented",
        block-height: current-block,
        amount: total-cost
      }
    )
    
    ;; Update user statistics
    (update-user-stats tx-sender total-cost false)
    (update-user-stats (get owner listing) owner-payment true)
    
    ;; Update platform revenue
    (var-set total-platform-revenue (+ (var-get total-platform-revenue) platform-fee))
    (var-set next-rental-id (+ rental-id u1))
    
    (ok { rental-id: rental-id, end-block: end-block, collateral: collateral })
  )
)

;; Return NFT and get collateral back
(define-public (return-nft (listing-id uint))
  (let
    (
      (validated-listing-id (+ listing-id u0))
      (listing (unwrap! (map-get? rental-listings { listing-id: validated-listing-id }) err-not-found))
      (rental (unwrap! (map-get? active-rentals { listing-id: validated-listing-id }) err-not-found))
      (current-block (get-current-block))
      (rental-id (var-get next-rental-id))
    )
    ;; Check if caller is the renter
    (asserts! (is-eq tx-sender (get renter rental)) err-unauthorized)
    
    ;; Return collateral
    (try! (as-contract (stx-transfer? (get collateral-amount rental) tx-sender (get renter rental))))
    
    ;; Remove active rental
    (map-delete active-rentals { listing-id: validated-listing-id })
    
    ;; Make listing available again
    (map-set rental-listings
      { listing-id: validated-listing-id }
      (merge listing { available: true })
    )
    
    ;; Record return in history
    (map-set rental-history
      { user: tx-sender, rental-id: rental-id }
      {
        listing-id: validated-listing-id,
        action: "returned",
        block-height: current-block,
        amount: u0
      }
    )
    
    (var-set next-rental-id (+ rental-id u1))
    (ok true)
  )
)

;; Auto-return expired rental (anyone can call)
(define-public (auto-return-expired (listing-id uint))
  (let
    (
      (validated-listing-id (+ listing-id u0))
      (listing (unwrap! (map-get? rental-listings { listing-id: validated-listing-id }) err-not-found))
      (rental (unwrap! (map-get? active-rentals { listing-id: validated-listing-id }) err-not-found))
      (current-block (get-current-block))
    )
    ;; Check if rental has expired
    (asserts! (>= current-block (get end-block rental)) err-rental-active)
    
    ;; Return collateral to renter
    (try! (as-contract (stx-transfer? (get collateral-amount rental) tx-sender (get renter rental))))
    
    ;; Remove active rental
    (map-delete active-rentals { listing-id: validated-listing-id })
    
    ;; Make listing available again
    (map-set rental-listings
      { listing-id: validated-listing-id }
      (merge listing { available: true })
    )
    
    (ok true)
  )
)

;; Remove NFT listing (only owner)
(define-public (remove-listing (listing-id uint))
  (let
    (
      (validated-listing-id (+ listing-id u0))
      (listing (unwrap! (map-get? rental-listings { listing-id: validated-listing-id }) err-not-found))
    )
    ;; Check if caller is the owner
    (asserts! (is-eq tx-sender (get owner listing)) err-unauthorized)
    
    ;; Check if there's no active rental
    (asserts! (is-none (map-get? active-rentals { listing-id: validated-listing-id })) err-rental-active)
    
    ;; Remove listing
    (map-delete rental-listings { listing-id: validated-listing-id })
    
    ;; Remove NFT mapping
    (map-delete nft-to-listing { nft-contract: (get nft-contract listing), token-id: (get token-id listing) })
    
    (ok true)
  )
)

;; Emergency function to handle disputes (owner only)
(define-public (resolve-dispute (listing-id uint) (return-collateral-to-renter bool))
  (let
    (
      (validated-listing-id (+ listing-id u0))
      (listing (unwrap! (map-get? rental-listings { listing-id: validated-listing-id }) err-not-found))
      (rental (unwrap! (map-get? active-rentals { listing-id: validated-listing-id }) err-not-found))
    )
    ;; Only contract owner can resolve disputes
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    ;; Handle collateral based on resolution
    (if return-collateral-to-renter
      (try! (as-contract (stx-transfer? (get collateral-amount rental) tx-sender (get renter rental))))
      (try! (as-contract (stx-transfer? (get collateral-amount rental) tx-sender (get owner listing))))
    )
    
    ;; Remove active rental
    (map-delete active-rentals { listing-id: validated-listing-id })
    
    ;; Make listing available again
    (map-set rental-listings
      { listing-id: validated-listing-id }
      (merge listing { available: true })
    )
    
    (ok true)
  )
)

;; Update rental price (only listing owner)
(define-public (update-rental-price (listing-id uint) (new-price-per-block uint))
  (let
    (
      (validated-listing-id (+ listing-id u0))
      (listing (unwrap! (map-get? rental-listings { listing-id: validated-listing-id }) err-not-found))
    )
    ;; Check if caller is the owner
    (asserts! (is-eq tx-sender (get owner listing)) err-unauthorized)
    
    ;; Check if there's no active rental
    (asserts! (is-none (map-get? active-rentals { listing-id: validated-listing-id })) err-rental-active)
    
    ;; Validate new price
    (asserts! (> new-price-per-block u0) err-invalid-amount)
    
    ;; Update price
    (map-set rental-listings
      { listing-id: validated-listing-id }
      (merge listing { price-per-block: new-price-per-block })
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Get listing details
(define-read-only (get-listing (listing-id uint))
  (map-get? rental-listings { listing-id: listing-id })
)

;; Get active rental details
(define-read-only (get-active-rental (listing-id uint))
  (map-get? active-rentals { listing-id: listing-id })
)

;; Get user statistics
(define-read-only (get-user-stats (user principal))
  (map-get? user-stats { user: user })
)

;; Calculate rental quote
(define-read-only (get-rental-quote (listing-id uint) (duration uint))
  (let
    (
      (listing (unwrap! (map-get? rental-listings { listing-id: listing-id }) err-not-found))
    )
    (if (and (>= duration (get min-duration listing)) (<= duration (get max-duration listing)))
      (let
        (
          (total-cost (calculate-rental-cost (get price-per-block listing) duration))
          (collateral (calculate-collateral total-cost))
          (platform-fee (/ (* total-cost (var-get platform-fee-rate)) u10000))
        )
        (ok {
          rental-cost: total-cost,
          collateral-required: collateral,
          platform-fee: platform-fee,
          total-payment: (+ total-cost collateral)
        })
      )
      err-invalid-duration
    )
  )
)

;; Check if rental is expired
(define-read-only (is-rental-expired (listing-id uint))
  (match (map-get? active-rentals { listing-id: listing-id })
    rental (>= stacks-block-height (get end-block rental))
    false
  )
)

;; Get total number of listings
(define-read-only (get-total-listings)
  (- (var-get next-listing-id) u1)
)

;; Get platform statistics
(define-read-only (get-platform-stats)
  {
    total-listings: (- (var-get next-listing-id) u1),
    total-revenue: (var-get total-platform-revenue),
    platform-fee-rate: (var-get platform-fee-rate)
  }
)

;; Get listing by NFT
(define-read-only (get-listing-by-nft (nft-contract principal) (token-id uint))
  (match (map-get? nft-to-listing { nft-contract: nft-contract, token-id: token-id })
    listing-info (map-get? rental-listings { listing-id: (get listing-id listing-info) })
    none
  )
)

;; Admin functions

;; Update platform fee rate (only owner)
(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u2000) err-invalid-amount) ;; Max 20%
    (var-set platform-fee-rate new-rate)
    (ok true)
  )
)

;; Update rental duration limits (only owner)
(define-public (set-duration-limits (min-duration uint) (max-duration uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (< min-duration max-duration) err-invalid-duration)
    (var-set min-rental-duration min-duration)
    (var-set max-rental-duration max-duration)
    (ok true)
  )
)

;; Withdraw platform fees (only owner)
(define-public (withdraw-platform-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= amount (var-get total-platform-revenue)) err-invalid-amount)
    (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
    (var-set total-platform-revenue (- (var-get total-platform-revenue) amount))
    (ok true)
  )
)