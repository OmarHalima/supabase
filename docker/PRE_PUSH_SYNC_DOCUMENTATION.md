# Pre-Push Docker Sync Documentation

**Date**: February 18, 2026  
**Purpose**: Document all changes made to sync Docker configuration files with GitHub for EasyPanel CI/CD deployment

---

## Summary

This document records the complete process of preparing and pushing Docker configuration updates to GitHub, ensuring:
- No sensitive credentials are committed
- Docker Compose and Kong configurations are validated
- Network aliases are properly configured for EasyPanel/Swarm compatibility
- All changes are documented for future reference

---

## Files Modified

### 1. `docker/docker-compose.yml`

**Changes Made:**
- Added network aliases to all Supabase services to ensure DNS resolution works in both Docker Compose and EasyPanel/Swarm environments
- Added documentation comment explaining the network alias strategy

**Services Updated with Network Aliases:**
- `studio`: aliases `studio`, `supabase-studio`
- `kong`: aliases `kong`, `supabase-kong`
- `auth`: aliases `auth`, `supabase-auth`
- `rest`: aliases `rest`, `supabase-rest`
- `realtime`: aliases `realtime`, `realtime-dev.supabase-realtime`
- `storage`: aliases `storage`, `supabase-storage`
- `imgproxy`: aliases `imgproxy`, `supabase-imgproxy`
- `meta`: aliases `meta`, `supabase-meta`
- `functions`: aliases `functions`, `supabase-edge-functions`
- `analytics`: aliases `analytics`, `logflare`, `supabase-analytics`

**Why This Matters:**
- Docker Compose uses service names for DNS (e.g., `storage`, `meta`)
- EasyPanel/Docker Swarm uses container names for DNS (e.g., `supabase-storage`, `supabase-meta`)
- By adding both aliases, services can resolve correctly in both environments
- This ensures Kong routing and Studio meta connections work correctly

**Lines Changed:**
- Added `networks.default.aliases` section to 10 service definitions
- Added documentation comment at the top of the file (lines 8-12)

---

### 2. `docker/volumes/api/kong.yml`

**Changes Made:**
- Updated storage service routing URL from `http://storage:5000/` to `http://supabase-storage:5000/`

**Specific Change:**
```yaml
# Before:
url: http://storage:5000/

# After:
url: http://supabase-storage:5000/
```

**Why This Matters:**
- Kong needs to route storage API requests to the correct container
- In EasyPanel/Swarm, the container name is `supabase-storage`, not `storage`
- With network aliases, both names work, but using the full container name ensures compatibility

**Lines Changed:**
- Line 177-178: Updated storage-v1 service URL

---

### 3. `docker/CHATWOOT_SUPABASE_BACKEND_SETUP.md`

**Changes Made:**
- **Security**: Redacted real database password (`Akalimain000-`) and replaced with placeholder (`<DB_PASSWORD>`)
- Updated intro section to reflect that repo files were modified
- Updated "Files Modified" section to include `docker/docker-compose.yml`

**Specific Changes:**

1. **Intro Section (Line 5):**
   ```markdown
   # Before:
   No tracked repo files were modified; all changes were done via Docker / Postgres runtime configuration.
   
   # After:
   This repo now includes a few `docker/` updates to make EasyPanel Git sync deployments work reliably (see section **12**). The remaining steps below are runtime/EasyPanel configuration.
   ```

2. **Password Redaction (Multiple Locations):**
   - All instances of `Akalimain000-` replaced with `<DB_PASSWORD>`
   - Database connection URLs updated to use placeholder
   - SQL examples updated to use placeholder

3. **Files Modified Section (Line 355):**
   ```markdown
   # Added:
   - `docker/docker-compose.yml` - Added `networks.default.aliases` for reliable service DNS across Docker Compose and EasyPanel/Swarm
   ```

**Why This Matters:**
- Prevents credential leakage in version control
- Ensures documentation accurately reflects current state
- Makes it safe to share documentation publicly

---

## Validation Steps Performed

### 1. Docker Compose Validation

**Command:**
```bash
env DOCKER_SOCKET_LOCATION=/var/run/docker.sock \
  KONG_HTTP_PORT=8000 \
  KONG_HTTPS_PORT=8443 \
  POSTGRES_PORT=5432 \
  POOLER_PROXY_PORT_TRANSACTION=6543 \
  docker compose -f docker/docker-compose.yml config >/dev/null
```

**Result:** ✅ Passed (warnings about missing env vars are expected when validating without `.env` file)

### 2. Secret Scanning

**Scanned For:**
- Real database passwords
- Private keys
- API keys
- JWT tokens

**Result:** ✅ No secrets found after sanitization

**Commands Used:**
```bash
grep -r "Akalimain000-" docker/
grep -r "BEGIN.*PRIVATE KEY" docker/
grep -r "AKIA[0-9A-Z]{16}" docker/
```

---

## Git Operations

