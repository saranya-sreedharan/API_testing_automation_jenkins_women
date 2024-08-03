This api testing automation, including 3 bash script

make sure that docker and docker-compose is already installed in the system

1. Creating the postgres database container and creating table inside the database
inputs (eg) : 
 db_name = report_db
 db_password = password
 db_ip = 100.26.219.30 
 the default table name will be reports


2. Jenkins_script will setup the jenkins container 
inputs:

jenkins_location: /home/ubuntu/jenkins_data

jenkins username = admin
jenkiins pasword = admin

gitlab_username = saruSaranya
gitlabpassword = saruSYAM23

gitlab_url : https://gitlab.com
gitlab_token = glpat-qPUkzurmzjMaU_NT5JNM
directory_url : https://gitlab.com/saruSaranya/api-testing_project.git
database_ip = 100.26.219.30 
job_name = api_testing
db_name: report_db
db_password= password 

3. Run the prometehus_grafana setup script. It will ask where the postgres_exporter installed-ip address (it should be the same where the database is running)
give the ip address. Open promethus web view in port 9090 and grafana web view in port 3000. 

then in prometheus target we can see the target metrics. next go to grafana and add datasource - promethus give promethus url, then save and test. 
next add datasource - progresql and give the databse details and source as promethus. Then dashboard import dashboard-9628 

now database details will see in grafana dash board.



for api testing and storing the data in the database script, if you want to see the content in the database, you can see while accessing from inside the jenkins
if you want to see the conetnt only follow this : 
sudo nano /etc/apt/sources.list.d/pgdg.list     //edit this file (jemmy-pgdg main)
sudo apt install postgresql-client-15  -y

