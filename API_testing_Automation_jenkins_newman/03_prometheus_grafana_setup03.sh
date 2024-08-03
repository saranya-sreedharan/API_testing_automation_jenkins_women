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

echo -e "${YELLOW}Setting up Prometheus and Grafana...${NC}"

# Prompt user for target IP address
read -p "Enter the target IP address for the PostgreSQL exporter: " target_ip

# Create Docker volumes for Prometheus and Grafana
sudo docker volume create prometheus_data || display_error "Failed to create Docker volume prometheus_data."
sudo docker volume create grafana_data || display_error "Failed to create Docker volume grafana_data."

# Create Prometheus configuration directory
config_dir="/path/to/prometheus/config"
sudo mkdir -p $config_dir || display_error "Failed to create Prometheus configuration directory."

# Create Prometheus configuration file
prometheus_config="$config_dir/prometheus.yml"
sudo tee $prometheus_config > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'postgres_exporter'
    static_configs:
      - targets: ['$target_ip:9187']
EOF

# Create Docker Compose file
docker_compose_file="/home/ubuntu/docker-compose.yml"
sudo tee $docker_compose_file > /dev/null <<EOF
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - prometheus_data:/etc/prometheus
      - $config_dir/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
    restart: always

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    restart: always

volumes:
  prometheus_data:
  grafana_data:
EOF

# Start Prometheus and Grafana services using Docker Compose
sudo docker-compose -f $docker_compose_file up -d || display_error "Failed to start Prometheus and Grafana using Docker Compose."

display_success "Prometheus and Grafana setup completed successfully.Prometheus is running in port 9090 and Grafana is running in port 3000 "
