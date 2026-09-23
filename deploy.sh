#!/usr/bin/env bash
# 开源软库 一键部署脚本（Ubuntu + Nginx）
# 用法：bash deploy.sh [网站压缩包路径，默认 ~/softbank-site.tar.gz]
set -euo pipefail

DOMAINS="softbank.org.cn www.softbank.org.cn"
WEBROOT=/var/www/softbank
PKG="${1:-$HOME/softbank-site.tar.gz}"
CONF=/etc/nginx/sites-available/softbank

[ -f "$PKG" ] || { echo "找不到网站压缩包：$PKG"; exit 1; }

echo "==> 1/5 安装 Nginx"
if ! command -v nginx >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y nginx
fi

echo "==> 2/5 解压网站文件到 $WEBROOT"
TMP=$(mktemp -d)
tar -xzf "$PKG" -C "$TMP"
[ -f "$TMP/index.html" ] || { echo "压缩包里没有 index.html，请检查文件"; exit 1; }
sudo mkdir -p "$WEBROOT"
if [ -f "$WEBROOT/index.html" ]; then
  BAK="$WEBROOT.bak.$(date +%Y%m%d%H%M%S)"
  sudo cp -a "$WEBROOT" "$BAK"
  echo "    旧版本已备份到 $BAK"
fi
sudo rsync -a --delete "$TMP"/ "$WEBROOT"/ 2>/dev/null || { sudo rm -rf "${WEBROOT:?}"/*; sudo cp -a "$TMP"/. "$WEBROOT"/; }
sudo chown -R www-data:www-data "$WEBROOT"
rm -rf "$TMP"

echo "==> 3/5 写入 Nginx 配置"
sudo tee "$CONF" >/dev/null <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAINS;

    root $WEBROOT;
    index index.html;
    charset utf-8;

    gzip on;
    gzip_types text/html text/css application/javascript image/svg+xml;

    location / {
        try_files \$uri \$uri/ /index.html;
        add_header Cache-Control "no-cache";
    }

    location ~* ^/(icons|logo)/ {
        expires 30d;
        add_header Cache-Control "public";
    }
}
NGINX
sudo ln -sf "$CONF" /etc/nginx/sites-enabled/softbank
sudo rm -f /etc/nginx/sites-enabled/default

echo "==> 4/5 检查并重载 Nginx"
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow 'Nginx Full' >/dev/null && echo "    已在 ufw 防火墙放行 80/443"
fi

echo "==> 5/5 本机自检"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: www.softbank.org.cn" http://127.0.0.1/)
echo "    本机访问状态码：$CODE（200 表示网站已在服务器上跑起来）"

cat <<TIP

部署完成。接下来：
  1. 在腾讯云控制台的「安全组」里确认已放行 TCP 80 和 443 入站。
  2. 域名需要先完成 ICP 备案并接入腾讯云，否则用域名访问会被拦截。
  3. 备案通过后，可以用下面的命令申请免费 HTTPS 证书：
       sudo apt-get install -y certbot python3-certbot-nginx
       sudo certbot --nginx -d softbank.org.cn -d www.softbank.org.cn
TIP
