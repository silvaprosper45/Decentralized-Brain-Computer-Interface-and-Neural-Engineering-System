;; Memory Enhancement Protocol Contract
;; Augments human memory capacity through neural interfaces

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-INPUT (err u301))
(define-constant ERR-USER-NOT-FOUND (err u302))
(define-constant ERR-MEMORY-NOT-FOUND (err u303))
(define-constant ERR-QUOTA-EXCEEDED (err u304))
(define-constant ERR-BACKUP-FAILED (err u305))
(define-constant ERR-ENCRYPTION-FAILED (err u306))

;; Data Variables
(define-data-var total-memory-users uint u0)
(define-data-var total-memory-blocks uint u0)
(define-data-var total-storage-used uint u0)

;; Data Maps
(define-map memory-users
  {user-id: (string-ascii 50)}
  {
    storage-quota: uint,
    storage-used: uint,
    backup-frequency: uint,
    encryption-level: uint,
    last-backup: uint,
    memory-blocks-count: uint,
    enhancement-level: uint,
    access-permissions: (list 5 principal)
  })

(define-map memory-blocks
  {user-id: (string-ascii 50), block-id: uint}
  {
    memory-type: (string-ascii 50),
    content-hash: (buff 32),
    encrypted-content: (buff 1024),
    creation-time: uint,
    last-accessed: uint,
    access-count: uint,
    importance-level: uint,
    tags: (list 10 (string-ascii 30)),
    backup-status: bool
  })

(define-map memory-categories
  {user-id: (string-ascii 50), category: (string-ascii 50)}
  {
    block-count: uint,
    total-size: uint,
    retention-period: uint,
    auto-backup: bool,
    compression-level: uint
  })

(define-map backup-records
  {user-id: (string-ascii 50), backup-id: uint}
  {
    backup-time: uint,
    blocks-backed-up: uint,
    backup-size: uint,
    backup-hash: (buff 32),
    verification-status: bool,
    restoration-count: uint
  })

;; Private Functions
(define-private (is-authorized-user (user-id (string-ascii 50)))
  (or
    (is-eq tx-sender CONTRACT-OWNER)
    (is-some (map-get? memory-users {user-id: user-id}))))

(define-private (has-storage-quota (user-id (string-ascii 50)) (additional-size uint))
  (match (map-get? memory-users {user-id: user-id})
    user-data (>= (get storage-quota user-data) (+ (get storage-used user-data) additional-size))
    false))

(define-private (calculate-storage-size (content (buff 1024)))
  (len content))

(define-private (is-authorized-accessor (user-id (string-ascii 50)) (accessor principal))
  (match (map-get? memory-users {user-id: user-id})
    user-data (or
      (is-eq accessor tx-sender)
      (is-some (index-of (get access-permissions user-data) accessor)))
    false))

;; Public Functions
(define-public (setup-memory-enhancement
  (user-id (string-ascii 50))
  (storage-quota uint)
  (backup-frequency uint)
  (encryption-level uint)
  (enhancement-level uint))
  (begin
    (asserts! (> (len user-id) u0) ERR-INVALID-INPUT)
    (asserts! (> storage-quota u0) ERR-INVALID-INPUT)
    (asserts! (and (>= encryption-level u1) (<= encryption-level u5)) ERR-INVALID-INPUT)
    (asserts! (and (>= enhancement-level u1) (<= enhancement-level u10)) ERR-INVALID-INPUT)
    (asserts! (and (>= backup-frequency u1) (<= backup-frequency u168)) ERR-INVALID-INPUT) ;; Max 1 week

    (map-set memory-users
      {user-id: user-id}
      {
        storage-quota: storage-quota,
        storage-used: u0,
        backup-frequency: backup-frequency,
        encryption-level: encryption-level,
        last-backup: u0,
        memory-blocks-count: u0,
        enhancement-level: enhancement-level,
        access-permissions: (list)
      })

    (var-set total-memory-users (+ (var-get total-memory-users) u1))
    (ok true)))

