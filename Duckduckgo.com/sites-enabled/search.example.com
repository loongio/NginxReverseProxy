server {
    listen 80;
    server_name search.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;

    server_name search.example.com;

    root /dev/null;
    resolver 8.8.8.8 1.1.1.1 valid=300s;

    # --- SSL configuration ---
    ssl_certificate /root/.acme.sh/search.example.com_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/search.example.com_ecc/search.example.com.key;

    ssl_session_cache shared:MozSSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    add_header Strict-Transport-Security "max-age=63072000" always;

    # Block crawlers (basic UA filter)
    if ($http_user_agent ~* "qihoobot|Baiduspider|Googlebot|Googlebot-Mobile|Googlebot-Image|Mediapartners-Google|Adsbot-Google|Feedfetcher-Google|Yahoo! Slurp|Yahoo! Slurp China|YoudaoBot|Sosospider|Sogou spider|Sogou web spider|MSNBot|ia_archiver|Tomato Bot") {
        return 403;
    }

    location / {
        proxy_set_header Accept-Encoding "";

        proxy_pass https://duckduckgo.com;
        proxy_set_header Host 'duckduckgo.com';

        proxy_ssl_name duckduckgo.com;
        proxy_ssl_server_name on;
        proxy_ssl_protocols TLSv1.2 TLSv1.3;

        proxy_set_header Origin "https://duckduckgo.com";
        proxy_set_header Referer "https://duckduckgo.com";

        proxy_cookie_domain duckduckgo.com search.example.com;
        proxy_redirect https://duckduckgo.com/ https://search.example.com/;

        # --- Core fixes ---
        # Ensure responses containing URLs or integrity attributes are adapted
        sub_filter_types text/css text/xml application/javascript application/json application/x-javascript;
        sub_filter_once off;

        # 1. Break SRI (Subresource Integrity) attribute to avoid integrity failures
        sub_filter 'integrity=' 'no-integrity=';

        # 2. Replace main-site links that include protocol (match longest strings first)
        # Ensure clicking logo or home links returns to search.example.com
        sub_filter 'https://duckduckgo.com' 'https://search.example.com';
        sub_filter 'http://duckduckgo.com' 'http://search.example.com';
        sub_filter '//duckduckgo.com' '//search.example.com';

        # 3. Replace specific subdomains as a fallback if hardcoded in upstream source
        sub_filter 'external-content.duckduckgo.com' 'external-content.example.com';
        sub_filter 'links.duckduckgo.com' 'links.example.com';
        sub_filter 'improving.duckduckgo.com' 'improving.example.com';

        # 4. Critical fix: replace bare domain variables
        # Replace 'duckduckgo.com' with 'example.com' (no leading subdomain)
        # This ensures JS concatenation like 'improving.' + var results in improving.example.com
        sub_filter 'duckduckgo.com' 'example.com';

        # --- Header handling ---
        proxy_hide_header Content-Security-Policy;
        proxy_hide_header X-Frame-Options;
        proxy_hide_header Access-Control-Allow-Origin;
        add_header Access-Control-Allow-Origin * always;
    }
}

# External content host (maps external-content.duckduckgo.com)
server {
    listen 443 ssl;

    server_name external-content.example.com;
    root /dev/null;
    resolver 9.9.9.9 1.1.1.1 [2620:fe::fe] [2606:4700:4700::1111];

    # SSL certificates for external content host
    ssl_certificate /root/.acme.sh/external-content.example.com_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/external-content.example.com_ecc/external-content.example.com.key;

    # SSL session cache for returning visitors
    ssl_session_cache shared:MozSSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # Intermediate TLS configuration (Mozilla recommended)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS (requires ngx_http_headers_module) - 63072000 seconds
    add_header Strict-Transport-Security "max-age=63072000" always;

    add_header X-Robots-Tag "none" always;

    # Local logs are intentionally disabled / not configured here

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

        # Optional server-side cache settings were present but are disabled/removed
    }
}

# Links host (maps links.duckduckgo.com)
server {
    listen 443 ssl;

    server_name links.example.com;
    root /dev/null;
    resolver 9.9.9.9 1.1.1.1 [2620:fe::fe] [2606:4700:4700::1111];

    # SSL certificates for links host
    ssl_certificate /root/.acme.sh/links.example.com_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/links.example.com_ecc/links.example.com.key;

    ssl_session_cache shared:MozSSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS (requires ngx_http_headers_module)
    add_header Strict-Transport-Security "max-age=63072000" always;

    add_header X-Robots-Tag "none" always;

    location / {
        proxy_set_header Host 'links.duckduckgo.com';
        proxy_pass https://links.duckduckgo.com;
        proxy_ssl_name links.duckduckgo.com;
        proxy_ssl_server_name on;

        proxy_set_header Origin "";
        proxy_set_header Referer "";

        # Optional cache directives removed (were commented out)
    }
}

# Tracking host (maps improving.duckduckgo.com)
server {
    listen 443 ssl;

    server_name improving.example.com;
    root /dev/null;
    resolver 9.9.9.9 1.1.1.1 [2620:fe::fe] [2606:4700:4700::1111];

    # SSL certificates for improving host
    ssl_certificate /root/.acme.sh/improving.example.com_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/improving.example.com_ecc/improving.example.com.key;

    ssl_session_cache shared:MozSSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    add_header Strict-Transport-Security "max-age=63072000" always;

    add_header X-Robots-Tag "none" always;

    location / {
        return 200;
    }
}
