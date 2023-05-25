#!/bin/bash 

# 1) Specify Errors.
function check_error(){
	if [ $? -ne 0 ]; then
		echo "$1"
		exit 1
	fi
}


# 2) Node Installation. 
function node_installation(){
	curl -fsSL https://deb.nodesource.com/setup_14.x|sudo -E bash
	sudo apt-get install -y nodejs
	check_error "Problem with node js installion"
}

# 3) Changing to static ip.
function static_ip(){
	sudo tee /etc/netplan/50_new_configs.yaml << EOF
network:
 version: 2
 renderer: NetworkManager
 ethernets:
   enp0s8:
     dhcp4: no
     addresses: [192.168.1.15/24]
     gateway4: 192.168.1.1
     nameservers:
         addresses: [8.8.8.8,8.8.8.4]
EOF

	check_error "IP Configuration failed."	
	sudo netplan apply	
	IP_ADDRESS=$(ip addr show enp0s8 | grep  -Eo 'inet ([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9].*)')
}

# 4) Add node user & postgress configuration
function postgress_installation(){
	sudo adduser node --disabled-password --gecos "test_user"
	sudo apt-get install postgresql postgresql-contrib
	sudo systemctl start postgresql
	sudo systemctl enable postgresql
	sudo -u postgres psql -c "CREATE DATABASE node;"
	sudo -u postgres psql -c "CREATE USER node WITH PASSWORD 'node';"
	sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE node TO node;"
	check_error "Postgress Problem."
}

# 5) UI
function ui_conf(){
	cd ui
	npm ci
	npm audit fix
	npm run test a &  
	npm run build  
	check_error "Problem with UI."
}

# 6) API
function api_conf(){
	cd ../api/
	npm ci
	npm install webpack webpack-cli
	cp webpack.config.js webpack.config.js.bak
	check_file=$(sed -n "/(environment === 'demo')/p" webpack.config.js)
	check_file_len=${#check_file}
	if [ $check_file_len -eq '0' ]; then
		echo 'file has no demo'
		sed -i "s/module/else if (environment === 'demo') {\n  console.log('this is demo env')\n  ENVIRONMENT_VARIABLES = {\n    'process.env.HOST': JSON.stringify('$IP_ADDRESS'),\n    'process.env.USER': JSON.stringify('node'),\n    'process.env.DB': JSON.stringify('node'),\n    'process.env.DIALECT': JSON.stringify('postgres'),\n    'process.env.PORT': JSON.stringify('3500'),\n    'process.env.PG_CONNECTION_STR': JSON.stringify('postgres:\/\/node:node@$IP_ADDRESS:5432\/node')\n  };\n}\n\n&/" webpack.config.js
	fi

	ENVIRONMENT=demo npm run build
	check_error "Problem with API."

}

# 7) Deploy and run.
function deploy_conf(){
	cd ..
	cp api/dist/* .
	cp api/swagger.css .
	npm install
	node api.bundle.js
}

node_installation
static_ip
postgress_installation
ui_conf
api_conf
deploy_conf
