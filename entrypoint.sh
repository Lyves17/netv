#!/bin/sh
set -e
# Entrypoint: fix permissions and drop to netv user
#
# Handles two common Docker issues:
# 1. Bind-mounted ./cache owned by host user (permission denied)
# 2. /dev/dri/renderD128 GID mismatch (VAAPI unavailable)

# Fix cache directory ownership (skip if already correct to avoid slow recursive chown)
# Build/runtime note: this only applies to bind-mounted cache (e.g., NAS),
# not to image layers, so it does not affect build reproducibility.
mkdir -p /app/cache
if [ "$(stat -c '%U' /app/cache)" != "netv" ]; then
    chown -R netv:netv /app/cache 2>/dev/null || true
fi
# Ensure writable even on filesystems that ignore chown (e.g., some NAS mounts)
if ! gosu netv sh -c "touch /app/cache/.perm_test && rm /app/cache/.perm_test" 2>/dev/null; then
    chmod -R u+rwX,g+rwX /app/cache 2>/dev/null || true
    chmod g+s /app/cache 2>/dev/null || true
fi
# Final verification - warn if still not writable
if ! gosu netv sh -c "touch /app/cache/.perm_test && rm /app/cache/.perm_test" 2>/dev/null; then
    echo "WARNING: /app/cache is not writable by netv user"
    echo "Cache operations may fail. Check volume permissions."
fi
mkdir -p /app/cache/users
if [ "$(stat -c '%U' /app/cache/users)" != "netv" ]; then
    chown -R netv:netv /app/cache/users 2>/dev/null || true
fi
# Ensure writable even on filesystems that ignore chown (e.g., some NAS mounts)
if ! gosu netv sh -c "touch /app/cache/users/.perm_test && rm /app/cache/users/.perm_test" 2>/dev/null; then
    chmod -R u+rwX,g+rwX /app/cache/users 2>/dev/null || true
    chmod g+s /app/cache/users 2>/dev/null || true
fi
# Final verification - warn if still not writable
if ! gosu netv sh -c "touch /app/cache/users/.perm_test && rm /app/cache/users/.perm_test" 2>/dev/null; then
    echo "WARNING: /app/cache/users is not writable by netv user"
    echo "Cache operations may fail. Check volume permissions."
fi

# Add netv user to render device group (for VAAPI hardware encoding)
if [ -e /dev/dri/renderD128 ]; then
    RENDER_GID=$(stat -c '%g' /dev/dri/renderD128)
    RENDER_ADDED=false
    if groupadd --gid "$RENDER_GID" hostrender 2>/dev/null; then
        :  # Created new group
    fi
    if usermod -aG hostrender netv 2>/dev/null; then
        RENDER_ADDED=true
    fi
    if [ "$RENDER_ADDED" = "false" ]; then
        echo "WARNING: Could not add netv to render group (GID $RENDER_GID)"
        if [ "$RENDER_GID" = "65534" ]; then
            echo "  GID 65534 (nogroup) indicates Docker user namespace mapping issue."
            echo "  This is usually harmless - VAAPI may still work if container has device access."
            echo "  To fix: ensure 'render' group exists on host and user is in it, or use --privileged"
        else
            echo "  VAAPI hardware encoding may not be available."
            echo "  To fix on host: sudo usermod -aG render \$USER (then restart Docker)"
        fi
    fi
fi

# Drop to netv user and run the app

# Initialize default settings and admin user on every start
# (Render has ephemeral storage, so we recreate on each boot)
python3 << 'PYEOF'
import json, pathlib, hashlib, secrets, uuid

cache_dir = pathlib.Path('/app/cache')
cache_dir.mkdir(exist_ok=True)
users_dir = cache_dir / 'users'
users_dir.mkdir(exist_ok=True)

settings_file = cache_dir / 'server_settings.json'
settings = {}
if settings_file.exists():
    try:
        settings = json.loads(settings_file.read_text())
    except Exception:
        settings = {}

# Ensure admin user exists
if 'users' not in settings or not settings['users']:
    salt = secrets.token_hex(16)
    key = hashlib.pbkdf2_hmac('sha256', b'Mentenon', salt.encode(), 100000)
    settings['users'] = {'admin': {'password': f'{salt}:{key.hex()}', 'admin': True}}
    admin_dir = users_dir / 'admin'
    admin_dir.mkdir(exist_ok=True)
    (admin_dir / 'settings.json').write_text(json.dumps({
        'guide_filter': [],
        'captions_enabled': True,
        'watch_history': {},
        'favorites': {'series': {}, 'movies': {}},
        'cc_lang': '', 'cc_style': {}, 'cast_host': '',
    }, indent=2))
    print('Default admin user created')

# Ensure FR source exists
if 'sources' not in settings or not settings['sources']:
    settings['sources'] = [
{
                                    "id": "5ea099d6",
                                    "name": "iptv-org France",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/fr.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "f880c243",
                                    "name": "iptv-org USA",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/us.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "a3ad3402",
                                    "name": "iptv-org UK",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/gb.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "e5323b0d",
                                    "name": "iptv-org Germany",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/de.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "32f2790a",
                                    "name": "iptv-org Spain",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/es.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "87814c6a",
                                    "name": "iptv-org Italy",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/it.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "8e280c00",
                                    "name": "iptv-org Portugal",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/pt.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "f8c66ccb",
                                    "name": "iptv-org Brazil",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/br.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "6f19a70c",
                                    "name": "iptv-org Canada",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/ca.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "ff4e6ef2",
                                    "name": "iptv-org Belgium",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/be.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "736bb223",
                                    "name": "iptv-org Switzerland",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/ch.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "78005248",
                                    "name": "iptv-org Morocco",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/ma.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "ded53eb2",
                                    "name": "iptv-org Tunisia",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/tn.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "a4c5dc85",
                                    "name": "iptv-org Algeria",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/dz.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "e2b44fbc",
                                    "name": "iptv-org Senegal",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/countries/sn.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    },
{
                                    "id": "078d0ba8",
                                    "name": "iptv-org (all channels)",
                                    "type": "m3u",
                                    "url": "https://iptv-org.github.io/iptv/all.m3u",
                                    "username": "",
                                    "password": "",
                                    "epg_timeout": 120,
                                    "epg_schedule": [],
                                    "epg_enabled": true,
                                    "epg_url": "",
                                    "deinterlace_fallback": true,
                                    "max_streams": 0
                    }
            ]
    print('Default country sources added')

# Ensure secret key
if 'secret_key' not in settings:
    settings['secret_key'] = secrets.token_hex(32)

settings_file.write_text(json.dumps(settings, indent=2))
print('Settings initialized')
PYEOF
exec gosu netv python3 main.py --port "${NETV_PORT:-8000}" ${NETV_HTTPS:+--https}
