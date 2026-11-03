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
    }
}