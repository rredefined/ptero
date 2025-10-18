# Ubuntu/Debian
curl -sL https://deb.nodesource.com/setup_22.x | sudo -E bash - 
sudo apt install -y nodejs

npm i -g yarn # Install Yarn

cd /var/www/pterodactyl
yarn # Installs panel build dependencies

cd /var/www/pterodactyl
export NODE_OPTIONS=--openssl-legacy-provider # for NodeJS v17+
yarn build:production # Build panel

yarn remove react-icons
# OR if you use npm:
# npm uninstall react-icons
yarn add react-icons@5.4.0
# OR if you use npm:
# npm install react-icons@5.4.0
