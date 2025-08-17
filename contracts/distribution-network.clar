;; Green Hydrogen Distribution Network Contract
;; Manages pricing, inventory, and distribution logistics

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u300))
(define-constant ERR-INVALID-INPUT (err u301))
(define-constant ERR-NOT-FOUND (err u302))
(define-constant ERR-INSUFFICIENT-INVENTORY (err u303))
(define-constant ERR-INVALID-PRICE (err u304))
(define-constant ERR-DELIVERY-FAILED (err u305))

;; Price precision (multiply by 1000 for 3 decimal places)
(define-constant PRICE-PRECISION u1000)
(define-constant MAX-PRICE u1000000) ;; Maximum price per kg in micro-units

;; Data Variables
(define-data-var next-distribution-point-id uint u1)
(define-data-var next-order-id uint u1)
(define-data-var total-distribution-points uint u0)
(define-data-var global-base-price uint u50000) ;; Base price per kg in micro-units

;; Distribution Point Data Structure
(define-map distribution-points
  { point-id: uint }
  {
    operator: principal,
    location-name: (string-ascii 50),
    location-lat: int,
    location-lon: int,
    storage-capacity-kg: uint,
    current-inventory-kg: uint,
    price-per-kg: uint,
    transportation-methods: (list 5 (string-ascii 20)),
    operational-status: (string-ascii 20),
    last-updated: uint,
    quality-requirements: (string-ascii 30)
  }
)

;; Inventory Tracking
(define-map inventory-batches
  { point-id: uint, batch-id: uint }
  {
    quantity-kg: uint,
    quality-certificate-id: uint,
    arrival-date: uint,
    expiry-date: uint,
    source-producer: principal,
    storage-conditions: (string-ascii 30)
  }
)

;; Order Management
(define-map hydrogen-orders
  { order-id: uint }
  {
    buyer: principal,
    distribution-point: uint,
    quantity-kg: uint,
    price-per-kg: uint,
    total-amount: uint,
    order-date: uint,
    delivery-date: uint,
    delivery-address: (string-ascii 100),
    order-status: (string-ascii 20),
    quality-requirements: (string-ascii 30)
  }
)

;; Price History Tracking
(define-map price-history
  { point-id: uint, timestamp: uint }
  {
    price-per-kg: uint,
    supply-level: uint,
    demand-indicator: uint,
    market-conditions: (string-ascii 50)
  }
)

;; Regional Market Data
(define-map regional-markets
  { region: (string-ascii 30) }
  {
    average-price: uint,
    total-supply: uint,
    total-demand: uint,
    active-points: uint,
    last-updated: uint
  }
)

;; Distribution Point Performance
(define-map point-performance
  { point-id: uint }
  {
    total-orders-fulfilled: uint,
    total-volume-sold: uint,
    average-delivery-time: uint,
    customer-rating: uint,
    last-activity: uint
  }
)

;; Public Functions