(define-public (store-memory-block
  (user-id (string-ascii 50))
  (block-id uint)
  (memory-type (string-ascii 50))
  (encrypted-content (buff 1024))
  (importance-level uint)
  (tags (list 10 (string-ascii 30))))
  (let (
    (user-data (unwrap! (map-get? memory-users {user-id: user-id}) ERR-USER-NOT-FOUND))
    (content-size (calculate-storage-size encrypted-content))
  )
    (asserts! (is-authorized-user user-id) ERR-NOT-AUTHORIZED)
    (asserts! (> (len encrypted-content) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= importance-level u1) (<= importance-level u10)) ERR-INVALID-INPUT)
    (asserts! (has-storage-quota user-id content-size) ERR-QUOTA-EXCEEDED)

    ;; Create content hash for integrity verification
    (let ((content-hash (keccak256 encrypted-content)))
      (map-set memory-blocks
        {user-id: user-id, block-id: block-id}
        {
          memory-type: memory-type,
          content-hash: content-hash,
          encrypted-content: encrypted-content,
          creation-time: block-height,
          last-accessed: block-height,
          access-count: u1,
          importance-level: importance-level,
          tags: tags,
          backup-status: false
        }))

    ;; Update user storage statistics
    (map-set memory-users
      {user-id: user-id}
      (merge user-data {
        storage-used: (+ (get storage-used user-data) content-size),
        memory-blocks-count: (+ (get memory-blocks-count user-data) u1)
      }))

    (var-set total-memory-blocks (+ (var-get total-memory-blocks) u1))
    (var-set total-storage-used (+ (var-get total-storage-used) content-size))
    (ok true)))

(define-public (retrieve-memory-block
  (user-id (string-ascii 50))
  (block-id uint))
  (let (
    (block-data (unwrap! (map-get? memory-blocks {user-id: user-id, block-id: block-id}) ERR-MEMORY-NOT-FOUND))
  )
    (asserts! (is-authorized-accessor user-id tx-sender) ERR-NOT-AUTHORIZED)

    ;; Update access statistics
    (map-set memory-blocks
      {user-id: user-id, block-id: block-id}
      (merge block-data {
        last-accessed: block-height,
        access-count: (+ (get access-count block-data) u1)
      }))

    (ok {
      memory-type: (get memory-type block-data),
      encrypted-content: (get encrypted-content block-data),
      importance-level: (get importance-level block-data),
      tags: (get tags block-data),
      creation-time: (get creation-time block-data)
    })))

(define-public (update-memory-block
  (user-id (string-ascii 50))
  (block-id uint)
  (new-encrypted-content (buff 1024))
  (new-importance-level uint))
  (let (
    (user-data (unwrap! (map-get? memory-users {user-id: user-id}) ERR-USER-NOT-FOUND))
    (block-data (unwrap! (map-get? memory-blocks {user-id: user-id, block-id: block-id}) ERR-MEMORY-NOT-FOUND))
    (old-size (calculate-storage-size (get encrypted-content block-data)))
    (new-size (calculate-storage-size new-encrypted-content))
    (size-diff (if (> new-size old-size) (- new-size old-size) u0))
  )
    (asserts! (is-authorized-user user-id) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= new-importance-level u1) (<= new-importance-level u10)) ERR-INVALID-INPUT)
    (asserts! (has-storage-quota user-id size-diff) ERR-QUOTA-EXCEEDED)

    ;; Update memory block
    (let ((new-content-hash (keccak256 new-encrypted-content)))
      (map-set memory-blocks
        {user-id: user-id, block-id: block-id}
        (merge block-data {
          content-hash: new-content-hash,
          encrypted-content: new-encrypted-content,
          importance-level: new-importance-level,
          last-accessed: block-height,
          backup-status: false
        })))

    ;; Update storage usage
    (map-set memory-users
      {user-id: user-id}
      (merge user-data {
        storage-used: (+ (- (get storage-used user-data) old-size) new-size)
      }))

    (ok true)))

