# EasyPanel Deployment Notes for Supabase

## Changes Made for EasyPanel Compatibility

### 1. Port Conflict Resolution
The `supavisor` service exposes PostgreSQL port `${POSTGRES_PORT}` (default: 5432). If EasyPanel reports port conflicts:
- Ensure no other service is using port 5432
- Consider changing `POSTGRES_PORT` in your `.env` file to a different port (e.g., 5433)
- Or comment out the port mapping line in `supavisor` service if you don't need direct PostgreSQL access

### 2. Docker Socket Access
The `vector` service mounts the Docker socket to collect container logs. If EasyPanel doesn't allow this:
- Comment out the Docker socket volume mount line in the `vector` service
- Note: This will disable Docker log collection, but Supabase will still function

### 3. Security Options
The `vector` service uses `security_opt: - "label=disable"`. If EasyPanel reports security policy violations:
- Comment out the `security_opt` section
- This may affect Vector's ability to access Docker logs

### 4. Volume Paths
All volume paths use relative paths (`./volumes/...`). Ensure:
- The build path in EasyPanel is set to `/docker` (as configured)
- The volumes directory exists in your repository
- EasyPanel has proper permissions to create/modify these directories

## Common EasyPanel Issues and Solutions

### Issue: "Some issues were found in your Docker Compose configuration"

**Possible causes:**
1. **Port conflicts**: Check if ports 5432, 8000, 8443, 6543 are already in use
2. **Docker socket access**: EasyPanel may restrict Docker socket mounting
3. **Volume permissions**: Ensure volume paths are accessible
4. **Missing environment variables**: All required env vars must be set in EasyPanel

### Recommended Environment Variables Check

Ensure all these are set in EasyPanel:
- `POSTGRES_PASSWORD`
- `JWT_SECRET`
- `ANON_KEY`
- `SERVICE_ROLE_KEY`
- `DASHBOARD_USERNAME`
- `DASHBOARD_PASSWORD`
- `SECRET_KEY_BASE`
- `VAULT_ENC_KEY`
- `PG_META_CRYPTO_KEY`
- `SITE_URL`
- `API_EXTERNAL_URL`
- `SUPABASE_PUBLIC_URL`
- And all other variables from your `.env` file

### If Issues Persist

1. **Check EasyPanel logs**: Look at the detailed error message by clicking "View" on the warning banner
2. **Test locally first**: Run `docker compose up` locally to ensure the configuration works
3. **Gradually enable services**: Comment out services one by one to identify the problematic service
4. **Contact EasyPanel support**: If the error message is unclear, share the full error with EasyPanel support

## Service Dependencies

The services have the following dependency chain:
- `vector` → `db` → `analytics` → (most other services)
- `db` → `supavisor`
- `rest` → `storage` → `imgproxy`

Ensure all services can start properly and health checks pass.
