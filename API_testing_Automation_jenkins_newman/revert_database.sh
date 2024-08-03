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

# Prompt user for database name
read -p "Enter the database name to revert changes: " db_name

# Stop and remove the PostgreSQL Docker container
echo -e "${YELLOW}Stopping and removing PostgreSQL Docker container...${NC}"
sudo docker stop $db_name || display_error "Failed to stop Docker container."
sudo docker rm $db_name || display_error "Failed to remove Docker container."

# Remove the PostgreSQL exporter setup
exporter_dir="/opt/postgres_exporter"

if [ -d "$exporter_dir" ]; then
    echo -e "${YELLOW}Removing PostgreSQL exporter setup...${NC}"
    cd $exporter_dir
    sudo docker-compose down || display_error "Failed to stop PostgreSQL exporter."
    cd ~
    sudo rm -rf $exporter_dir || display_error "Failed to remove exporter directory."
else
    echo -e "${YELLOW}PostgreSQL exporter setup directory does not exist.${NC}"
fi

# Remove the PostgreSQL client
echo -e "${YELLOW}Removing PostgreSQL client...${NC}"
sudo apt remove --purge postgresql-client-14 -y || display_error "Failed to remove PostgreSQL client."

display_success "Revert completed successfully."
