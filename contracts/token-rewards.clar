;; Token Rewards Smart Contract
;; Manages Compost Credit Token (CCT) minting, distribution, and management

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INSUFFICIENT_BALANCE (err u201))
(define-constant ERR_INVALID_AMOUNT (err u202))
(define-constant ERR_REWARD_ALREADY_CLAIMED (err u203))
(define-constant ERR_ACTIVITY_NOT_VERIFIED (err u204))
(define-constant ERR_TOKEN_NOT_FOUND (err u205))
(define-constant ERR_INVALID_RECIPIENT (err u206))
(define-constant ERR_MINTING_DISABLED (err u207))

;; Token metadata
(define-constant TOKEN_NAME "Compost Credit Token")
(define-constant TOKEN_SYMBOL "CCT")
(define-constant TOKEN_DECIMALS u6)
(define-constant TOKEN_URI u"https://compostix.eco/token-metadata")

;; Total supply and distribution constants
(define-constant MAX_TOTAL_SUPPLY u100000000000000) ;; 100M tokens with 6 decimals
(define-constant REWARD_POOL_PERCENTAGE u60) ;; 60% for user rewards
(define-constant DEV_POOL_PERCENTAGE u20) ;; 20% for development
(define-constant COMMUNITY_POOL_PERCENTAGE u15) ;; 15% for community grants
(define-constant VALIDATOR_POOL_PERCENTAGE u5) ;; 5% for validators

;; Data Variables
(define-data-var total-supply uint u0)
(define-data-var contract-owner principal tx-sender)
(define-data-var minting-enabled bool true)
(define-data-var reward-pool-balance uint u0)
(define-data-var dev-pool-balance uint u0)
(define-data-var community-pool-balance uint u0)
(define-data-var validator-pool-balance uint u0)
(define-data-var next-reward-id uint u1)

;; Token balances
(define-map token-balances principal uint)

;; Token allowances for spending
(define-map token-allowances { owner: principal, spender: principal } uint)

;; Reward claims tracking
(define-map reward-claims { user: principal, activity-id: uint } {
  amount: uint,
  claimed-block: uint,
  claim-id: uint
})

;; Staking positions
(define-map stakes principal {
  amount: uint,
  start-block: uint,
  lock-period: uint,
  rewards-earned: uint
})

;; Governance proposals (simplified)
(define-map proposals uint {
  proposer: principal,
  title: (string-ascii 100),
  description: (string-ascii 500),
  votes-for: uint,
  votes-against: uint,
  voting-ends: uint,
  executed: bool
})

;; User voting records
(define-map votes { proposal-id: uint, voter: principal } {
  vote: bool,
  voting-power: uint,
  vote-block: uint
})

;; Administrative functions

;; Set new contract owner
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

;; Toggle minting capability
(define-public (toggle-minting (enabled bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (var-set minting-enabled enabled)
    (ok true)
  )
)

;; Initialize token pools
(define-public (initialize-pools)
  (let (
    (total-allocation MAX_TOTAL_SUPPLY)
    (reward-allocation (/ (* total-allocation REWARD_POOL_PERCENTAGE) u100))
    (dev-allocation (/ (* total-allocation DEV_POOL_PERCENTAGE) u100))
    (community-allocation (/ (* total-allocation COMMUNITY_POOL_PERCENTAGE) u100))
    (validator-allocation (/ (* total-allocation VALIDATOR_POOL_PERCENTAGE) u100))
  )
    ;; Only owner can initialize
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    
    ;; Set pool balances
    (var-set reward-pool-balance reward-allocation)
    (var-set dev-pool-balance dev-allocation)
    (var-set community-pool-balance community-allocation)
    (var-set validator-pool-balance validator-allocation)
    
    ;; Mint initial supply to contract
    (var-set total-supply total-allocation)
    (map-set token-balances (as-contract tx-sender) total-allocation)
    
    (ok true)
  )
)

;; Core token functions

;; Get token balance
(define-read-only (get-balance (owner principal))
  (default-to u0 (map-get? token-balances owner))
)

;; Get total supply
(define-read-only (get-total-supply)
  (var-get total-supply)
)

;; Get token metadata
(define-read-only (get-token-info)
  {
    name: TOKEN_NAME,
    symbol: TOKEN_SYMBOL,
    decimals: TOKEN_DECIMALS,
    total-supply: (var-get total-supply)
  }
)

;; Transfer tokens
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (let (
    (sender-balance (get-balance sender))
  )
    ;; Validate transfer
    (asserts! (is-eq tx-sender sender) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (not (is-eq sender recipient)) ERR_INVALID_RECIPIENT)
    
    ;; Update balances
    (map-set token-balances sender (- sender-balance amount))
    (map-set token-balances recipient (+ (get-balance recipient) amount))
    
    ;; Emit transfer event (simplified)
    (print { event: "transfer", from: sender, to: recipient, amount: amount })
    
    (ok true)
  )
)

;; Reward distribution functions

;; Claim reward for verified composting activity
(define-public (claim-reward (activity-id uint) (expected-amount uint))
  (let (
    (claim-key { user: tx-sender, activity-id: activity-id })
    (reward-id (var-get next-reward-id))
  )
    ;; Check if already claimed
    (asserts! (is-none (map-get? reward-claims claim-key)) ERR_REWARD_ALREADY_CLAIMED)
    
    ;; Validate amount (in real implementation, this would check with compost-tracker)
    (asserts! (> expected-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= expected-amount u10000000) ERR_INVALID_AMOUNT) ;; Max 10 CCT per claim
    
    ;; Check reward pool has sufficient balance
    (asserts! (>= (var-get reward-pool-balance) expected-amount) ERR_INSUFFICIENT_BALANCE)
    
    ;; Update reward pool balance
    (var-set reward-pool-balance (- (var-get reward-pool-balance) expected-amount))
    
    ;; Transfer tokens to user
    (map-set token-balances tx-sender (+ (get-balance tx-sender) expected-amount))
    
    ;; Record the claim
    (map-set reward-claims claim-key {
      amount: expected-amount,
      claimed-block: stacks-block-height,
      claim-id: reward-id
    })
    
    ;; Update reward ID counter
    (var-set next-reward-id (+ reward-id u1))
    
    ;; Emit reward claim event
    (print { event: "reward-claimed", user: tx-sender, activity-id: activity-id, amount: expected-amount })
    
    (ok expected-amount)
  )
)

