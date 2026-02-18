# Fix Meta/Facebook "robots.txt" Error for Chatwoot Images

Meta reports: **"(#100) The media server does not allow downloading of the media due to robots.txt"** when fetching images from **chatwoot-development.chattyai.cloud** (e.g. `/rails/active_storage/...`). That host is your **Chatwoot** app, not Supabase/Kong. Fix it on the **Chatwoot server** as below.

---

## 1. Serve a robots.txt that allows Meta on media paths

On the server that hosts **chatwoot-development.chattyai.cloud**, serve this `robots.txt` at the root (e.g. via Nginx or the Rails app):

```txt
User-agent: facebookexternalhit
Allow: /
User-agent: Facebot
Allow: /
User-agent: facebookcatalog
Allow: /
User-agent: WhatsApp
Allow: /

User-agent: *
Disallow: /admin
Allow: /rails/active_storage/
```

- Meta bots get `Allow: /` so they can fetch any URL (including `/rails/active_storage/...`).
- Other crawlers get a generic policy that still allows `/rails/active_storage/`.

---

## 2. Nginx example (if you use Nginx in front of Chatwoot)

Add a `location` that serves the above content for `chatwoot-development.chattyai.cloud`:

```nginx
server {
  server_name chatwoot-development.chattyai.cloud;
  # ... existing root, ssl, etc. ...

  location = /robots.txt {
    default_type text/plain;
    return 200 'User-agent: facebookexternalhit\nAllow: /\nUser-agent: Facebot\nAllow: /\nUser-agent: facebookcatalog\nAllow: /\nUser-agent: WhatsApp\nAllow: /\n\nUser-agent: *\nDisallow: /admin\nAllow: /rails/active_storage/\n';
  }

  location / {
    # existing proxy_pass to Rails/Puma
    proxy_pass http://...;
    # ...
  }
}
```

Then: `sudo nginx -t && sudo systemctl reload nginx`

---

## 3. If Chatwoot is behind a reverse proxy that strips User-Agent

Some setups block or alter the `User-Agent` header. Ensure **facebookexternalhit** (and similar) are **not** blocked or rewritten so the app can allow them. If you have bot-blocking or rate-limiting, add an exception for Meta’s IPs or for requests to `/rails/active_storage/` with Meta’s User-Agent.

---

## 4. Verify

From the Chatwoot server or your machine:

```bash
# robots.txt allows Meta
curl -s https://chatwoot-development.chattyai.cloud/robots.txt

# Meta UA can fetch an image (use a real URL from your logs)
curl -I -A "facebookexternalhit/1.1" "https://chatwoot-development.chattyai.cloud/rails/active_storage/blobs/redirect/YOUR_SIGNED_ID/filename.png"
```

You should see `200` (or `302` to the final image) for the image request when using Meta’s User-Agent.

---

**Summary:** The Supabase/Kong stack (api.chattyai.cloud) already serves a suitable robots.txt. The Meta error is for **chatwoot-development.chattyai.cloud**. Apply the robots.txt (and optional Nginx config) above on the **Chatwoot** host so Meta can download media from `/rails/active_storage/`.
