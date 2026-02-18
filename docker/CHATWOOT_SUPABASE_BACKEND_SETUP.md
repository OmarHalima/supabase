## ChattyAI Backend ↔ Supabase DB Setup (EasyPanel + Swarm)

This document records the runtime changes made to get the `supabase_chattyai-backend` NestJS service talking to the local Supabase Postgres (`supabase-db`) over SSL inside EasyPanel’s Docker Swarm setup.

This repo now includes a few `docker/` updates to make EasyPanel Git sync deployments work reliably (see section **12**). The remaining steps below are runtime/EasyPanel configuration.

---

## 1. Network wiring

- **Goal**: Put the backend and Supabase DB on the same network so `supabase-db` resolves from the backend.

- **Actions**
  - Attach the DB container to the overlay network used by the backend:
    - `easypanel-supabase` overlay already used by:
      - `supabase_chattyai-backend`
      - `supabase_chattyai-frontend`
  - Connected `supabase-db` to that network:
    - `docker network connect easypanel-supabase supabase-db`

- **Resulting networks**
  - Backend task containers: `easypanel`, `easypanel-supabase`
  - DB container: `supabase_supabase_default`, `easypanel-supabase`
  - Hostname used by backend: **`supabase-db`** on port **5432**

---

## 2. Backend service environment (Swarm)

- **Service**: `supabase_chattyai-backend`
- **Problem symptoms**
  - Initially:
    - `getaddrinfo ENOTFOUND base` (bad hostname parsing)
    - later `The server does not support SSL connections`
    - later `password authentication failed for user "postgres.default"`
    - later `must be owner of table client_config`
    - later `function uuid_generate_v4() does not exist`

### 2.1. Fixed DB URL / hostname

Original env (from EasyPanel) had:

```text
SUPABASE_DB_URL=DATABASE_URL=postgresql://postgres.default:<DB_PASSWORD>@supabase-db:5432/postgres?sslmode=disable
```

- This double-prefix (`SUPABASE_DB_URL=DATABASE_URL=...`) caused parsing issues inside the backend and ultimately produced the bogus host `base`.

**Service env changes (via `docker service update`):**

- Removed the bad value and set clean URLs:

```text
SUPABASE_DB_URL=postgresql://postgres.default:<DB_PASSWORD>@supabase-db:5432/postgres?sslmode=require
DATABASE_URL=postgresql://postgres.default:<DB_PASSWORD>@supabase-db:5432/postgres?sslmode=require
```

- Added explicit DB connection envs that the Nest/TypeORM config reads:

```text
DB_HOST=supabase-db
DB_PORT=5432
DB_USERNAME=postgres.default
DB_PASSWORD=<DB_PASSWORD>
DB_NAME=postgres
DB_CONNECTION_TIMEOUT_MS=30000
DB_RETRY_ATTEMPTS=30
DB_RETRY_DELAY_MS=5000
```

### 2.2. SSL env cleanup

During debugging we temporarily added flags like:

```text
PGSSLMODE=disable
DB_SSL=...
TYPEORM_SSL=...
```

Once Postgres was correctly configured for SSL (see section 3), these were **removed** and we standardized on `sslmode=require` in the URLs above. There should be **no SSL-disable envs** left on the service now.

You can re‑inspect current env with:

```bash
docker service inspect supabase_chattyai-backend --format '{{json .Spec.TaskTemplate.ContainerSpec.Env}}'
```

---

## 3. Enabling SSL on `supabase-db`

- **Container**: `supabase-db`
- **Image**: `supabase/postgres:15.8.1.085`
- **Actual config file in use**
  - Verified via:
    - `SHOW config_file;` → `/etc/postgresql/postgresql.conf`
  - Note: the file in `/var/lib/postgresql/data/postgresql.conf` is *not* the active one; SSL must be configured in `/etc/postgresql/postgresql.conf`.

### 3.1. Certificate generation (self‑signed, local only)

Inside `supabase-db`:

```bash
cd /var/lib/postgresql/data
openssl req -new -x509 -days 365 -nodes -text \
  -out server.crt \
  -keyout server.key \
  -subj "/CN=supabase-db"

chmod 600 server.key
chown postgres:postgres server.key server.crt
```

