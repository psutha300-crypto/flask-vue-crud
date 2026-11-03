# Developing a Single Page App with Flask and Vue.js

### Want to learn how to build this?

Check out the [tutorial](https://testdriven.io/developing-a-single-page-app-with-flask-and-vuejs).


## Assessment implementation

This project packages the Flask and Vue book application with Docker and deploys it to an AWS EC2 instance through a Jenkins pipeline.

### Components

- **Frontend:** Vue 3 and Vite, built as static files and served by Nginx.
- **Backend:** Flask REST API for listing, adding, editing, and deleting books.
- **Local containers:** Docker Compose runs the frontend and backend; Nginx forwards `/api` requests to Flask.
- **Image registry:** Jenkins builds ARM64 images and pushes them to private Amazon ECR repositories with a commit and build number tag.
- **Deployment:** Jenkins uses AWS Systems Manager Run Command to deploy the images to EC2. The deployment does not use SSH.

## Want to use this project?
### Run locally with Docker Compose

Prerequisite: Docker Desktop with the Docker Compose plugin.

Clone this repository and enter the project folder:

```sh
git clone https://github.com/psutha300-crypto/flask-vue-crud.git
cd flask-vue-crud
```

Build and start the application:

```sh
docker compose up --build -d
```

Open http://localhost:8080 in your browser. Nginx serves the Vue app and forwards `/api` requests to Flask.

Check the containers:

```sh
docker compose ps
```

Stop the application:

```sh
docker compose down
```

Book data is held in memory and resets when the backend container restarts.
## CI/CD pipeline

The Declarative Pipeline is defined in `Jenkinsfile`. It runs these stages:

1. **Checkout:** Gets the source from this repository.
2. **Verify tools:** Checks Git, Python, Flake8, AWS CLI, and Docker.
3. **Build:** Builds the Vue frontend using the build stage in `client/Dockerfile`.
4. **Lint:** Runs Flake8 against the Flask backend.
5. **Verify AWS access:** Confirms the Jenkins AWS identity and ECR authentication.
6. **Docker Build:** Builds ARM64 backend and frontend images, tags them with the Git commit and Jenkins build number, then pushes them to the private ECR repositories.
7. **Deploy:** Uses the `TARGET_INSTANCE_ID` build parameter and AWS Systems Manager Run Command to deploy the images to EC2. The stage waits for the command result.

### Jenkins and AWS configuration

- Add the AWS access key as a Jenkins credential with ID `aws-deploy`. Do not commit access keys or secret values to this repository.
- Run the job with the `TARGET_INSTANCE_ID` parameter set to the EC2 instance ID.
- Jenkins uses AWS IAM permissions to push images to ECR and send the deployment command to the target instance.
- The EC2 instance role gives the instance permission to pull images from ECR.
- Deployment uses Systems Manager; SSH and port 22 are not used.

## Production notes

- **AWS region:** `eu-west-2` (Europe, London).
- **EC2:** Amazon Linux 2023 on ARM64.
- **Access:** Open `http://<EC2-public-IPv4>/` in a browser. The security group allows HTTP on port 80 from the configured source IP; SSH port 22 is not open.
- **Health checks:** Docker Compose checks the backend and frontend health during deployment. Jenkins reports the SSM command result.
- **Data:** Book records are stored in memory and reset when the backend restarts. There is no database or user authentication.
- **Transport:** The demo uses HTTP, not HTTPS. Do not use it for private information.
- **Rollback:** The pipeline does not automatically roll back a failed deployment.
- **Cost:** EC2 charges can continue while the instance is running, and stored ECR images can incur storage charges.