# NginxReverseProxyGithub

## Quick Deploy for github.example.com (Debian 12)

1. Install nginx (with sub_filter module):
   ```bash
   sudo apt update
   sudo apt install -y nginx-extras
   ```

2. Obtain SSL certificate (recommended: acme.sh):
   ```bash
   curl https://get.acme.sh | sh
   sudo systemctl stop nginx
   ~/.acme.sh/acme.sh --issue -d github.example.com --standalone --keylength ec-256
   ~/.acme.sh/acme.sh --installcert -d github.example.com \
     --ecc \
     --fullchain-file /root/.acme.sh/github.example.com_ecc/fullchain.cer \
     --key-file /root/.acme.sh/github.example.com_ecc/github.example.com.key
   sudo systemctl start nginx
   ```

3. Upload the config file:
   ```bash
   sudo cp github.example.com /etc/nginx/sites-available/
   sudo ln -s /etc/nginx/sites-available/github.example.com /etc/nginx/sites-enabled/
   ```

4. Restart nginx:
   ```bash
   sudo nginx -t
   sudo systemctl restart nginx
   ```

5. Verify in browser:
   ```
   https://github.example.com
   ```

> Deployment is complete after these steps.