Files created:

- `/var/lib/postgresql/data/server.crt`
- `/var/lib/postgresql/data/server.key`

### 3.2. Postgres SSL config

Appended to `/etc/postgresql/postgresql.conf`:

```text
ssl = on
ssl_cert_file = '/var/lib/postgresql/data/server.crt'
ssl_key_file  = '/var/lib/postgresql/data/server.key'
```

Then restarted `supabase-db`:

```bash
docker restart supabase-db
docker exec supabase-db psql -U postgres -c "SHOW ssl;"
-- result: ssl = on
```

At this point the server accepts SSL connections on 5432.

---

## 4. Database role / auth model

- **Goal**: Match the backend’s expected credentials while keeping things isolated from system roles.
- **App role used by backend**: `"postgres.default"`

### 4.1. Role creation

From inside `supabase-db`:

```sql
CREATE ROLE "postgres.default" WITH LOGIN PASSWORD '<DB_PASSWORD>';
```

Confirm:

```sql
SELECT rolname FROM pg_roles WHERE rolname = 'postgres.default';
```

Manual test using the same URL pattern as the backend:

```bash
psql "postgresql://postgres.default:<DB_PASSWORD>@localhost:5432/postgres?sslmode=require" \
  -c "SELECT current_user, current_database();"
```

### 4.2. Privileges

We granted the role appropriate privileges and membership so it can own and manage the application schema:

```sql
-- Let postgres.default act with postgres membership
GRANT postgres TO "postgres.default";

-- Basic schema + object privileges
GRANT ALL ON SCHEMA public TO "postgres.default";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "postgres.default";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "postgres.default";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO "postgres.default";
```

> These are appropriate for a local, self‑hosted environment where this role is strictly an app backend user. Tighten in production if necessary.

---

## 5. Table ownership for TypeORM

TypeORM’s schema sync (`synchronize: true` or equivalent) needs to ALTER columns on existing tables, which requires table ownership.

- **Symptom**
  - `QueryFailedError: must be owner of table client_config`

### 5.1. Fix strategy

We made `"postgres.default"` the owner of the application tables in `public`:

```sql
-- Grant postgres membership (already shown above)
GRANT postgres TO "postgres.default";

-- As "postgres.default", reassign ownership of all public tables
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
  LOOP
    EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) ||
            ' OWNER TO "postgres.default"';
  END LOOP;
END
$$;
```

If you ever add tables manually as a different owner and see the same error again, re‑run a variant of the block above.

---

## 6. `uuid_generate_v4()` / `uuid-ossp` extension

The schema uses `uuid_generate_v4()` defaults. On Supabase, `uuid-ossp` is installed into the `extensions` schema.

- Verified extension:

```sql
SELECT extname, nspname
FROM pg_extension e
JOIN pg_namespace n ON e.extnamespace = n.oid
WHERE extname = 'uuid-ossp';
-- extname = 'uuid-ossp', nspname = 'extensions'
```

- Calling `uuid_generate_v4()` initially failed for the app role because the `extensions` schema was not on `search_path`.

### 6.1. Search path fix

We set the search path for both the role and the database:

```sql
-- As postgres user:
ALTER ROLE "postgres.default" SET search_path = public, extensions;
ALTER DATABASE postgres SET search_path = public, extensions;
```

Validation:

```bash
psql "postgresql://postgres.default:<DB_PASSWORD>@localhost:5432/postgres?sslmode=require" \
  -c "SELECT uuid_generate_v4();"
```

---

## 7. Final verification

- **Postgres**
  - `SHOW ssl;` → `on`
  - `SELECT current_user;` as app URL → `postgres.default`
  - `SELECT uuid_generate_v4();` works

- **Backend**
  - Service: `supabase_chattyai-backend` (Swarm)
  - DB URL: `postgresql://postgres.default:<DB_PASSWORD>@supabase-db:5432/postgres?sslmode=require`
  - Logs show:
    - `Nest application successfully started`
    - `Application is running on: http://localhost:3001`
    - `API Documentation: http://localhost:3001/api/docs`

