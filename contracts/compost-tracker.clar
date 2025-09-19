;; Compost Tracker Smart Contract
;; Manages user registration, composting activity logging, and verification

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALREADY_REGISTERED (err u101))
(define-constant ERR_USER_NOT_FOUND (err u102))
(define-constant ERR_ACTIVITY_NOT_FOUND (err u103))
(define-constant ERR_INVALID_WEIGHT (err u104))
(define-constant ERR_ALREADY_VERIFIED (err u105))
(define-constant ERR_INVALID_STATUS (err u106))
(define-constant ERR_INSUFFICIENT_BALANCE (err u107))

;; Activity status constants
(define-constant STATUS_PENDING u0)
(define-constant STATUS_VERIFIED u1)
(define-constant STATUS_REJECTED u2)

;; Minimum compost weight (in grams)
(define-constant MIN_COMPOST_WEIGHT u100)

;; Base reward per kg (in tokens)
(define-constant BASE_REWARD_PER_KG u10)

;; Data Variables
(define-data-var next-activity-id uint u1)
(define-data-var next-user-id uint u1)
(define-data-var contract-owner principal tx-sender)
(define-data-var total-compost-weight uint u0)
(define-data-var total-users uint u0)
(define-data-var verification-fee uint u1000000) ;; 1 STX in microSTX

;; Data Maps

;; User profiles
(define-map users principal {
  id: uint,
  username: (string-ascii 50),
  registration-block: uint,
  total-activities: uint,
  total-weight: uint,
  total-rewards: uint,
  verification-level: uint,
  is-active: bool
})

;; User ID to principal mapping
(define-map user-ids uint principal)

;; Composting activities
(define-map compost-activities uint {
  user: principal,
  weight-grams: uint,
  compost-type: (string-ascii 50),
  description: (string-ascii 200),
  creation-block: uint,
  verification-block: uint,
  status: uint,
  verifier: (optional principal),
  photo-hash: (optional (string-ascii 64)),
  reward-claimed: bool
})

;; User activity lists
(define-map user-activities principal (list 100 uint))

;; Monthly statistics
(define-map monthly-stats { year: uint, month: uint } {
  total-weight: uint,
  total-activities: uint,
  unique-users: uint
})

;; Verification requests
(define-map verification-requests uint {
  activity-id: uint,
  requester: principal,
  request-block: uint,
  fee-paid: uint,
  priority: uint
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

;; Update verification fee
(define-public (update-verification-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (var-set verification-fee new-fee)
    (ok true)
  )
)

;; Core user management functions

;; Register a new user
(define-public (register-user (username (string-ascii 50)))
  (let (
    (current-user-id (var-get next-user-id))
  )
    ;; Check if user is already registered
    (asserts! (is-none (map-get? users tx-sender)) ERR_ALREADY_REGISTERED)
    
    ;; Create user profile
    (map-set users tx-sender {
      id: current-user-id,
      username: username,
      registration-block: stacks-block-height,
      total-activities: u0,
      total-weight: u0,
      total-rewards: u0,
      verification-level: u1,
      is-active: true
    })
    
    ;; Set user ID mapping
    (map-set user-ids current-user-id tx-sender)
    
    ;; Initialize empty activity list
    (map-set user-activities tx-sender (list))
    
    ;; Update counters
    (var-set next-user-id (+ current-user-id u1))
    (var-set total-users (+ (var-get total-users) u1))
    
    (ok current-user-id)
  )
)

;; Update user profile
(define-public (update-profile (new-username (string-ascii 50)))
  (let (
    (user-data (unwrap! (map-get? users tx-sender) ERR_USER_NOT_FOUND))
  )
    (map-set users tx-sender (merge user-data { username: new-username }))
    (ok true)
  )
)

;; Core composting activity functions

;; Log a composting activity
(define-public (log-compost-activity 
  (weight-grams uint)
  (compost-type (string-ascii 50))
  (description (string-ascii 200))
  (photo-hash (optional (string-ascii 64)))
)
  (let (
    (activity-id (var-get next-activity-id))
    (user-data (unwrap! (map-get? users tx-sender) ERR_USER_NOT_FOUND))
    (current-activities (default-to (list) (map-get? user-activities tx-sender)))
    (current-month (/ stacks-block-height u144)) ;; Approximate blocks per month
    (current-year (/ current-month u12))
  )
    ;; Validate weight
    (asserts! (>= weight-grams MIN_COMPOST_WEIGHT) ERR_INVALID_WEIGHT)
    
    ;; Create activity record
    (map-set compost-activities activity-id {
      user: tx-sender,
      weight-grams: weight-grams,
      compost-type: compost-type,
      description: description,
      creation-block: stacks-block-height,
      verification-block: u0,
      status: STATUS_PENDING,
      verifier: none,
      photo-hash: photo-hash,
      reward-claimed: false
    })
    
    ;; Update user activities list
    (map-set user-activities tx-sender (unwrap! (as-max-len? (append current-activities activity-id) u100) (err u999)))
    
    ;; Update user statistics
    (map-set users tx-sender (merge user-data {
      total-activities: (+ (get total-activities user-data) u1),
      total-weight: (+ (get total-weight user-data) weight-grams)
    }))
    
    ;; Update global statistics
    (var-set next-activity-id (+ activity-id u1))
    (var-set total-compost-weight (+ (var-get total-compost-weight) weight-grams))
    
    ;; Update monthly statistics
    (let (
      (month-stats (default-to {
        total-weight: u0,
        total-activities: u0,
        unique-users: u0
      } (map-get? monthly-stats { year: current-year, month: (mod current-month u12) })))
    )
      (map-set monthly-stats { year: current-year, month: (mod current-month u12) } {
        total-weight: (+ (get total-weight month-stats) weight-grams),
        total-activities: (+ (get total-activities month-stats) u1),
        unique-users: (get unique-users month-stats) ;; Simplified for this implementation
      })
    )
    
    (ok activity-id)
  )
)

;; Verify a composting activity (by contract owner or designated verifier)
(define-public (verify-activity (activity-id uint) (approved bool))
  (let (
    (activity (unwrap! (map-get? compost-activities activity-id) ERR_ACTIVITY_NOT_FOUND))
    (user-data (unwrap! (map-get? users (get user activity)) ERR_USER_NOT_FOUND))
  )
    ;; Only contract owner can verify for now
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status activity) STATUS_PENDING) ERR_ALREADY_VERIFIED)
    
    ;; Update activity status
    (map-set compost-activities activity-id (merge activity {
      status: (if approved STATUS_VERIFIED STATUS_REJECTED),
      verification-block: stacks-block-height,
      verifier: (some tx-sender)
    }))
    
    ;; If approved, calculate and store potential reward
    (if approved
      (let (
        (weight-kg (/ (get weight-grams activity) u1000))
        (base-reward (* weight-kg BASE_REWARD_PER_KG))
        (bonus-multiplier (if (>= (get total-activities user-data) u10) u15 u10)) ;; 50% bonus for active users
        (final-reward (/ (* base-reward bonus-multiplier) u10))
      )
        ;; Update user rewards (to be claimed later)
        (map-set users (get user activity) (merge user-data {
          total-rewards: (+ (get total-rewards user-data) final-reward)
        }))
        (ok final-reward)
      )
      (ok u0)
    )
  )
)

