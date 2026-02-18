#!/bin/bash
# SSL Configuration Script for Supabase Postgres
# This script enables SSL and generates self-signed certificates if they don't exist

set -e

PGDATA=${PGDATA:-/var/lib/postgresql/data}
CONFIG_FILE=/etc/postgresql/postgresql.conf

# Generate SSL certificates if they don't exist
if [ ! -f "$PGDATA/server.crt" ] || [ ! -f "$PGDATA/server.key" ]; then
    echo "Generating SSL certificates..."
    cd "$PGDATA"
    openssl req -new -x509 -days 365 -nodes -text \
      -out server.crt \
      -keyout server.key \
      -subj "/CN=supabase-db"
    
    chmod 600 server.key
    chown postgres:postgres server.key server.crt
    echo "SSL certificates generated successfully"
else
    echo "SSL certificates already exist, skipping generation"
fi

# Enable SSL in postgresql.conf if not already enabled
if ! grep -q "^ssl = on" "$CONFIG_FILE" 2>/dev/null; then
    echo "Enabling SSL in postgresql.conf..."
    cat >> "$CONFIG_FILE" <<EOF

# SSL Configuration (added by ssl-config.sh)
ssl = on
ssl_cert_file = '$PGDATA/server.crt'
ssl_key_file = '$PGDATA/server.key'
EOF
    echo "SSL enabled in postgresql.conf"
else
    echo "SSL already enabled in postgresql.conf"
fi
