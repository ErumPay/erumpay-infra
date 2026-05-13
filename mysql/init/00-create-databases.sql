CREATE DATABASE IF NOT EXISTS auth_db
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS card_db
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS payment_db
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS recommend_db
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS notification_db
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS pg_auth_db
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS pg_billing_db
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS pg_payment_db
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS merchant_db
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS card_simulator_db
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'erumpay'@'%' IDENTIFIED BY 'erumpay1234';

GRANT ALL PRIVILEGES ON auth_db.* TO 'erumpay'@'%';
GRANT ALL PRIVILEGES ON card_db.* TO 'erumpay'@'%';
GRANT ALL PRIVILEGES ON payment_db.* TO 'erumpay'@'%';
GRANT ALL PRIVILEGES ON recommend_db.* TO 'erumpay'@'%';
GRANT ALL PRIVILEGES ON notification_db.* TO 'erumpay'@'%';
GRANT ALL PRIVILEGES ON pg_auth_db.* TO 'erumpay'@'%';
GRANT ALL PRIVILEGES ON pg_billing_db.* TO 'erumpay'@'%';
GRANT ALL PRIVILEGES ON pg_payment_db.* TO 'erumpay'@'%';
GRANT ALL PRIVILEGES ON merchant_db.* TO 'erumpay'@'%';
GRANT ALL PRIVILEGES ON card_simulator_db.* TO 'erumpay'@'%';

FLUSH PRIVILEGES;