;; Request priority verification (with fee)
(define-public (request-verification (activity-id uint))
  (let (
    (activity (unwrap! (map-get? compost-activities activity-id) ERR_ACTIVITY_NOT_FOUND))
    (fee (var-get verification-fee))
  )
    ;; Verify ownership of activity
    (asserts! (is-eq tx-sender (get user activity)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status activity) STATUS_PENDING) ERR_INVALID_STATUS)
    
    ;; Transfer verification fee to contract
    (try! (stx-transfer? fee tx-sender (var-get contract-owner)))
    
    ;; Create verification request
    (map-set verification-requests activity-id {
      activity-id: activity-id,
      requester: tx-sender,
      request-block: stacks-block-height,
      fee-paid: fee,
      priority: u1
    })
    
    (ok true)
  )
)

;; Update activity with additional proof
(define-public (update-activity-proof (activity-id uint) (photo-hash (string-ascii 64)))
  (let (
    (activity (unwrap! (map-get? compost-activities activity-id) ERR_ACTIVITY_NOT_FOUND))
  )
    ;; Verify ownership
    (asserts! (is-eq tx-sender (get user activity)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status activity) STATUS_PENDING) ERR_INVALID_STATUS)
    
    ;; Update activity with photo proof
    (map-set compost-activities activity-id (merge activity {
      photo-hash: (some photo-hash)
    }))
    
    (ok true)
  )
)

;; Read-only functions

;; Get user profile
(define-read-only (get-user (user principal))
  (map-get? users user)
)

;; Get user by ID
(define-read-only (get-user-by-id (id uint))
  (match (map-get? user-ids id)
    user-principal (map-get? users user-principal)
    none
  )
)

;; Get activity details
(define-read-only (get-activity (activity-id uint))
  (map-get? compost-activities activity-id)
)

;; Get user activities
(define-read-only (get-user-activities (user principal))
  (map-get? user-activities user)
)

;; Get user activity count
(define-read-only (get-user-activity-count (user principal))
  (match (map-get? users user)
    user-data (some (get total-activities user-data))
    none
  )
)

;; Get total statistics
(define-read-only (get-total-stats)
  {
    total-users: (var-get total-users),
    total-compost-weight: (var-get total-compost-weight),
    next-activity-id: (var-get next-activity-id),
    verification-fee: (var-get verification-fee)
  }
)

;; Get monthly statistics
(define-read-only (get-monthly-stats (year uint) (month uint))
  (map-get? monthly-stats { year: year, month: month })
)

;; Check if user is registered
(define-read-only (is-user-registered (user principal))
  (is-some (map-get? users user))
)

;; Get verification request
(define-read-only (get-verification-request (activity-id uint))
  (map-get? verification-requests activity-id)
)

;; Calculate potential reward for activity
(define-read-only (calculate-reward (weight-grams uint) (user principal))
  (let (
    (user-data (default-to {
      id: u0,
      username: "",
      registration-block: u0,
      total-activities: u0,
      total-weight: u0,
      total-rewards: u0,
      verification-level: u1,
      is-active: true
    } (map-get? users user)))
    (weight-kg (/ weight-grams u1000))
    (base-reward (* weight-kg BASE_REWARD_PER_KG))
    (bonus-multiplier (if (>= (get total-activities user-data) u10) u15 u10))
  )
    (/ (* base-reward bonus-multiplier) u10)
  )
)

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

