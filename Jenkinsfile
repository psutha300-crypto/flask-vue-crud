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
            }
        }

                stage('Deploy') {
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

                        account_id="$(aws sts get-caller-identity --query Account --output text)"
                        ecr_registry="${account_id}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"

                        remote_parameters="$(python3 - "$GIT_COMMIT" "$AWS_DEFAULT_REGION" "$ecr_registry" "$IMAGE_TAG" <<'PY'
import json
import re
import sys

commit, region, registry, tag = sys.argv[1:]

if not re.fullmatch(r"[0-9a-f]{40}", commit):
    raise SystemExit("Invalid Git commit")
if region != "eu-west-2":
    raise SystemExit("Unexpected AWS region")
if not re.fullmatch(r"[0-9]{12}\\.dkr\\.ecr\\.eu-west-2\\.amazonaws\\.com", registry):
    raise SystemExit("Invalid ECR registry")
if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", tag):
    raise SystemExit("Invalid image tag")

repo = "/opt/assessment/repo"
commands = [
    "set -eu",
    "mkdir -p /opt/assessment",
    f"if [ ! -d {repo}/.git ]; then git clone https://github.com/psutha300-crypto/flask-vue-crud.git {repo}; fi",
    f"git -C {repo} fetch origin main",
    f"git -C {repo} checkout --force --detach {commit}",
    f"bash {repo}/scripts/deploy.sh {region} {registry} {tag}",
]
print(json.dumps({"commands": commands}))
PY
                        )"

                        command_id="$(aws ssm send-command --region "$AWS_DEFAULT_REGION" --instance-ids "$TARGET_INSTANCE_ID" --document-name AWS-RunShellScript --parameters "$remote_parameters" --timeout-seconds 600 --query Command.CommandId --output text)"
                        echo "SSM deployment command submitted"

                        status=""
                        for attempt in $(seq 1 120); do
                            status="$(aws ssm get-command-invocation --region "$AWS_DEFAULT_REGION" --command-id "$command_id" --instance-id "$TARGET_INSTANCE_ID" --query Status --output text 2>/dev/null || true)"

                            case "$status" in
                                Success)
                                    break
                                    ;;
                                Failed|TimedOut|Cancelled|DeliveryTimedOut|ExecutionTimedOut|Undeliverable|Terminated)
                                    echo "SSM deployment failed with status: $status"
                                    aws ssm get-command-invocation --region "$AWS_DEFAULT_REGION" --command-id "$command_id" --instance-id "$TARGET_INSTANCE_ID" --query '{Status:Status,ResponseCode:ResponseCode,Output:StandardOutputContent,Error:StandardErrorContent}' --output json
                                    exit 1
                                    ;;
                            esac

                            sleep 5
                        done

                        if [ "$status" != "Success" ]; then
                            echo "SSM deployment did not finish within 10 minutes"
                            exit 1
                        fi

                        aws ssm get-command-invocation --region "$AWS_DEFAULT_REGION" --command-id "$command_id" --instance-id "$TARGET_INSTANCE_ID" --query StandardOutputContent --output text
                    '''
                }
            }
        }
    }
}