---

## 8. Supabase Auth & Storage Services Setup

### 8.1. Starting Supabase Services

The backend needs Supabase Auth and Storage services running locally. These were stopped and needed to be started:

```bash
# Start required Supabase services
docker start supabase-kong supabase-auth supabase-rest supabase-storage supabase-imgproxy supabase-studio

# Connect them to the backend network
docker network connect easypanel-supabase supabase-kong
docker network connect easypanel-supabase supabase-auth
docker network connect easypanel-supabase supabase-rest
docker network connect easypanel-supabase supabase-storage
docker network connect easypanel-supabase supabase-imgproxy
docker network connect easypanel-supabase supabase-studio

# Add storage alias for Kong routing
docker network disconnect easypanel-supabase supabase-storage
docker network connect --alias storage easypanel-supabase supabase-storage
```

### 8.2. Updating Backend SUPABASE_URL

The backend was pointing to an external Supabase URL (`https://cdn-supabase.chattyai.cloud`) which returned 503. Updated to use local Kong gateway:

```bash
docker service update \
  --env-rm SUPABASE_URL \
  --env-add "SUPABASE_URL=http://supabase-kong:8000" \
  supabase_chattyai-backend
```

**Kong Gateway Routes:**
- Auth: `http://supabase-kong:8000/auth/v1/*` → `http://supabase-auth:9999/*`
- Storage: `http://supabase-kong:8000/storage/v1/*` → `http://supabase-storage:5000/*`
- REST API: `http://supabase-kong:8000/rest/v1/*` → `http://supabase-rest:3000/*`

### 8.3. Fixing Kong Storage Routing

Kong's config file (`docker/volumes/api/kong.yml`) was updated to use the correct container name:

**Changed:**
```yaml
url: http://storage:5000/
```

**To:**
```yaml
url: http://supabase-storage:5000/
```

Also added network alias `storage` for `supabase-storage` so Kong can resolve it either way.

### 8.4. Accessing Supabase Studio

Studio runs on port 3000 internally, but port 3000 is already used by EasyPanel. Created a proxy container to expose Studio on port 3002:

```bash
docker run -d --name studio-port-forward \
  --network easypanel-supabase \
  -p 3002:3000 \
  --restart unless-stopped \
  nginx:alpine sh -c 'echo "server { listen 3000; location / { proxy_pass http://supabase-studio:3000; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; } }" > /etc/nginx/conf.d/default.conf && nginx -g "daemon off;"'
```

**Access Studio at:** `http://your-vps-ip:3002`

---

## 9. Files Modified

### Runtime Configuration (Not in Git)
- `/etc/postgresql/postgresql.conf` (inside `supabase-db` container) - SSL enabled
- `/var/lib/postgresql/data/server.crt` and `server.key` - SSL certificates
- `/home/kong/kong.yml` (inside `supabase-kong` container) - Storage routing updated

### Source Files (In Git)
- `docker/volumes/api/kong.yml` - Updated storage URL from `http://storage:5000` to `http://supabase-storage:5000`
- `docker/docker-compose.yml` - Added `networks.default.aliases` for reliable service DNS across Docker Compose and EasyPanel/Swarm

---

## 10. Complete Setup Checklist

If you ever need to recreate this from scratch on a new VPS:

1. **Network Setup:**
   - Attach `supabase-db` to `easypanel-supabase` network
   - Start and connect all Supabase services (kong, auth, rest, storage, imgproxy, studio)
   - Add `storage` alias for `supabase-storage`

2. **Database Configuration:**
   - Enable SSL on `supabase-db` (section **3**)
   - Create `postgres.default` user with password `<DB_PASSWORD>` (section **4**)
   - Grant privileges and ownership (sections **4–5**)
   - Set search_path for uuid extension (section **6**)

3. **Backend Service:**
   - Update `SUPABASE_URL=http://supabase-kong:8000` (section **8.2**)
   - Ensure DB connection strings use `sslmode=require` (section **2**)
   - Set all `DB_*` environment variables (section **2.1**)

