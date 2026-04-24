# NginxReverseProxyDuckduckgo

## Quick Deploy for example.com (Debian 12)

1. Install nginx (with sub_filter module):
   ```bash
   sudo apt update
   sudo apt install -y nginx-extras
   ```

2. Obtain SSL certificate (recommended: acme.sh):
   ```bash
   curl https://get.acme.sh | sh
   sudo systemctl stop nginx
   ~/.acme.sh/acme.sh --issue -d example.com --standalone --keylength ec-256
   ~/.acme.sh/acme.sh --installcert -d example.com \
     --ecc \
     --fullchain-file /root/.acme.sh/example.com_ecc/fullchain.cer \
     --key-file /root/.acme.sh/example.com_ecc/example.com.key
   sudo systemctl start nginx
   ```

3. Upload configuration file:
   ```bash
   sudo cp example.com /etc/nginx/sites-available/
   sudo ln -s /etc/nginx/sites-available/example.com /etc/nginx/sites-enabled/
   ```

4. Restart nginx:
   ```bash
   sudo nginx -t
   sudo systemctl restart nginx
   ```

5. Verify in browser:
   ```
   https://example.com
   ```

---

## Quick Deploy for search.example.com (Debian 12)

1. Install nginx (with sub_filter module):
   ```bash
   sudo apt update
   sudo apt install -y nginx-extras
   ```

2. Obtain SSL certificate (recommended: acme.sh):
   ```bash
   curl https://get.acme.sh | sh
   sudo systemctl stop nginx
   ~/.acme.sh/acme.sh --issue -d search.example.com --standalone --keylength ec-256
   ~/.acme.sh/acme.sh --installcert -d search.example.com \
     --ecc \
     --fullchain-file /root/.acme.sh/search.example.com_ecc/fullchain.cer \
     --key-file /root/.acme.sh/search.example.com_ecc/search.example.com.key
   sudo systemctl start nginx
   ```

3. Upload configuration file:
   ```bash
   sudo cp search.example.com /etc/nginx/sites-available/
   sudo ln -s /etc/nginx/sites-available/search.example.com /etc/nginx/sites-enabled/
   ```

4. Restart nginx:
   ```bash
   sudo nginx -t
   sudo systemctl restart nginx
   ```

5. Verify in browser:
   ```
   https://search.example.com/?q=1
   ```

---

> **Note:** For root domain reverse proxy, you can directly open `https://example.com` in your browser to search.  
> For subdomain reverse proxy, you must access `https://search.example.com/?q=1` to search.  
> Choose the configuration file that best suits your needs.

> Deployment is complete after these steps.