;; Batch mint rewards to multiple users (admin only)
(define-public (batch-mint-rewards (recipients (list 50 { recipient: principal, amount: uint })))
  (begin
    ;; Only contract owner can batch mint
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (asserts! (var-get minting-enabled) ERR_MINTING_DISABLED)
    
    ;; Process each recipient
    (ok (map process-mint-reward recipients))
  )
)

;; Helper function for batch minting
(define-private (process-mint-reward (recipient-data { recipient: principal, amount: uint }))
  (let (
    (recipient (get recipient recipient-data))
    (amount (get amount recipient-data))
  )
    ;; Check reward pool balance
    (if (>= (var-get reward-pool-balance) amount)
      (begin
        ;; Update balances
        (var-set reward-pool-balance (- (var-get reward-pool-balance) amount))
        (map-set token-balances recipient (+ (get-balance recipient) amount))
        true
      )
      false
    )
  )
)

;; Staking functions

;; Stake tokens for governance and additional rewards
(define-public (stake-tokens (amount uint) (lock-period uint))
  (let (
    (user-balance (get-balance tx-sender))
    (current-stake (map-get? stakes tx-sender))
  )
    ;; Validate staking parameters
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= user-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (>= lock-period u144) ERR_INVALID_AMOUNT) ;; Minimum 1 day lock
    (asserts! (is-none current-stake) ERR_UNAUTHORIZED) ;; One stake per user for simplicity
    
    ;; Deduct tokens from balance
    (map-set token-balances tx-sender (- user-balance amount))
    
    ;; Create staking position
    (map-set stakes tx-sender {
      amount: amount,
      start-block: stacks-block-height,
      lock-period: lock-period,
      rewards-earned: u0
    })
    
    (ok true)
  )
)

;; Unstake tokens after lock period
(define-public (unstake-tokens)
  (let (
    (stake-data (unwrap! (map-get? stakes tx-sender) ERR_TOKEN_NOT_FOUND))
    (lock-end (+ (get start-block stake-data) (get lock-period stake-data)))
  )
    ;; Check if lock period has ended
    (asserts! (>= stacks-block-height lock-end) ERR_UNAUTHORIZED)
    
    ;; Calculate staking rewards (simplified: 1% per 1000 blocks)
    (let (
      (stake-duration (- stacks-block-height (get start-block stake-data)))
      (stake-rewards (/ (* (get amount stake-data) stake-duration) u100000))
      (total-return (+ (get amount stake-data) stake-rewards))
    )
      ;; Return staked amount plus rewards
      (map-set token-balances tx-sender (+ (get-balance tx-sender) total-return))
      
      ;; Remove stake record
      (map-delete stakes tx-sender)
      
      (ok total-return)
    )
  )
)

;; Governance functions

;; Create governance proposal
(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (voting-period uint))
  (let (
    (proposal-id (var-get next-reward-id))
    (user-balance (get-balance tx-sender))
  )
    ;; Require minimum token balance to create proposal
    (asserts! (>= user-balance u1000000) ERR_UNAUTHORIZED) ;; 1 CCT minimum
    
    ;; Create proposal
    (map-set proposals proposal-id {
      proposer: tx-sender,
      title: title,
      description: description,
      votes-for: u0,
      votes-against: u0,
      voting-ends: (+ stacks-block-height voting-period),
      executed: false
    })
    
    (var-set next-reward-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

;; Vote on proposal
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR_TOKEN_NOT_FOUND))
    (voting-power (get-balance tx-sender))
    (vote-key { proposal-id: proposal-id, voter: tx-sender })
  )
    ;; Validate voting
    (asserts! (> voting-power u0) ERR_INSUFFICIENT_BALANCE)
    (asserts! (< stacks-block-height (get voting-ends proposal)) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? votes vote-key)) ERR_UNAUTHORIZED) ;; One vote per user
    
    ;; Record vote
    (map-set votes vote-key {
      vote: vote-for,
      voting-power: voting-power,
      vote-block: stacks-block-height
    })
    
    ;; Update proposal vote counts
    (map-set proposals proposal-id (merge proposal {
      votes-for: (if vote-for (+ (get votes-for proposal) voting-power) (get votes-for proposal)),
      votes-against: (if vote-for (get votes-against proposal) (+ (get votes-against proposal) voting-power))
    }))
    
    (ok true)
  )
)

;; Read-only functions

;; Get reward claim status
(define-read-only (get-reward-claim (user principal) (activity-id uint))
  (map-get? reward-claims { user: user, activity-id: activity-id })
)

;; Get staking information
(define-read-only (get-stake-info (user principal))
  (map-get? stakes user)
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

;; Get vote information
(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

;; Get pool balances
(define-read-only (get-pool-balances)
  {
    reward-pool: (var-get reward-pool-balance),
    dev-pool: (var-get dev-pool-balance),
    community-pool: (var-get community-pool-balance),
    validator-pool: (var-get validator-pool-balance)
  }
)

;; Check if minting is enabled
(define-read-only (get-minting-status)
  (var-get minting-enabled)
)

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