4. **Storage & Studio:**
   - Update Kong config for storage routing (section **8.3**)
   - Set up Studio port forwarding if needed (section **8.4**)
   - Start `supabase-meta` and `supabase-analytics` services
   - Connect them to `easypanel-supabase` network with proper aliases

5. **Verify:**
   - Backend connects to DB successfully
   - Auth login works
   - Storage bucket operations work
   - Studio accessible on port 3002

---

## 11. Additional Service Fixes

### 11.1. Studio Meta Service Connection

Studio requires the `pg-meta` service (container name: `supabase-meta`) to function properly. It was failing with `getaddrinfo EAI_AGAIN meta` errors.

**Fix:**
```bash
# Start meta service
docker start supabase-meta

# Connect to network with alias
docker network disconnect easypanel-supabase supabase-meta
docker network connect --alias meta easypanel-supabase supabase-meta

# Also ensure analytics is running (Studio depends on it)
docker start supabase-analytics
docker network connect easypanel-supabase supabase-analytics

# Restart Studio to pick up changes
docker restart supabase-studio
```

**Verification:**
- Studio logs should show: `Ready in XXXms` without meta connection errors
- Studio accessible at: `http://your-vps-ip:3002`

### 11.2. Storage Authorization Headers

Storage API requires proper authorization headers. The Supabase JS client should automatically add these when initialized with `SUPABASE_ANON_KEY` or `SUPABASE_SERVICE_KEY`.

**If storage requests fail with "headers must have required property 'authorization'":**
- Verify backend has `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_KEY` env vars set
- Ensure backend is using `SUPABASE_URL=http://supabase-kong:8000` (not external URL)
- Check that Kong is routing storage requests correctly (section **8.3**)

**Storage endpoint:** `http://supabase-kong:8000/storage/v1/*` → `http://supabase-storage:5000/*`

---

## 12. Docker Compose File Updates for CI/CD Sync

To ensure EasyPanel deployments work correctly when syncing from GitHub, the following updates have been made to `docker/docker-compose.yml`:

### 12.1. Network Aliases Added

All Supabase services now have explicit network aliases defined to ensure proper DNS resolution:

- **`db`** service: aliases `db`, `supabase-db`
- **`kong`** service: aliases `kong`, `supabase-kong`
- **`auth`** service: aliases `auth`, `supabase-auth`
- **`rest`** service: aliases `rest`, `supabase-rest`
- **`storage`** service: aliases `storage`, `supabase-storage`
- **`meta`** service: aliases `meta`, `supabase-meta`
- **`studio`** service: aliases `studio`, `supabase-studio`
- **`imgproxy`** service: aliases `imgproxy`, `supabase-imgproxy`
- **`analytics`** service: aliases `analytics`, `logflare`, `supabase-analytics`
- **`realtime`** service: aliases `realtime`, `realtime-dev.supabase-realtime`
- **`functions`** service: aliases `functions`, `supabase-edge-functions`

**Why this matters:**
- Docker Compose uses service names for DNS (e.g., `storage`, `meta`)
- EasyPanel/Docker Swarm uses container names for DNS (e.g., `supabase-storage`, `supabase-meta`)
- By adding both aliases, services can resolve correctly in both environments
- This ensures Kong routing (`kong.yml` → `http://supabase-storage:5000/`) and Studio meta connections (`http://meta:8080`) work correctly

### 12.2. Files Modified

1. **`docker/docker-compose.yml`**
   - Added `networks.default.aliases` section to all service definitions listed above
   - Added documentation comment explaining the network alias strategy

2. **`docker/volumes/api/kong.yml`**
   - Updated storage service URL from `http://storage:5000/` to `http://supabase-storage:5000/`
   - This ensures Kong can route storage requests correctly when deployed via EasyPanel

### 12.3. Verification

When EasyPanel syncs these files from GitHub:
- ✅ Kong should be able to route to `supabase-storage` using the full container name
- ✅ Studio should be able to connect to `meta` service using the short alias
- ✅ All inter-service communication should work using either short or full names
- ✅ No manual network alias configuration needed in EasyPanel

**Note**: The `db` service already had network aliases configured (this was a pre-existing setup).

