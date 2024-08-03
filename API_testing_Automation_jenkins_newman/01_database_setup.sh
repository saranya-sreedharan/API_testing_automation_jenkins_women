#!/bin/bash

# Colors for formatting
RED='\033[0;31m'    # Red colored text
GREEN='\033[0;32m'  # Green colored text
YELLOW='\033[1;33m' # Yellow colored text
NC='\033[0m'        # Normal text

# Function to display error message and exit
display_error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Function to display success message
display_success() {
    echo -e "${GREEN}$1${NC}"
}

echo -e "${YELLOW}Please provide the necessary details to set up your PostgreSQL database.${NC}"

# Prompt user for database name and password
read -p "Enter the database name: " db_name
read -p "Enter the databse container name: " container_name
read -sp "Enter the database password: " db_password
echo -e "${YELLOW}..default username will be postgres for postgres database....${NC}"

# Create a PostgreSQL container with the provided database name and password
sudo docker run --name $db_name -p 5432:5432 -e POSTGRES_PASSWORD=$db_password -d postgres || display_error "Failed to create Docker container."

# Wait for the PostgreSQL container to start
sleep 5

# Enter the PostgreSQL container and run psql as postgres user
sudo docker exec -it $db_name psql -U postgres -c "SELECT version();" || display_error "Failed to execute psql command."

# Create a database with the provided name
sudo docker exec -it $db_name psql -U postgres -c "CREATE DATABASE $db_name;" || display_error "Failed to create database $db_name."

# Create a table called reports in the specified database

sudo docker exec -it $db_name psql -U postgres -d $db_name -c "CREATE TABLE reports (name VARCHAR(255), content TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);" || display_error "Failed to create table in database $db_name."

# Show the path of the PostgreSQL configuration file
config_file=$(sudo docker exec $db_name psql -U postgres -c "SHOW config_file;" | grep -oE "/.*/postgresql.conf") || display_error "Failed to get PostgreSQL config file path."

# Update PostgreSQL configuration file to set port to 5432
sudo docker exec $db_name sed -i '/^#?port/s/^#//g' "$config_file"
sudo docker exec $db_name sed -i '/^#?port/s/5433/5432/g' "$config_file"

# Show the path of the pg_hba.conf file
pg_hba_conf=$(sudo docker exec $db_name psql -U postgres -c "SHOW hba_file;" | grep -oE "/.*/pg_hba.conf") || display_error "Failed to get pg_hba.conf file path."

# Update pg_hba.conf to allow connections from any address
sudo docker exec $db_name sed -i 's/^host.*127.0.0.1\/32.*trust/host all all 0.0.0.0\/0 trust/g' "$pg_hba_conf"

# Restart the PostgreSQL container to apply changes
sudo docker restart $db_name || display_error "Failed to restart Docker container."

display_success "PostgreSQL setup completed successfully."

# Exporter setup
# Check docker-compose version
docker-compose --version || display_error "docker-compose is not installed."

# Set up the PostgreSQL exporter
exporter_dir="/opt/postgres_exporter"
sudo mkdir -p $exporter_dir
cd $exporter_dir

# Prompt for the database IP address
read -p "Enter the IP address of the database: " db_ip

# Create the environment file for the exporter
echo "DATA_SOURCE_NAME=\"postgresql://postgres:$db_password@$db_ip:5432/postgres?sslmode=disable\"" | sudo tee postgres_exporter.env

# Create the docker-compose file for the exporter
sudo tee docker-compose.yml > /dev/null <<EOF
version: '3.7'

services:
  postgres_exporter:
    image: wrouesnel/postgres_exporter
    env_file:
      - ./postgres_exporter.env
    network_mode: host
    ports:
      - "9187:9187"
    restart: always
EOF

# Start the PostgreSQL exporter
sudo docker-compose up -d || display_error "Failed to start PostgreSQL exporter."

sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

sudo apt update
sudo apt install postgresql-client-14  -y|| display_error "Failed install postgre_client."

display_success "PostgreSQL exporter setup completed successfully."
