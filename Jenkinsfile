pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }

    environment {
        AWS_DEFAULT_REGION = 'eu-west-2'
        AWS_PAGER = ''
    }
        parameters {
        string(
            name: 'TARGET_INSTANCE_ID',
            defaultValue: '',
            description: 'EC2 instance ID in eu-west-2 for SSM deployment'
        )
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Verify tools') {
            steps {
                sh '''
                    git --version
                    python3 --version
                    flake8 --version
                    aws --version
                    docker version
                '''
            }
        }
               stage('Build') {
            steps {
                sh '''
                    set -eu
                    docker build --platform linux/arm64 --target build --tag assessment-frontend-build:ci ./client
                '''
            }
        }
                stage('Lint') {
            steps {
                sh '''
                    set -eu
                    flake8 --config=.flake8 server --show-source --statistics
                '''
            }
        }

        stage('Verify AWS access') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-deploy',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                        set +x
                        aws sts get-caller-identity \
                          --query "ends_with(Arn, ':user/assessment-jenkins')" \
                          --output text > identity-check.txt

                        grep -qx 'True' identity-check.txt

                        aws ecr get-login-password \
                          --region "$AWS_DEFAULT_REGION" > /dev/null

                        echo "Jenkins AWS identity and ECR authentication verified"
                    '''
                }
            }
        }
                    stage('Docker Build') {
            steps {
                script {
                    env.IMAGE_TAG = sh(
                        script: 'git rev-parse --short=12 HEAD',
                        returnStdout: true
                    ).trim() + "-${env.BUILD_NUMBER}"
                }

                withCredentials([usernamePassword(
                    credentialsId: 'aws-deploy',
                    usernameVariable: 'AWS_ACCESS_KEY_ID',
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                )]) {
                    sh '''
                        set +x
                        set -eu

                        account_id="$(aws sts get-caller-identity --query Account --output text)"
                        ecr_registry="${account_id}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
                        docker_config="$(mktemp -d)"
                        export DOCKER_CONFIG="$docker_config"
                        trap 'rm -rf "$docker_config"' EXIT

                        aws ecr get-login-password --region "$AWS_DEFAULT_REGION" > "$DOCKER_CONFIG/ecr-password"
                        docker login --username AWS --password-stdin "$ecr_registry" < "$DOCKER_CONFIG/ecr-password"
                        rm -f "$DOCKER_CONFIG/ecr-password"

                        docker build --platform linux/arm64 --tag "$ecr_registry/assessment/backend:$IMAGE_TAG" ./server
                        docker build --platform linux/arm64 --tag "$ecr_registry/assessment/frontend:$IMAGE_TAG" ./client

                        docker push "$ecr_registry/assessment/backend:$IMAGE_TAG"
                        docker push "$ecr_registry/assessment/frontend:$IMAGE_TAG"

                        echo "Pushed both images with tag $IMAGE_TAG"
                    '''
                }
                        stage('SSM connectivity') {
            steps {
                script {
                    def target = params.TARGET_INSTANCE_ID?.trim()
                    if (!(target ==~ /^i-[0-9a-f]{8,17}$/)) {
                        error('Enter a valid EC2 instance ID in TARGET_INSTANCE_ID')
                    }
                }

                withCredentials([usernamePassword(
                    credentialsId: 'aws-deploy',
                    usernameVariable: 'AWS_ACCESS_KEY_ID',
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                )]) {
                    sh '''
                        set +x
                        set -eu

                        command_id="$(aws ssm send-command --region "$AWS_DEFAULT_REGION" --instance-ids "$TARGET_INSTANCE_ID" --document-name AWS-RunShellScript --parameters '{"commands":["echo SSM connection verified"]}' --query Command.CommandId --output text)"
                        aws ssm wait command-executed --region "$AWS_DEFAULT_REGION" --command-id "$command_id" --instance-id "$TARGET_INSTANCE_ID"
                        aws ssm get-command-invocation --region "$AWS_DEFAULT_REGION" --command-id "$command_id" --instance-id "$TARGET_INSTANCE_ID" --query StandardOutputContent --output text
                    '''
                }
            }
        }
    }
}