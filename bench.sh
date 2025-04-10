#!/bin/bash

LOG_DIR="/var/log/httpd"
WEB_DIR="/srv/http"
ERROR_FILE="$WEB_DIR/error500.php"
FORBIDDEN_DIR="$WEB_DIR/forbidden"
BACKUP_CONF="/etc/httpd/conf/httpd.conf.bak"
APACHE_CONF="/etc/httpd/conf/httpd.conf"

# Vérification des droits
if [[ $EUID -ne 0 ]]; then
   echo "Ce script doit être exécuté en tant que root." 
   exit 1
fi

# Test Erreur 404
echo "Test Erreur 404..."
curl -i http://localhost/nonexistent-page
sleep 2

# Test Erreur 403
echo "Test Erreur 403..."
sudo mkdir -p "$FORBIDDEN_DIR"
echo "Accès interdit" | sudo tee "$FORBIDDEN_DIR/index.html" > /dev/null
sudo chmod 000 "$FORBIDDEN_DIR"
curl -i http://localhost/forbidden/
sudo chmod 755 "$FORBIDDEN_DIR"  # Rétablissement des permissions
sleep 2

# Test Erreur 500
echo "Test Erreur 500..."
echo '<?php http_response_code(500); trigger_error("Erreur interne testée", E_USER_ERROR); ?>' | sudo tee "$ERROR_FILE" > /dev/null
curl -i http://localhost/error500.php
rm -f "$ERROR_FILE"
sleep 2

# Test Erreur de permission
echo "Test Erreur de permission..."
sudo chmod 000 "$WEB_DIR/index.html"
curl -i http://localhost/
sudo chmod 644 "$WEB_DIR/index.html"
sleep 2

# Test Erreur de configuration Apache
echo "Test Erreur de configuration Apache..."
cp "$APACHE_CONF" "$BACKUP_CONF"
echo 'InvalidDirective On' | sudo tee -a "$APACHE_CONF" > /dev/null
if ! sudo systemctl restart httpd; then
    echo "Erreur détectée dans la configuration. Vérifie les logs."
    sudo journalctl -xe | grep httpd
fi
cp "$BACKUP_CONF" "$APACHE_CONF"
sudo systemctl restart httpd
rm -f "$BACKUP_CONF"

# Affichage des logs récents sans suppression des anciens
echo "Logs récents :"
sudo tail -n 20 "$LOG_DIR/error_log"

# Affichage des logs d'accès
echo "Logs d'accès récents :"
sudo tail -n 20 "$LOG_DIR/access_log"

echo "Tests terminés."