(define-public (create-memory-backup
  (user-id (string-ascii 50))
  (backup-id uint)
  (backup-hash (buff 32)))
  (let (
    (user-data (unwrap! (map-get? memory-users {user-id: user-id}) ERR-USER-NOT-FOUND))
  )
    (asserts! (is-authorized-user user-id) ERR-NOT-AUTHORIZED)
    (asserts! (> (len backup-hash) u0) ERR-INVALID-INPUT)

    (map-set backup-records
      {user-id: user-id, backup-id: backup-id}
      {
        backup-time: block-height,
        blocks-backed-up: (get memory-blocks-count user-data),
        backup-size: (get storage-used user-data),
        backup-hash: backup-hash,
        verification-status: true,
        restoration-count: u0
      })

    ;; Update user's last backup time
    (map-set memory-users
      {user-id: user-id}
      (merge user-data {
        last-backup: block-height
      }))

    (ok true)))

(define-public (set-memory-category
  (user-id (string-ascii 50))
  (category (string-ascii 50))
  (retention-period uint)
  (auto-backup bool)
  (compression-level uint))
  (begin
    (asserts! (is-authorized-user user-id) ERR-NOT-AUTHORIZED)
    (asserts! (> (len category) u0) ERR-INVALID-INPUT)
    (asserts! (> retention-period u0) ERR-INVALID-INPUT)
    (asserts! (and (>= compression-level u1) (<= compression-level u9)) ERR-INVALID-INPUT)

    (map-set memory-categories
      {user-id: user-id, category: category}
      {
        block-count: u0,
        total-size: u0,
        retention-period: retention-period,
        auto-backup: auto-backup,
        compression-level: compression-level
      })

    (ok true)))

(define-public (grant-memory-access
  (user-id (string-ascii 50))
  (accessor principal))
  (let (
    (user-data (unwrap! (map-get? memory-users {user-id: user-id}) ERR-USER-NOT-FOUND))
  )
    (asserts! (is-authorized-user user-id) ERR-NOT-AUTHORIZED)
    (asserts! (< (len (get access-permissions user-data)) u5) ERR-INVALID-INPUT)

    (map-set memory-users
      {user-id: user-id}
      (merge user-data {
        access-permissions: (unwrap-panic (as-max-len? (append (get access-permissions user-data) accessor) u5))
      }))

    (ok true)))

;; Read-only Functions
(define-read-only (get-memory-user (user-id (string-ascii 50)))
  (map-get? memory-users {user-id: user-id}))

(define-read-only (get-memory-block-info (user-id (string-ascii 50)) (block-id uint))
  (match (map-get? memory-blocks {user-id: user-id, block-id: block-id})
    block-data (some {
      memory-type: (get memory-type block-data),
      creation-time: (get creation-time block-data),
      last-accessed: (get last-accessed block-data),
      access-count: (get access-count block-data),
      importance-level: (get importance-level block-data),
      tags: (get tags block-data),
      backup-status: (get backup-status block-data)
    })
    none))

(define-read-only (get-memory-category (user-id (string-ascii 50)) (category (string-ascii 50)))
  (map-get? memory-categories {user-id: user-id, category: category}))

(define-read-only (get-backup-record (user-id (string-ascii 50)) (backup-id uint))
  (map-get? backup-records {user-id: user-id, backup-id: backup-id}))

(define-read-only (get-system-stats)
  {
    total-memory-users: (var-get total-memory-users),
    total-memory-blocks: (var-get total-memory-blocks),
    total-storage-used: (var-get total-storage-used)
  })

(define-read-only (get-storage-usage (user-id (string-ascii 50)))
  (match (map-get? memory-users {user-id: user-id})
    user-data (some {
      quota: (get storage-quota user-data),
      used: (get storage-used user-data),
      available: (- (get storage-quota user-data) (get storage-used user-data)),
      utilization-percent: (/ (* (get storage-used user-data) u100) (get storage-quota user-data))
    })
    none))

;; Admin Functions
(define-public (increase-user-quota
  (user-id (string-ascii 50))
  (additional-quota uint))
  (let (
    (user-data (unwrap! (map-get? memory-users {user-id: user-id}) ERR-USER-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> additional-quota u0) ERR-INVALID-INPUT)

    (map-set memory-users
      {user-id: user-id}
      (merge user-data {
        storage-quota: (+ (get storage-quota user-data) additional-quota)
      }))

    (ok true)))
