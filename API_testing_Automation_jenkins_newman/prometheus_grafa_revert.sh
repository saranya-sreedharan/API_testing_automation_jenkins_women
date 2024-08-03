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

echo -e "${YELLOW}Reverting Prometheus and Grafana setup...${NC}"

# Docker Compose file path
docker_compose_file="/path/to/docker-compose.yml"

# Stop and remove Prometheus and Grafana services using Docker Compose
sudo docker-compose -f $docker_compose_file down || display_error "Failed to stop and remove Prometheus and Grafana using Docker Compose."

# Remove Docker volumes for Prometheus and Grafana
sudo docker volume rm prometheus_data || display_error "Failed to remove Docker volume prometheus_data."
sudo docker volume rm grafana_data || display_error "Failed to remove Docker volume grafana_data."

# Remove Prometheus configuration directory
config_dir="/path/to/prometheus/config"
sudo rm -rf $config_dir || display_error "Failed to remove Prometheus configuration directory."

# Remove Docker Compose file
sudo rm -f $docker_compose_file || display_error "Failed to remove Docker Compose file."

display_success "Prometheus and Grafana setup reverted successfully."