;; Register a new distribution point
(define-public (register-distribution-point
  (location-name (string-ascii 50))
  (location-lat int)
  (location-lon int)
  (storage-capacity-kg uint)
  (price-per-kg uint)
  (transportation-methods (list 5 (string-ascii 20)))
  (quality-requirements (string-ascii 30)))
  (let
    (
      (point-id (var-get next-distribution-point-id))
      (current-timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    ;; Input validation
    (asserts! (> (len location-name) u0) ERR-INVALID-INPUT)
    (asserts! (> storage-capacity-kg u0) ERR-INVALID-INPUT)
    (asserts! (and (> price-per-kg u0) (< price-per-kg MAX-PRICE)) ERR-INVALID-PRICE)
    (asserts! (> (len quality-requirements) u0) ERR-INVALID-INPUT)

    ;; Register distribution point
    (map-set distribution-points
      { point-id: point-id }
      {
        operator: tx-sender,
        location-name: location-name,
        location-lat: location-lat,
        location-lon: location-lon,
        storage-capacity-kg: storage-capacity-kg,
        current-inventory-kg: u0,
        price-per-kg: price-per-kg,
        transportation-methods: transportation-methods,
        operational-status: "active",
        last-updated: current-timestamp,
        quality-requirements: quality-requirements
      }
    )

    ;; Initialize performance tracking
    (map-set point-performance
      { point-id: point-id }
      {
        total-orders-fulfilled: u0,
        total-volume-sold: u0,
        average-delivery-time: u0,
        customer-rating: u100,
        last-activity: current-timestamp
      }
    )

    ;; Update counters
    (var-set next-distribution-point-id (+ point-id u1))
    (var-set total-distribution-points (+ (var-get total-distribution-points) u1))

    (ok point-id)
  )
)

;; Add inventory to distribution point
(define-public (add-inventory
  (point-id uint)
  (batch-id uint)
  (quantity-kg uint)
  (quality-certificate-id uint)
  (expiry-date uint)
  (source-producer principal)
  (storage-conditions (string-ascii 30)))
  (let
    (
      (point-data (unwrap! (map-get? distribution-points { point-id: point-id }) ERR-NOT-FOUND))
      (current-timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
      (new-inventory (+ (get current-inventory-kg point-data) quantity-kg))
    )
    ;; Authorization check
    (asserts! (is-eq tx-sender (get operator point-data)) ERR-UNAUTHORIZED)

    ;; Input validation
    (asserts! (> quantity-kg u0) ERR-INVALID-INPUT)
    (asserts! (> quality-certificate-id u0) ERR-INVALID-INPUT)
    (asserts! (> expiry-date current-timestamp) ERR-INVALID-INPUT)
    (asserts! (<= new-inventory (get storage-capacity-kg point-data)) ERR-INSUFFICIENT-INVENTORY)

    ;; Add inventory batch
    (map-set inventory-batches
      { point-id: point-id, batch-id: batch-id }
      {
        quantity-kg: quantity-kg,
        quality-certificate-id: quality-certificate-id,
        arrival-date: current-timestamp,
        expiry-date: expiry-date,
        source-producer: source-producer,
        storage-conditions: storage-conditions
      }
    )

    ;; Update distribution point inventory
    (map-set distribution-points
      { point-id: point-id }
      (merge point-data {
        current-inventory-kg: new-inventory,
        last-updated: current-timestamp
      })
    )

    (ok true)
  )
)

;; Update pricing for distribution point
(define-public (update-pricing
  (point-id uint)
  (new-price-per-kg uint)
  (market-conditions (string-ascii 50)))
  (let
    (
      (point-data (unwrap! (map-get? distribution-points { point-id: point-id }) ERR-NOT-FOUND))
      (current-timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    ;; Authorization check
    (asserts! (is-eq tx-sender (get operator point-data)) ERR-UNAUTHORIZED)

    ;; Input validation
    (asserts! (and (> new-price-per-kg u0) (< new-price-per-kg MAX-PRICE)) ERR-INVALID-PRICE)

    ;; Record price history
    (map-set price-history
      { point-id: point-id, timestamp: current-timestamp }
      {
        price-per-kg: new-price-per-kg,
        supply-level: (get current-inventory-kg point-data),
        demand-indicator: u50, ;; Simplified demand indicator
        market-conditions: market-conditions
      }
    )

    ;; Update distribution point pricing
    (map-set distribution-points
      { point-id: point-id }
      (merge point-data {
        price-per-kg: new-price-per-kg,
        last-updated: current-timestamp
      })
    )

    (ok true)
  )
)

;; Place hydrogen order
(define-public (place-order
  (distribution-point uint)
  (quantity-kg uint)
  (delivery-address (string-ascii 100))
  (quality-requirements (string-ascii 30)))
  (let
    (
      (order-id (var-get next-order-id))
      (point-data (unwrap! (map-get? distribution-points { point-id: distribution-point }) ERR-NOT-FOUND))
      (current-timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
      (delivery-timestamp (+ current-timestamp u604800)) ;; 1 week delivery
      (price-per-kg (get price-per-kg point-data))
      (total-amount (* quantity-kg price-per-kg))
    )
    ;; Input validation
    (asserts! (> quantity-kg u0) ERR-INVALID-INPUT)
    (asserts! (> (len delivery-address) u0) ERR-INVALID-INPUT)
    (asserts! (> (len quality-requirements) u0) ERR-INVALID-INPUT)

    ;; Check inventory availability
    (asserts! (>= (get current-inventory-kg point-data) quantity-kg) ERR-INSUFFICIENT-INVENTORY)

    ;; Check operational status
    (asserts! (is-eq (get operational-status point-data) "active") ERR-INVALID-INPUT)

    ;; Create order
    (map-set hydrogen-orders
      { order-id: order-id }
      {
        buyer: tx-sender,
        distribution-point: distribution-point,
        quantity-kg: quantity-kg,
        price-per-kg: price-per-kg,
        total-amount: total-amount,
        order-date: current-timestamp,
        delivery-date: delivery-timestamp,
        delivery-address: delivery-address,
        order-status: "pending",
        quality-requirements: quality-requirements
      }
    )

    ;; Reserve inventory
    (map-set distribution-points
      { point-id: distribution-point }
      (merge point-data {
        current-inventory-kg: (- (get current-inventory-kg point-data) quantity-kg),
        last-updated: current-timestamp
      })
    )

    ;; Update counter
    (var-set next-order-id (+ order-id u1))

    (ok order-id)
  )
)

;; Fulfill order (mark as delivered)
(define-public (fulfill-order (order-id uint))
  (let
    (
      (order-data (unwrap! (map-get? hydrogen-orders { order-id: order-id }) ERR-NOT-FOUND))
      (point-data (unwrap! (map-get? distribution-points { point-id: (get distribution-point order-data) }) ERR-NOT-FOUND))
      (current-timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
      (perf-data (default-to
        { total-orders-fulfilled: u0, total-volume-sold: u0, average-delivery-time: u0, customer-rating: u100, last-activity: u0 }
        (map-get? point-performance { point-id: (get distribution-point order-data) })
      ))
    )
    ;; Authorization check - only distribution point operator
    (asserts! (is-eq tx-sender (get operator point-data)) ERR-UNAUTHORIZED)

    ;; Validate order status
    (asserts! (is-eq (get order-status order-data) "pending") ERR-INVALID-INPUT)

    ;; Update order status
    (map-set hydrogen-orders
      { order-id: order-id }
      (merge order-data { order-status: "delivered" })
    )

    ;; Update performance metrics
    (map-set point-performance
      { point-id: (get distribution-point order-data) }
      (merge perf-data {
        total-orders-fulfilled: (+ (get total-orders-fulfilled perf-data) u1),
        total-volume-sold: (+ (get total-volume-sold perf-data) (get quantity-kg order-data)),
        last-activity: current-timestamp
      })
    )

    (ok true)
  )
)

;; Set global base price (contract owner only)
(define-public (set-global-base-price (new-base-price uint))
  (begin
    ;; Only contract owner can set global base price
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)

    ;; Input validation
    (asserts! (and (> new-base-price u0) (< new-base-price MAX-PRICE)) ERR-INVALID-PRICE)

    ;; Update global base price
    (var-set global-base-price new-base-price)

    (ok true)
  )
)

;; Read-only Functions

;; Get distribution point details
(define-read-only (get-distribution-point (point-id uint))
  (map-get? distribution-points { point-id: point-id })
)

;; Get inventory batch details
(define-read-only (get-inventory-batch (point-id uint) (batch-id uint))
  (map-get? inventory-batches { point-id: point-id, batch-id: batch-id })
)

;; Get order details
(define-read-only (get-order (order-id uint))
  (map-get? hydrogen-orders { order-id: order-id })
)

;; Get price history
(define-read-only (get-price-history (point-id uint) (timestamp uint))
  (map-get? price-history { point-id: point-id, timestamp: timestamp })
)

;; Get point performance metrics
(define-read-only (get-point-performance (point-id uint))
  (map-get? point-performance { point-id: point-id })
)

;; Calculate total inventory across all points
(define-read-only (get-total-network-inventory)
  ;; Simplified calculation - would need iteration in practice
  u0
)

;; Get global base price
(define-read-only (get-global-base-price)
  (var-get global-base-price)
)

;; Get total distribution points
(define-read-only (get-total-distribution-points)
  (var-get total-distribution-points)
)

;; Check if distribution point is operational
(define-read-only (is-point-operational (point-id uint))
  (match (map-get? distribution-points { point-id: point-id })
    point-data (is-eq (get operational-status point-data) "active")
    false
  )
)

;; Calculate delivery estimate
(define-read-only (estimate-delivery-time (point-id uint) (quantity-kg uint))
  (let
    (
      (current-timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (match (map-get? distribution-points { point-id: point-id })
      point-data (if (>= (get current-inventory-kg point-data) quantity-kg)
        (+ current-timestamp u604800) ;; 1 week if in stock
        (+ current-timestamp u1209600) ;; 2 weeks if needs restocking
      )
      u0
    )
  )
)

;; Get next available order ID
(define-read-only (get-next-order-id)
  (var-get next-order-id)
)
