#!/bin/bash
set -e

echo "=============================="
echo " SonarQube 25.x Installer"
echo "=============================="

SONAR_VERSION="25.11.0.114957"
SONAR_ZIP="sonarqube-$SONAR_VERSION.zip"
SONAR_URL="https://binaries.sonarsource.com/Distribution/sonarqube/$SONAR_ZIP"
SONAR_DIR="/opt/sonarqube"

DB_NAME="sonarqube"
DB_USER="sonaruser"
DB_PASS="StrongPassword123!"   # <-- Change if you want


echo "[1/12] Updating system..."
apt update && apt upgrade -y

echo "[2/12] Installing required packages..."
apt install -y wget unzip curl git apt-transport-https

echo "[3/12] Installing Java 17..."
apt install -y openjdk-17-jdk
echo "Java installed:"
java -version


echo "[4/12] Installing PostgreSQL..."
apt install -y postgresql postgresql-contrib
systemctl enable --now postgresql


echo "[5/12] Creating SonarQube database and user..."
sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS $DB_NAME;
DROP ROLE IF EXISTS $DB_USER;
CREATE ROLE $DB_USER WITH LOGIN ENCRYPTED PASSWORD '$DB_PASS';
CREATE DATABASE $DB_NAME OWNER $DB_USER ENCODING 'UTF8' LC_COLLATE='C.UTF-8' LC_CTYPE='C.UTF-8';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF


echo "[6/12] Setting Elasticsearch limits..."
echo "vm.max_map_count=524288" | tee -a /etc/sysctl.conf
echo "fs.file-max=65536" | tee -a /etc/sysctl.conf
sysctl -p

tee -a /etc/security/limits.conf <<EOF
sonar   -   nofile   65536
sonar   -   nproc    4096
EOF


echo "[7/12] Creating sonar user..."
groupadd -f sonar
id -u sonar >/dev/null 2>&1 || useradd -c "SonarQube User" -d /opt/sonarqube -g sonar -s /bin/bash sonar


echo "[8/12] Downloading SonarQube $SONAR_VERSION..."
cd /opt
rm -rf $SONAR_ZIP sonarqube-$SONAR_VERSION $SONAR_DIR

wget $SONAR_URL
unzip $SONAR_ZIP
mv sonarqube-$SONAR_VERSION sonarqube
chown -R sonar:sonar $SONAR_DIR


echo "[9/12] Configuring sonar.properties..."
sed -i "s|#sonar.jdbc.username=.*|sonar.jdbc.username=$DB_USER|" $SONAR_DIR/conf/sonar.properties
sed -i "s|#sonar.jdbc.password=.*|sonar.jdbc.password=$DB_PASS|" $SONAR_DIR/conf/sonar.properties
sed -i "s|#sonar.jdbc.url=jdbc:postgresql.*|sonar.jdbc.url=jdbc:postgresql://localhost:5432/$DB_NAME|" $SONAR_DIR/conf/sonar.properties
echo "sonar.web.host=0.0.0.0" >> $SONAR_DIR/conf/sonar.properties


echo "[10/12] Creating systemd service..."
tee /etc/systemd/system/sonarqube.service > /dev/null <<EOF
[Unit]
Description=SonarQube 25.x Service
After=network.target postgresql.service

[Service]
Type=forking
User=sonar
Group=sonar
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
Restart=always
LimitNOFILE=65536
LimitNPROC=4096
Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"

[Install]
WantedBy=multi-user.target
EOF


echo "[11/12] Starting SonarQube..."
systemctl daemon-reload
systemctl enable sonarqube
systemctl start sonarqube
sleep 5


echo "[12/12] Checking logs..."
tail -n 30 /opt/sonarqube/var/logs/web.log || echo "SonarQube starting, logs not ready yet."


echo "====================================================="
echo " SonarQube 25.x Installation Complete!"
echo "====================================================="
echo " URL:  http://YOUR_SERVER_IP:9000"
echo " Login: admin / admin"
echo " Database: $DB_NAME"
echo " DB User:  $DB_USER"
echo "====================================================="
