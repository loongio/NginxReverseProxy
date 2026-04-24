server {
    listen 80;
    server_name example.com;
    return 301 https://$host$request_uri;
}

# Main site reverse proxy for duckduckgo.com
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name example.com;

    # Block access if not allowed from CN
    if ($allow_cn = 0) {
        return 403;
    }

    root /dev/null;
    resolver 9.9.9.9 1.1.1.1 [2620:fe::fe] [2606:4700:4700::1111];

    # SSL certificates
    ssl_certificate /root/.acme.sh/*.example.com_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/*.example.com_ecc/*.example.com.key;
    ssl_trusted_certificate /root/.acme.sh/*.example.com_ecc/ca.cer;
    ssl_stapling off;
    ssl_stapling_verify on;

    # SSL session cache for returning visitors
    ssl_session_cache shared:MozSSL:10m; # about 40000 sessions
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # SSL configuration (intermediate)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Enable HSTS (63072000 seconds)
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Block known crawlers and bots
    if ($http_user_agent ~* "qihoobot|Baiduspider|Googlebot|Googlebot-Mobile|Googlebot-Image|Mediapartners-Google|Adsbot-Google|Feedfetcher-Google|Yahoo! Slurp|Yahoo! Slurp China|YoudaoBot|Sosospider|Sogou spider|Sogou web spider|MSNBot|ia_archiver|Tomato Bot")
    {
        return 403;
    }

    location / {
        proxy_set_header Accept-Encoding ""; # Disable gzip for sub_filter
        proxy_set_header Host 'duckduckgo.com';
        proxy_pass https://duckduckgo.com;
        proxy_ssl_name duckduckgo.com;
        proxy_ssl_server_name on;

        proxy_set_header Origin "duckduckgo.com";
        proxy_set_header Referer "duckduckgo.com";

        # Content replacement for domain and subdomains
        sub_filter_types *;
        sub_filter_once off;
        sub_filter 'domain:"duckduckgo.com"' 'domain:"example.com"';
        sub_filter 'sub:"external-content",path:"/' 'sub:"external-content",path:"/';
        sub_filter 'links.duckduckgo.com' 'links.example.com';
        sub_filter 'improving.duckduckgo.com' 'improving.example.com';

        proxy_set_header Cookie $http_cookie;
        proxy_cookie_domain duckduckgo.com $host;

        proxy_hide_header Content-Security-Policy;
        proxy_hide_header Access-Control-Allow-Origin;
        add_header Access-Control-Allow-Origin $http_origin;

        # Uncomment below to enable server-side cache
        # proxy_cache ZONECACHE;
        # proxy_cache_key $scheme$http_host$uri$is_args$args;
        # proxy_cache_valid 200 304 15s;
    }
}

# Reverse proxy for external-content.duckduckgo.com
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name external-content.example.com;
    root /dev/null;
    resolver 9.9.9.9 1.1.1.1 [2620:fe::fe] [2606:4700:4700::1111];

    # SSL certificates
    ssl_certificate /root/.acme.sh/*.example.com_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/*.example.com_ecc/*.example.com.key;
    ssl_trusted_certificate /root/.acme.sh/*.example.com_ecc/ca.cer;
    ssl_stapling off;
    ssl_stapling_verify on;

    # SSL session cache for returning visitors
    ssl_session_cache shared:MozSSL:10m; # about 40000 sessions
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # SSL configuration (intermediate)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Enable HSTS (63072000 seconds)
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Prevent indexing by robots
    add_header X-Robots-Tag "none" always;

    location / {
        proxy_set_header Host 'external-content.duckduckgo.com';
        proxy_pass https://external-content.duckduckgo.com;
        proxy_ssl_name external-content.duckduckgo.com;
        proxy_ssl_server_name on;

        proxy_set_header Origin "";
        proxy_set_header Referer "";

        proxy_hide_header Content-Security-Policy;
        proxy_hide_header Access-Control-Allow-Origin;
        add_header Access-Control-Allow-Origin $http_origin;

        # Uncomment below to enable server-side cache
        # proxy_cache ZONECACHE;
        # proxy_cache_key $scheme$http_host$uri$is_args$args;
        # proxy_cache_valid 200 304 30s;
    }
}

# Reverse proxy for links.duckduckgo.com
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name links.example.com;
    root /dev/null;
    resolver 9.9.9.9 1.1.1.1 [2620:fe::fe] [2606:4700:4700::1111];

    # SSL certificates
    ssl_certificate /root/.acme.sh/*.example.com_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/*.example.com_ecc/*.example.com.key;
    ssl_trusted_certificate /root/.acme.sh/*.example.com_ecc/ca.cer;
    ssl_stapling off;
    ssl_stapling_verify on;

    # SSL session cache for returning visitors
    ssl_session_cache shared:MozSSL:10m; # about 40000 sessions
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # SSL configuration (intermediate)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Enable HSTS (63072000 seconds)
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Prevent indexing by robots
    add_header X-Robots-Tag "none" always;

    location / {
        proxy_set_header Host 'links.duckduckgo.com';
        proxy_pass https://links.duckduckgo.com;
        proxy_ssl_name links.duckduckgo.com;
        proxy_ssl_server_name on;

        proxy_set_header Origin "";
        proxy_set_header Referer "";

        # Uncomment below to enable server-side cache
        # proxy_cache ZONECACHE;
        # proxy_cache_key $scheme$http_host$uri$is_args$args;
        # proxy_cache_valid 200 304 30s;
    }
}

# Reverse proxy for improving.duckduckgo.com (tracking)
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name improving.example.com;
    root /dev/null;
    resolver 9.9.9.9 1.1.1.1 [2620:fe::fe] [2606:4700:4700::1111];

    # SSL certificates
    ssl_certificate /root/.acme.sh/*.example.com_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/*.example.com_ecc/*.example.com.key;
    ssl_trusted_certificate /root/.acme.sh/*.example.com_ecc/ca.cer;
    ssl_stapling off;
    ssl_stapling_verify on;

    # SSL session cache for returning visitors
    ssl_session_cache shared:MozSSL:10m; # about 40000 sessions
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # SSL configuration (intermediate)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Enable HSTS (63072000 seconds)
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Prevent indexing by robots
    add_header X-Robots-Tag "none" always;

    location / {
        return 200;
    }
}
