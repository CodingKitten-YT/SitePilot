#!/bin/bash

# Update and install necessary packages
sudo apt update
sudo apt install nginx python3 python3-venv python3-pip apache2-utils nodejs npm git -y

# Create directory structure
sudo mkdir -p /var/www/sites
sudo mkdir -p /etc/nginx/sites-available
sudo mkdir -p /etc/nginx/sites-enabled

# Adjust Nginx configuration
sudo sed -i '/http {/a \    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf

# Create password file for HTTP Basic Authentication
sudo htpasswd -c /etc/nginx/.htpasswd admin

# Setup Flask application
mkdir -p ~/webservemanager
cd ~/webservemanager
python3 -m venv venv
source venv/bin/activate
pip install flask

# Create the Flask app
cat <<EOF > app.py
from flask import Flask, request, render_template_string
import os
import subprocess

app = Flask(__name__)

@app.route('/')
def index():
    return render_template_string('''
    <h2>WebServeManager</h2>
    <h3>Add New Site</h3>
    <form action="/add" method="post">
        Server Name: <input type="text" name="servername"><br>
        <input type="submit" value="Add Site">
    </form>
    <h3>Manage Files</h3>
    <a href="http://<your-vps-ip>:8080">Open File Manager</a>
    ''')

@app.route('/add', methods=['POST'])
def add_site():
    server_name = request.form['servername']
    if not server_name:
        return "Server name is required.", 400

    root_dir = f"/var/www/sites/{server_name}"
    config_file = f"/etc/nginx/sites-available/{server_name}"

    os.makedirs(root_dir, exist_ok=True)
    with open(os.path.join(root_dir, 'index.html'), 'w') as f:
        f.write(f"<html><head><title>Welcome to {server_name}!</title></head><body><h1>Success! The {server_name} server block is working!</h1></body></html>")

    config_content = f"""
server {{
    listen 80;
    server_name {server_name};
    root {root_dir};
    index index.html;

    location / {{
        try_files \$uri \$uri/ =404;
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }}
}}
"""
    with open(config_file, 'w') as f:
        f.write(config_content)

    os.symlink(config_file, f"/etc/nginx/sites-enabled/{server_name}")
    
    subprocess.run(['sudo', 'nginx', '-t'])
    subprocess.run(['sudo', 'systemctl', 'reload', 'nginx'])

    return f"Site {server_name} has been created and enabled."

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
EOF

# Create a systemd service for the Flask app
sudo tee /etc/systemd/system/webservemanager.service > /dev/null <<EOF
[Unit]
Description=WebServeManager
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/webservemanager
Environment="PATH=$HOME/webservemanager/venv/bin"
ExecStart=$HOME/webservemanager/venv/bin/python $HOME/webservemanager/app.py

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the Flask app service
sudo systemctl enable webservemanager
sudo systemctl start webservemanager

# Clone and set up File Manager
cd ~
git clone https://github.com/filebrowser/filebrowser.git
cd filebrowser
npm install
npm run build

# Create a File Manager configuration file
cat <<EOF > filemanager-config.json
{
  "port": 8080,
  "address": "0.0.0.0",
  "database": "/var/www/sites/filemanager.db",
  "root": "/var/www/sites"
}
EOF

# Create a systemd service for File Manager
sudo tee /etc/systemd/system/filemanager.service > /dev/null <<EOF
[Unit]
Description=File Manager
After=network.target

[Service]
ExecStart=/usr/bin/npm start --prefix /home/$USER/filebrowser
WorkingDirectory=/home/$USER/filebrowser
Restart=always
User=nobody
Group=nogroup
Environment=PATH=/usr/bin:/usr/local/bin
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the File Manager service
sudo systemctl enable filemanager
sudo systemctl start filemanager

# Reload Nginx
sudo systemctl reload nginx

echo "Installation complete. Visit http://<your-vps-ip>:5000 to manage your Nginx sites and http://<your-vps-ip>:8080 to manage files."
