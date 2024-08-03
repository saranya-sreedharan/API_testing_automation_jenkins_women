#!/bin/bash

# Colors for formatting
RED='\033[0;31m'    # Red colored text
GREEN='\033[0;32m'  # Green colored text
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

# Update package lists
sudo apt update || display_error "Failed to update package lists"

# Check if Docker is installed, if not install it
if ! command -v docker &> /dev/null; then
    display_success "Installing Docker..."
    sudo apt install docker.io -y || display_error "Failed to install Docker"
else
    display_success "Docker is already installed"
fi

# Create jenkins_data directory and Docker volume
read -p "Enter the absolute path to create jenkins_data directory: " jenkins_data_location
mkdir -p "$jenkins_data_location" || display_error "Failed to create jenkins_data directory"
sudo docker volume create jenkins_data || display_error "Failed to create Docker volume jenkins_data"
sudo docker volume create --driver local --opt type=none --opt device=/mnt/jenkins_data --opt o=bind jenkins_data || error_exit "Failed to create Docker volume jenkins_data."

# Set proper permissions for jenkins_data directory
sudo chown -R 1000:1000 "$jenkins_data_location" || display_error "Failed to set permissions for jenkins_data directory"

# Create Dockerfile
echo -e "
# Dockerfile
FROM jenkins/jenkins:lts

# Expose ports for Jenkins web UI and agent communication
EXPOSE 8080 50000

# Set up a volume to persist Jenkins data
VOLUME /var/jenkins_home

