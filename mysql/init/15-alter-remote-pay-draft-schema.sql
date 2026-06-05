USE payment_db;

ALTER TABLE payment_remote_requests
  MODIFY COLUMN target_user_id BIGINT NULL COMMENT 'auth_users logical reference. null while target is not selected';

ALTER TABLE payment_remote_requests
  ADD COLUMN source_payment_id BIGINT NULL COMMENT 'original QR/merchant payment_orders.payment_id' AFTER target_user_id;

ALTER TABLE payment_remote_requests
  MODIFY COLUMN status ENUM(
    'DRAFT',
    'PENDING',
    'COMPLETED',
    'REJECTED_BY_PAYER',
    'CANCELLED_BY_REQUESTER',
    'EXPIRED'
  ) NOT NULL DEFAULT 'PENDING';

ALTER TABLE payment_remote_requests
  ADD KEY idx_payment_remote_requests_source_payment (source_payment_id);

ALTER TABLE payment_remote_requests
  ADD CONSTRAINT fk_payment_remote_requests_source_payment
    FOREIGN KEY (source_payment_id) REFERENCES payment_orders(payment_id);
