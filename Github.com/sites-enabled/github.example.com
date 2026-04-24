server {
    listen 80;
    server_name github.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name github.example.com;

    ssl_certificate /root/.acme.sh/github.example.com_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/github.example.com_ecc/github.example.com.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Block web crawlers
    if ($http_user_agent ~* "qihoobot|Baiduspider|Googlebot|Googlebot-Mobile|Googlebot-Image|Mediapartners-Google|Adsbot-Google|Feedfetcher-Google|Yahoo! Slurp|Yahoo! Slurp China|YoudaoBot|Sosospider|Sogou spider|Sogou web spider|MSNBot|ia_archiver|Tomato Bot") {
        return 403;
    }

    location / {
        proxy_pass https://github.com;
        proxy_set_header Host github.com;
        proxy_set_header Referer "https://github.com";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_ssl_server_name on;
        proxy_ssl_name github.com;
        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
        proxy_ssl_verify_depth 2;

        proxy_connect_timeout 60;
        proxy_read_timeout 60;
        proxy_send_timeout 60;

        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
        proxy_temp_file_write_size 256k;

        client_max_body_size 1000m;

        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods GET,POST,OPTIONS always;
        add_header Access-Control-Allow-Headers Authorization,Content-Type always;
        add_header Access-Control-Max-Age 1728000 always;
        add_header X-Proxy-Debug "Proxied by github.example.com" always;

        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin * always;
            add_header Access-Control-Allow-Methods GET,POST,OPTIONS always;
            add_header Access-Control-Allow-Headers Authorization,Content-Type always;
            add_header Access-Control-Max-Age 1728000 always;
            add_header Content-Length 0;
            add_header Content-Type text/plain;
            add_header Cache-Control "public, max-age=86400";
            return 204;
        }

        sub_filter_once off;
        sub_filter "https://github.com" "https://github.example.com";
        sub_filter "github.com" "github.example.com";
        sub_filter "href=['\"](https?://github.com[^'\"]+)['\"]" "href='https://github.example.com$2'";
        sub_filter "src=['\"](https?://github.com[^'\"]+)['\"]" "src='https://github.example.com$2'";

        # Special handling for release download links:
        # GitHub release downloads redirect to release-assets.githubusercontent.com.
        # Replace that domain in redirected URLs with our proxy domain.
        # Note: need to capture full signed URLs and replace only the domain part.
        sub_filter "https://release-assets.githubusercontent.com" "https://github.example.com/github-release-assets";

        # Disable compression so sub_filter can operate on responses
        proxy_set_header Accept-Encoding "";
        proxy_set_header Cookie $http_cookie;
        proxy_hide_header Content-Security-Policy;
        add_header Content-Security-Policy "default-src * 'unsafe-inline' 'unsafe-eval';";

        proxy_redirect https://github.com/ https://github.example.com/;
        # Because redirects to release-assets.githubusercontent.com are full URLs,
        # also handle redirects from github.com to githubusercontent.com.
        proxy_redirect https://release-assets.githubusercontent.com/ https://github.example.com/github-release-assets/;
        proxy_intercept_errors on;
        error_page 301 302 = @handle_redirect;
    }

    location /api/ {
        proxy_pass https://api.github.com/;
        proxy_set_header Host api.github.com;
        proxy_set_header Referer "https://github.com";
        proxy_ssl_server_name on;
        proxy_ssl_name api.github.com;
        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;

        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods GET,POST,OPTIONS always;
        add_header Access-Control-Allow-Headers Authorization,Content-Type always;
        add_header Access-Control-Max-Age 1728000 always;

        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin * always;
            add_header Access-Control-Allow-Methods GET,POST,OPTIONS always;
            add_header Access-Control-Allow-Headers Authorization,Content-Type always;
            add_header Access-Control-Max-Age 1728000 always;
            add_header Content-Length 0;
            add_header Content-Type text/plain;
            return 204;
        }

        sub_filter "https://github.com" "https://github.example.com";
        sub_filter_once off;
    }

    # Proxy release-assets.githubusercontent.com
    # Rewrite URL by removing /github-release-assets/ prefix to restore original path
    location /github-release-assets/ {
        rewrite ^/github-release-assets/(.*)$ /$1 break;

        # Note: release-assets.githubusercontent.com backend may not be a single hostname.
        # For robustness, proxy directly to release-assets.githubusercontent.com.
        proxy_pass https://release-assets.githubusercontent.com/;
        proxy_set_header Host release-assets.githubusercontent.com;
        proxy_set_header Referer "https://github.example.com";
        proxy_ssl_server_name on;
        proxy_ssl_name release-assets.githubusercontent.com;
        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;

        proxy_connect_timeout 120;
        proxy_read_timeout 300;
        proxy_send_timeout 120;

        proxy_buffer_size 128k;
        proxy_buffers 8 256k;
        proxy_busy_buffers_size 512k;
        proxy_temp_file_write_size 512k;

        add_header Access-Control-Allow-Origin * always;
        add_header Cache-Control "public, max-age=86400";
    }

    # Keep existing /github-production-release-asset/ proxy if still needed.
    # For releases/download, /github-release-assets/ should take precedence.
    location /github-production-release-asset/ {
        proxy_pass https://github-production-release-asset-2e65be.s3.amazonaws.com;
        proxy_set_header Host github-production-release-asset-2e65be.s3.amazonaws.com;
        proxy_ssl_server_name on;

        add_header Access-Control-Allow-Origin * always;
        add_header Cache-Control "public, max-age=86400";
    }

    location /github-release/ {
        rewrite ^/github-release/(.*)$ /$1 break;
        proxy_pass https://github.com/;
        proxy_set_header Host github.com;
        proxy_ssl_server_name on;

        proxy_set_header User-Agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.212 Safari/537.36";

        proxy_intercept_errors on;
        error_page 301 302 = @handle_redirect;

        add_header Access-Control-Allow-Origin * always;
    }

    location @handle_redirect {
        internal;
        resolver 8.8.8.8; # or your own DNS resolver
        set $redirect_url $upstream_http_location;

        # Capture redirects to release-assets.githubusercontent.com
        if ($redirect_url ~* "^https?://release-assets.githubusercontent.com(/.*)") {
            set $redirect_url https://github.example.com/github-release-assets$1;
            return 301 $redirect_url;
        }
        # Capture redirects to objects.githubusercontent.com
        if ($redirect_url ~* "^https?://objects.githubusercontent.com(/.*)") {
            set $redirect_url https://github.example.com/github-objects$1;
            return 301 $redirect_url;
        }
        # Add more github.com redirect handling as needed
        if ($redirect_url ~* "^https?://github.com(/.*)") {
            set $redirect_url https://github.example.com$1;
            return 301 $redirect_url;
        }
        # For other redirects, return the original redirect
        return 301 $redirect_url;
    }

    location /github-objects/ {
        rewrite ^/github-objects/(.*)$ /$1 break;
        proxy_pass https://objects.githubusercontent.com/;
        proxy_set_header Host objects.githubusercontent.com;
        proxy_ssl_server_name on;

        add_header Access-Control-Allow-Origin * always;
        add_header Cache-Control "public, max-age=86400";
    }
}