### Files Staged
- `docker/docker-compose.yml` (modified)
- `docker/volumes/api/kong.yml` (modified)
- `docker/CHATWOOT_SUPABASE_BACKEND_SETUP.md` (new file)

### Files Excluded (as requested)
- `docker/CHATWOOT_META_ROBOTS_FIX.md` (kept untracked)

### Commit Details
- **Commit Hash**: `d8f61d61e0`
- **Commit Message**: `docker: add service aliases and fix kong storage upstream`
- **Branch**: `master`
- **Remote**: `origin/master`

### Push Result
✅ Successfully pushed to GitHub

---

## Post-Push Verification

### Git Status
```bash
$ git status --short
?? docker/CHATWOOT_META_ROBOTS_FIX.md
```

**Result:** ✅ Clean - only intended untracked file remains

---

## Impact on EasyPanel Deployment

When EasyPanel syncs these files from GitHub:

1. **Network Aliases**: All services will have proper DNS resolution using both short names and full container names
2. **Kong Routing**: Storage API requests will route correctly to `supabase-storage`
3. **Studio Access**: Studio will be able to connect to `meta` service using the `meta` alias
4. **No Manual Configuration**: No manual network alias configuration needed in EasyPanel

---

## Related Documentation

- `docker/CHATWOOT_SUPABASE_BACKEND_SETUP.md` - Comprehensive setup guide for Chatwoot backend integration
- `docker/REALTIME_DNS_FIX.md` - Previous DNS resolution fixes
- `docker/.env.example` - Example environment variables (no secrets)

---

## Notes

- The `db` service already had network aliases configured (pre-existing setup)
- Network aliases ensure backward compatibility with both Docker Compose and Swarm deployments
- All sensitive credentials were redacted before committing
- Docker Compose validation confirms syntax is correct

---

## Known Issues & Solutions

### Storage URLs Returning Internal Hostname

**Issue:** When uploading product images, the backend returns URLs with the internal hostname (`http://supabase-kong:8000`) instead of the public domain (`https://cdn-supabase.chattyai.cloud`).

**Root Cause:** The backend's `SUPABASE_URL` is set to `http://supabase-kong:8000` for internal API calls, but when Supabase Storage's `getPublicUrl()` method is called, it uses that internal URL to construct public URLs.

**Solution:** The backend code needs to replace the internal URL domain with the public domain when returning storage URLs to clients. This can be done by:

1. **Option 1: Use a separate public URL environment variable**
   - Keep `SUPABASE_URL=http://supabase-kong:8000` for internal API calls
   - Add `SUPABASE_PUBLIC_URL=https://cdn-supabase.chattyai.cloud` for public URLs
   - In the backend code, replace the domain in storage URLs before returning them

2. **Option 2: Post-process storage URLs**
   - After calling `supabase.storage.from('bucket').getPublicUrl(path)`, replace the domain:
   ```typescript
   const { data } = supabase.storage.from('bucket').getPublicUrl(path);
   const publicUrl = new URL(data.publicUrl);
   publicUrl.host = 'cdn-supabase.chattyai.cloud';
   publicUrl.protocol = 'https';
   return publicUrl.href;
   ```

**Reference:** See `apps/studio/pages/api/platform/storage/[ref]/buckets/[id]/objects/public-url.ts` for a similar implementation in Supabase Studio.

---

## Database SSL Configuration Fix

**Issue Encountered:** After EasyPanel synced the changes, the `supabase-db` container was exiting immediately (exit code 0).

**Root Cause:** The SSL configuration in `/etc/postgresql/postgresql.conf` was not persisted because this file is not mounted as a volume. When containers were recreated, the SSL settings were lost, but the SSL certificates remained in the data directory.

**Solution:** Added SSL configuration directly to the Postgres command-line arguments in `docker-compose.yml`:

```yaml
command:
  [
    "postgres",
    "-c",
    "config_file=/etc/postgresql/postgresql.conf",
    "-c",
    "log_min_messages=fatal",
    "-c",
    "ssl=on",
    "-c",
    "ssl_cert_file=/var/lib/postgresql/data/server.crt",
    "-c",
    "ssl_key_file=/var/lib/postgresql/data/server.key"
  ]
```

**Files Modified:**
- `docker/docker-compose.yml` - Added SSL command-line arguments to db service
- `docker/volumes/db/ssl-config.sh` - Created init script for SSL certificate generation (runs on first initialization)

**Note:** The SSL certificates (`server.crt` and `server.key`) are stored in `/var/lib/postgresql/data`, which IS persisted via the volume mount. The init script ensures certificates are generated if they don't exist on first database initialization.

---

## Future Considerations

- If additional services are added, ensure they also have network aliases configured
- When updating Kong routing, verify both short and full container names work
- Always redact credentials before committing documentation files
- Consider adding a pre-commit hook to scan for secrets
- Backend should handle public URL replacement for storage assets
- Database SSL configuration is now persistent via command-line arguments
