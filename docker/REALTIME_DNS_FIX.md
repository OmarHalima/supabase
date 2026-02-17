# Realtime Service DNS Resolution Issue

## Problem
The `realtime-dev.supabase-realtime` service is failing to connect to the database with error:
```
tcp connect (db:5432): connection refused - :econnrefused
```

## Root Cause
The realtime container resolves `db` to IPv6 `::1` (localhost) instead of the actual container IP address `172.19.0.4`. This is a Docker DNS resolution issue where some containers resolve service names to IPv6 localhost instead of the container IP.

## Verification
```bash
# Check DNS resolution in realtime container
docker exec realtime-dev.supabase-realtime getent hosts db
# Output: ::1             db.localhost  (WRONG - should be container IP)

# Compare with working container
docker exec supabase-auth getent hosts db  
# Output: 172.19.0.4        db  db  (CORRECT)
```

## Solution Options

### Option 1: Use Container IP Directly (Temporary Fix)
If you need an immediate fix, you can set `DB_HOST` to the container IP:

1. Get the database container IP:
   ```bash
   docker inspect supabase-db --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
   ```

2. In EasyPanel, set the environment variable:
   ```
   POSTGRES_HOST=<container-ip>
   ```
   Note: This IP may change when containers restart, so this is not a permanent solution.

### Option 2: Use Container Name Instead
Try using `supabase-db` instead of `db`:

In EasyPanel, set:
```
POSTGRES_HOST=supabase-db
```

### Option 3: Network Configuration Fix
The docker-compose.yml has been updated to:
1. Disable IPv6 on the network (`enable_ipv6: false`)
2. Add network aliases to the db service

However, since EasyPanel manages the deployment, you may need to:
1. Redeploy the application in EasyPanel to pick up the network changes
2. Or manually fix DNS resolution in the realtime container

### Option 4: Manual DNS Fix (Temporary)
As a temporary workaround, you can add a hosts entry:

```bash
# Get database container IP
DB_IP=$(docker inspect supabase-db --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

# Add to realtime container (will be lost on restart)
docker exec realtime-dev.supabase-realtime sh -c "echo '$DB_IP db' >> /etc/hosts"

# Restart realtime service
docker restart realtime-dev.supabase-realtime
```

## Recommended Action
1. **Check EasyPanel logs** for the exact error message
2. **Verify environment variables** are set correctly in EasyPanel
3. **Try Option 2 first** (use `supabase-db` as hostname)
4. If that doesn't work, **redeploy the application** in EasyPanel to pick up network configuration changes

## Network Configuration Changes Made
The docker-compose.yml has been updated with:
- Network IPv6 disabled
- Network aliases for db service
- Increased start_period for realtime healthcheck

These changes should help, but may require a full redeploy in EasyPanel to take effect.