# Set up the default command to run Jenkins
CMD [\"java\", \"-jar\", \"/usr/share/jenkins/jenkins.war\"]" > Dockerfile || display_error "Failed to create Dockerfile"

# Build custom Jenkins image
sudo docker build -t my-custom-jenkins . || display_error "Failed to build custom Jenkins image"

# Run Jenkins container
sudo docker run -d -p 8080:8080 -p 50000:50000 -v "$jenkins_data_location:/var/jenkins_home" --name jenkins --restart always my-custom-jenkins || display_error "Failed to run Jenkins container"

# Wait for Jenkins to generate initial admin password
echo "Waiting for initial admin password..."
sleep 30

# Retrieve initial admin password
password=$(sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword) || display_error "Failed to retrieve initial admin password"

# Print initial admin password
display_success "Initial admin password: $password"

sleep 30

# Install necessary packages inside Jenkins container
sudo docker exec -u root jenkins apt-get update || display_error "Failed to update package lists inside Jenkins container"
sudo docker exec -u root jenkins apt-get install -y wget nano || display_error "Failed to install necessary packages inside Jenkins container"

# Get Jenkins container ID and IP address
CONTAINER_ID=$(sudo docker ps -aqf "name=jenkins")
CONTAINER_IP=$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_ID")

# Download Jenkins CLI JAR file
sudo docker exec -u root jenkins wget "http://$CONTAINER_IP:8080/jnlpJars/jenkins-cli.jar" || display_error "Failed to download Jenkins CLI JAR file"

# Restart Jenkins container
sudo docker restart jenkins || display_error "Failed to restart Jenkins container"

display_success "Initial admin password: $password"

echo -e "setup username and password for jenkins"

sleep 120

read -p "Enter Jenkins admin username: " username
read -sp "Enter Jenkins admin password: " password

sudo docker exec -u root jenkins java -jar jenkins-cli.jar -auth $username:$password -s http://$CONTAINER_IP:8080/ install-plugin gitlab-plugin || error_exit "Failed to install GitLab plugin."

sudo docker exec -u root jenkins java -jar jenkins-cli.jar -auth $username:$password -s http://$CONTAINER_IP:8080/ install-plugin htmlpublisher || error_exit "Failed to install HTML publisher."
sudo docker exec -u root jenkins java -jar jenkins-cli.jar -auth $username:$password -s http://$CONTAINER_IP:8080/ install-plugin database-postgresql || error_exit "Failed to install PostgreSQL JDBC driver plugin."


sudo docker exec -u root jenkins curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
sudo docker exec -u root jenkins apt-get install -y nodejs
sudo docker exec -u root jenkins apt-get install -y npm
sudo docker exec -u root jenkins apt-get install -y libpostgresql-jdbc-java
sudo docker exec -u root jenkins cp /usr/share/java/postgresql-42.5.4.jar /var/jenkins_home//war/WEB-INF/lib
sudo docker exec -u root jenkins chmod 755 /var/jenkins_home//war/WEB-INF/lib 



sudo docker exec -u root jenkins npm -v
sudo docker exec -u root jenkins node -v

sudo docker exec -u root jenkins npm install -g newman
sudo docker exec -u root jenkins newman -v

sudo docker restart jenkins || display_error "Failed to restart Jenkins container"

echo -e "Create gitlab login credentails and token credential in jenkins"

sleep 120

# Prompt user for GitLab credentials
read -p "Enter your GitLab username: " gitlab_username
read -sp "Enter your GitLab password or personal access token: " gitlab_password
echo ""

# Define XML for GitLab credentials
GITLAB_CREDENTIALS_XML=$(cat <<EOF
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>gitlab-login</id>
  <description>GitLab Login</description>
  <username>$gitlab_username</username>
  <password>$gitlab_password</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
EOF
)

# Create GitLab credentials XML file
echo "$GITLAB_CREDENTIALS_XML" > gitlab-credentials.xml

# Retry mechanism
MAX_RETRIES=5
RETRY_DELAY=10

retry_count=0
success=false

while [ $retry_count -lt $MAX_RETRIES ]; do
  echo "Attempt $(($retry_count + 1)) to create GitLab credentials..."
  sudo docker exec -i jenkins sh -c "java -jar jenkins-cli.jar -auth $username:$password -s http://$CONTAINER_IP:8080/ create-credentials-by-xml system::system::jenkins _ < /dev/stdin" < gitlab-credentials.xml

  if [ $? -eq 0 ]; then
    success=true
    break
  else
    echo "Attempt $(($retry_count + 1)) failed. Retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
    retry_count=$(($retry_count + 1))
  fi
done

if [ "$success" = true ]; then
  echo "GitLab credentials created successfully and automation script completed."
else
  echo "Failed to create GitLab credentials after $MAX_RETRIES attempts."
fi

display_success "GitLab credentials created successfully and automation script completed."

CONTAINER_NAME="jenkins"
SCRIPT_PATH="/usr/share/jenkins/ref/init.groovy.d"
SCRIPT_NAME="custom-csp.groovy"
SCRIPT_CONTENT="System.setProperty('hudson.model.DirectoryBrowserSupport.CSP', \"\")"

# Create the script content
echo "$SCRIPT_CONTENT" > "$SCRIPT_NAME"

# Copy the script into the Jenkins container
sudo docker cp "$SCRIPT_NAME" "$CONTAINER_NAME":"$SCRIPT_PATH"/"$SCRIPT_NAME"

# Clean up: remove the local copy of the script
rm "$SCRIPT_NAME"

# Restart the Jenkins container to apply changes
sudo docker restart "$CONTAINER_NAME"

sudo docker exec -u root jenkins npm install -g newman-reporter-html
sudo docker exec -u root jenkins npm install -g newman-reporter-htmlextra

JENKINS_CONTAINER="jenkins"
JENKINS_HOME="/var/jenkins_home"
INIT_GROOVY_D="$JENKINS_HOME/init.groovy.d"
SCRIPT_NAME="approveSignatures.groovy"
SCRIPT_PATH="$INIT_GROOVY_D/$SCRIPT_NAME"

# Create the init.groovy.d directory if it doesn't exist
echo "Creating $INIT_GROOVY_D directory..."
sudo docker exec -u root $JENKINS_CONTAINER mkdir -p "$INIT_GROOVY_D"

# Create the Groovy script for approving signatures
echo "Creating the Groovy script for approving signatures..."
sudo docker exec -u root $JENKINS_CONTAINER bash -c "cat <<EOF > $SCRIPT_PATH
import jenkins.model.*
import org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval

def approvals = [
    'staticMethod groovy.sql.Sql newInstance java.lang.String java.lang.String java.lang.String java.lang.String',
    'method groovy.sql.Sql execute java.lang.String java.util.List',
    'staticMethod java.lang.Class forName java.lang.String'
]

def scriptApproval = ScriptApproval.get()
approvals.each { approval ->
    scriptApproval.approveSignature(approval)
}
EOF"

# Set permissions for the script
echo "Setting permissions for the script..."
sudo docker exec -u root $JENKINS_CONTAINER chown -R jenkins:jenkins "$INIT_GROOVY_D"
sudo docker exec -u root $JENKINS_CONTAINER chmod +x "$SCRIPT_PATH"

# Restart Jenkins to apply the changes
echo "Restarting Jenkins..."
sudo docker restart $JENKINS_CONTAINER

# Confirmation message
echo "Groovy script for script approval has been set up and Jenkins is restarting."


# Prompt user for GitLab URL and token
read -p "Enter your GitLab URL (e.g., https://gitlab.com): " gitlab_url
read -p "Enter your GitLab token: " gitlab_token
read -p "Enter your Gitlab directory URL (e.g., https://gitlab.com/saruSaranya/api-testing_project.git): " gitlabdirectory_url
read -p "Enter the ip_adress of database: " databse_ip
read -p "Enter the job_name in jenkins: " job_name
read -p "Enter the database name, where you want to store the html files: " db_name
echo -e "${YELLOW}..default username will be postgres for postgres database....${NC}"
read -p "Enter the password of your database: " db_password

# Define the job configuration XML content with dynamic URL and token
JOB_CONFIG_XML=$(cat <<EOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.42">
  <actions/>
  <description></description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <org.jenkinsci.plugins.pipeline.modeldefinition.config.FolderConfig plugin="pipeline-model-definition@1.10.2">
      <dockerLabel></dockerLabel>
      <registry plugin="docker-commons@1.17"/>
      <registryCredentialId></registryCredentialId>
    </org.jenkinsci.plugins.pipeline.modeldefinition.config.FolderConfig>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps@2.90">
    <script>
    pipeline {
    agent any
    
    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', credentialsId: 'gitlab-login', url: '$gitlabdirectory_url'
            }
        }
        
        stage('Run API Tests') {
            steps {
                script {
                    sh 'newman run /var/jenkins_home/workspace/$job_name/mmdev2api.postman_collection.json -r htmlextra'
                }
            }
        }
    }
    
    post {
        always {
            script {
                // Move HTML report to a temporary location
                sh 'mv /var/jenkins_home/workspace/$job_name/newman/*.html /tmp/'


                // Store HTML reports into PostgreSQL database
                def htmlReportsDir = "/tmp/"
                def htmlReports = sh(script: 'ls /tmp/*.html', returnStdout: true).trim().split('\\\n')
                
                htmlReports.each { reportFile ->
                    // Extract report name from file path
                    def reportName = reportFile.tokenize('/').last()
                    
                    // Read HTML report content
                    def reportContent = readFile(file: reportFile).trim()
                    
                    // Store report content into PostgreSQL database
					
                       storeReportInDatabase(reportName, reportContent)
                   
                }
            }
        }
    }
}


