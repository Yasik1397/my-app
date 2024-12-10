#!/bin/bash

# Update and install necessary packages
sudo apt update -y
sudo apt install nginx npm python3-venv acl libxml2-dev libxslt1-dev libpq-dev python3-dev -y

# Check the status of nginx
sudo systemctl status nginx

# Set permissions for /var/www
sudo chown -R ubuntu:ubuntu /var/www/
sudo find /var/www/ -type d -exec chmod 775 {} \;
sudo find /var/www/ -type f -exec chmod 664 {} \;
sudo setfacl -R -m d:u:ubuntu:rwx /var/www/
sudo setfacl -R -m d:g:ubuntu:rwx /var/www/
sudo setfacl -R -m d:o:rx /var/www/
ls -l /var/www/

# Install PM2
sudo npm install -g pm2
sudo ln -s /usr/bin/nodejs /usr/bin/node

# Create PM2 ecosystem file
cd /var/www/
sudo pm2 init simple

# Install and configure PostgreSQL
sudo apt install gnupg2 wget nano
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
sudo apt update
sudo apt install postgresql-16 postgresql-contrib-16
sudo systemctl start postgresql
sudo systemctl enable postgresql
# sudo apt install postgresql postgresql-contrib -y
# sudo systemctl start postgresql.service
sudo -i -u postgres psql -c "CREATE DATABASE \"staging_leadq_db\";"
sudo -i -u postgres psql -c "\password"
sudo systemctl restart postgresql

# Configure PostgreSQL for remote access
sudo bash -c 'echo "listen_addresses = '\''*'\''" >> /etc/postgresql/16/main/postgresql.conf'
sudo bash -c 'echo "host    all             all             0.0.0.0/0               md5" >> /etc/postgresql/16/main/pg_hba.conf'
sudo systemctl daemon-reload
sudo systemctl restart postgresql

# Setup working directory and clone repository
sudo mkdir /var/www/leadq
cd /var/www/leadq/
sudo git clone https://github.com/LeadQ-Product/leadq-admin-service.git
cd leadq-admin-service
sudo git checkout staging

# Create .env file
sudo bash -c 'cat <<EOF > /var/www/leadq/leadq-admin-service/app/.env
Server:

# ADMIN AUTH DETAILS

ALGORITHM = "HS256"
ADMIN_REFRESH_SECRET = "admin_refresh"
ADMIN_ACCESS_SECRET = "admin"

# Postgres credential

SQLALCHEMY_DATABASE_URL_APP = "postgresql://postgres:1234@localhost/staging_leadq_db"
SQLALCHEMY_DATABASE_URL = "postgresql://postgres:1234@localhost/{}_leadq_db"


ORG_LIST = "staging"


DEVELOPMENT_DOMAIN=staging
EOF'

# Setup Python environment and install requirements
sudo python3 -m venv /var/www/leadq/leadq-admin-service/env
sudo chmod +x /var/www/leadq/leadq-admin-service/env/bin/activate
sudo chmod -R u+w /var/www/leadq/leadq-admin-service/env
source /var/www/leadq/leadq-admin-service/env/bin/activate
cd /var/www/leadq/leadq-admin-service
pip install -r requirements.txt

# Run the application to check if it is working
python3 app/main.py

# If required, install missing packages
pip install uvicorn sqlalchemy fastapi python-decouple psycopg2-binary pytz passlib openpyxl python-dateutil numpy pandas schedule PyJWT
pip freeze > requirements.txt

# Create PM2 configuration file
sudo bash -c 'cat <<EOF > /var/www/ecosystem.config.js
module.exports = {
  apps : [
    {
      name   : "leadq-admin-service",
      script : "/var/www/leadq/leadq-admin-service/env/bin/activate",
      cwd:"/var/www/leadq/leadq-admin-service",
      interpreter:"/var/www/leadq/leadq-admin-service/env/bin/python3",
      interpreter_args:"app/main.py",
      "log_date_format"  : "YYYY-MM-DD HH:mm Z"
    }
  ]
}
EOF'

# Setup Nginx configuration
sudo rm /etc/nginx/sites-available/default
sudo rm /etc/nginx/sites-enabled/default
sudo bash -c 'cat <<EOF > /etc/nginx/sites-available/leadq
server {
  server_name _;
  # server_name staging-api.leadsynq.com;
  client_max_body_size 20M;
  location /api/leadq-admin {
        proxy_pass http://127.0.0.1:8000;
  }  
}
EOF'
sudo ln -s /etc/nginx/sites-available/leadq /etc/nginx/sites-enabled/leadq
sudo nginx -t
sudo systemctl restart nginx

# Install SSL certificate
sudo apt install snapd -y
sudo snap install core; sudo snap refresh core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
# sudo certbot --nginx

# # Start PM2 server
# pm2 start /var/www/ecosystem.config.js
# pm2 startup
# sudo env PATH=$PATH:/usr/bin /usr/local/lib/node_modules/pm2/bin/pm2 startup systemd -u ubuntu --hp /home/ubuntu
# pm2 save

echo "Setup complete!"
