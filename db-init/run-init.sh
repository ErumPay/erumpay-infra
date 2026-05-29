#!/bin/sh
set -e

echo "Waiting for MySQL..."
until mysqladmin ping -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" --silent; do
  sleep 3
done

echo "Running SQL files..."
for file in /db-init/sql/*.sql; do
  echo "Running $file"
  mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" < "$file"
done

echo "DB init completed"