def storeReportInDatabase(reportName, reportContent) {
    def dbUrl = 'jdbc:postgresql://$databse_ip:5432/$db_name'
    def dbUser = 'postgres'
    def dbPassword = '$db_password'
    def driver = 'org.postgresql.Driver'

    Class.forName(driver)
    
    // Establish database connection
    def sql = groovy.sql.Sql.newInstance(dbUrl, dbUser, dbPassword, driver)
    
    // Insert report into database
    sql.execute("INSERT INTO reports (name, content) VALUES (?, ?)", [reportName, reportContent])
}

    </script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
  <!-- GitLab configuration -->
  <scm class="hudson.plugins.git.GitSCM" plugin="git@4.12.0">
    <configVersion>2</configVersion>
    <userRemoteConfigs>
      <hudson.plugins.git.UserRemoteConfig>
        <url>$gitlab_url</url> 
        <credentialsId>$gitlab_token</credentialsId> <!-- Use dynamic token here -->
      </hudson.plugins.git.UserRemoteConfig>
    </userRemoteConfigs>
  </scm>
</flow-definition>
EOF
)

# Create the job configuration XML file
echo -e "${JOB_CONFIG_XML}" | sudo tee job_config.xml > /dev/null
          
   

# Get the container ID
CONTAINER_ID=$(sudo docker ps -aqf "name=jenkins")

# Extract the IP address of the container
CONTAINER_IP=$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_ID")

# Copy job_config.xml to Jenkins container
echo -e "${YELLOW}... Copying job_config.xml to Jenkins container....${NC}"
sudo docker cp job_config.xml "$CONTAINER_ID":/var/jenkins_home/ || { echo -e "${RED}Failed to copy job_config.xml to Jenkins container.${NC}"; exit 1; }

# Restart Jenkins container
echo -e "${YELLOW}... Restarting Jenkins container....${NC}"
sudo docker restart "$CONTAINER_ID" || { echo -e "${RED}Failed to restart Jenkins container.${NC}"; exit 1; }

sleep 30

# Create job
echo -e "${YELLOW}... Creating the job....${NC}"
sudo docker exec -i "$CONTAINER_ID" sh -c "java -jar jenkins-cli.jar -auth $username:$password -s http://$CONTAINER_IP:8080/ create-job $job_name < /var/jenkins_home/job_config.xml" || { echo -e "${RED}Failed to create job.${NC}"; exit 1; }
sleep 30

# List jobs
echo -e "${YELLOW}... Listing jobs....${NC}"
sudo docker exec -i "$CONTAINER_ID" sh -c "java -jar jenkins-cli.jar -auth $username:$password -s http://$CONTAINER_IP:8080/ list-jobs" || { echo -e "${RED}Failed to list jobs.${NC}"; exit 1; }

# Build the job
echo -e "${YELLOW}... Building the job....${NC}"
sudo docker exec -i "$CONTAINER_ID" sh -c "java -jar jenkins-cli.jar -auth $username:$password -s http://$CONTAINER_IP:8080/ build $job_name" || { echo -e "${RED}Failed to build job.${NC}"; exit 1; }

echo -e "${YELLOW}Job created and built successfully.${NC}"
 
