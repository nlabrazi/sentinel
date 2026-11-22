@Library('nabster-ci') _

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    stages {
        stage('Notify start') {
            steps {
                notifyTelegram('started')
                sh 'git clean -ffdx'
            }
        }

        stage('Start test database') {
            steps {
                sh '''
                    docker rm -f sentinel-ci-db >/dev/null 2>&1 || true
                    docker network inspect sentinel-ci >/dev/null 2>&1 || docker network create sentinel-ci

                    docker run -d --rm \
                        --name sentinel-ci-db \
                        --network sentinel-ci \
                        -e POSTGRES_DB=sentinel_test \
                        -e POSTGRES_USER=sentinel_ci \
                        -e POSTGRES_PASSWORD=sentinel_ci \
                        postgres:16-alpine

                    for i in $(seq 1 30); do
                        if docker exec sentinel-ci-db pg_isready -h 127.0.0.1 -U sentinel_ci -d sentinel_test >/dev/null 2>&1; then
                            echo "PostgreSQL test database is ready"
                            exit 0
                        fi
                        sleep 1
                    done

                    echo "PostgreSQL did not become ready"
                    docker logs sentinel-ci-db
                    exit 1
                '''
            }
        }

        stage('CI, Unit Tests & Build') {
            agent {
                docker {
                    image 'node:26-bookworm-slim'
                    args '--network sentinel-ci'
                    reuseNode true
                }
            }

            environment {
                CI = 'true'
                DATABASE_URL = 'postgresql://sentinel_ci:sentinel_ci@sentinel-ci-db:5432/sentinel_test'
                SESSION_SECRET = 'ci-session-secret-0123456789abcdef0123456789abcdef'
                AUTH_DEV_BYPASS = 'true'
            }

            stages {
                stage('Install') {
                    steps {
                        npmCi()
                    }
                }

                stage('Check') {
                    steps {
                        sh 'npm run check'
                    }
                }

                stage('Typecheck') {
                    steps {
                        sh 'npm run typecheck'
                    }
                }

                stage('Unit tests') {
                    steps {
                        sh 'npm test'
                    }
                }

                stage('Build') {
                    steps {
                        sh 'npm run build'
                    }
                }
            }
        }

        stage('End-to-end tests') {
            agent {
                docker {
                    image 'mcr.microsoft.com/playwright:v1.65.1-noble'
                    args '--network sentinel-ci --ipc=host'
                    reuseNode true
                }
            }

            environment {
                CI = 'true'
                NODE_ENV = 'test'
                DATABASE_URL = 'postgresql://sentinel_ci:sentinel_ci@sentinel-ci-db:5432/sentinel_test'
                SESSION_SECRET = 'ci-session-secret-0123456789abcdef0123456789abcdef'
                PROMETHEUS_METRICS_TOKEN = 'ci-metrics-token'
                AUTH_DEV_BYPASS = 'true'
            }

            steps {
                sh '''
                    npm run db:migrate
                    npm run test:e2e
                '''
            }
        }

        stage('Docker build & push') {
            steps {
                dockerBuildAndPush(
                    imageName: 'sentinel',
                    target: 'prod'
                )
            }
        }
    }

    post {
        always {
            sh 'docker rm -f sentinel-ci-db >/dev/null 2>&1 || true'
        }

        success {
            notifyTelegram('success')
        }

        failure {
            notifyTelegram('failed')
        }
    }
}
