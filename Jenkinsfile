@Library('nabster-ci') _

pipeline {
    agent any

    options {
        disableConcurrentBuilds()
    }

    stages {
        stage('Notify start') {
            steps {
                notifyTelegram('started')
            }
        }

        stage('Start test database') {
            steps {
                sh '''
                    # Nettoyage éventuel d'un ancien build interrompu
                    docker rm -f sentinel-ci-db >/dev/null 2>&1 || true

                    # Réseau CI isolé
                    docker network inspect sentinel-ci >/dev/null 2>&1 \
                        || docker network create sentinel-ci

                    # PostgreSQL temporaire uniquement pour les tests
                    docker run -d --rm \
                        --name sentinel-ci-db \
                        --network sentinel-ci \
                        -e POSTGRES_DB=sentinel_test \
                        -e POSTGRES_USER=sentinel_ci \
                        -e POSTGRES_PASSWORD=sentinel_ci \
                        postgres:16

                    # Attendre que PostgreSQL soit réellement prêt
                    for i in $(seq 1 30); do
                        if docker exec sentinel-ci-db \
                            pg_isready \
                            -U sentinel_ci \
                            -d sentinel_test >/dev/null 2>&1; then
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

        stage('Rails CI') {
            agent {
                dockerfile {
                    filename 'Dockerfile'
                    args '--network sentinel-ci'
                    reuseNode true
                }
            }

            environment {
                RAILS_ENV = 'test'

                POSTGRES_HOST = 'sentinel-ci-db'
                POSTGRES_USER = 'sentinel_ci'
                POSTGRES_PASSWORD = 'sentinel_ci'

                HOME = '/tmp'
            }

            stages {
                stage('Prepare test DB') {
                    steps {
                        sh 'bin/rails db:schema:load'
                    }
                }

                stage('Unit tests') {
                    steps {
                        sh '''
                            bundle exec rspec \
                                spec/models \
                                spec/services \
                                spec/jobs
                        '''
                    }
                }

                stage('Build CSS') {
                    steps {
                        sh 'bin/rails tailwindcss:build'
                    }
                }

                stage('Integration tests') {
                    steps {
                        sh 'bundle exec rspec spec/requests'
                    }
                }

                stage('Ruby lint') {
                    steps {
                        sh 'bin/rubocop'
                    }
                }

                stage('ERB lint') {
                    steps {
                        sh 'bundle exec erb_lint --lint-all'
                    }
                }

                stage('Gem audit') {
                    steps {
                        sh '''
                            export BUNDLER_AUDIT_DB="$WORKSPACE/.bundler-audit/ruby-advisory-db"
                            mkdir -p "$WORKSPACE/.bundler-audit"
                            bin/bundler-audit
                        '''
                    }
                }

                stage('Importmap audit') {
                    steps {
                        sh 'bin/importmap audit'
                    }
                }

                stage('Brakeman') {
                    steps {
                        sh 'bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error'
                    }
                }
            }
        }

        stage('E2E tests (Playwright Headless)') {
            stages {
                stage('Start test web server') {
                    steps {
                        sh '''
                            # Nettoyage d'un éventuel ancien conteneur web de test
                            docker rm -f sentinel-ci-web >/dev/null 2>&1 || true

                            # Construire l'image applicative Rails pour le serveur de test
                            docker build -t sentinel-ci-app:latest .

                            # Peupler la base de test avec les données et le compte admin pour les parcours E2E
                            docker run --rm \
                                --network sentinel-ci \
                                -e RAILS_ENV=test \
                                -e POSTGRES_HOST=sentinel-ci-db \
                                -e POSTGRES_USER=sentinel_ci \
                                -e POSTGRES_PASSWORD=sentinel_ci \
                                -e ADMIN_PASSWORD=sentinelpassword \
                                sentinel-ci-app:latest \
                                bin/rails db:seed

                            # Lancer le serveur Rails en mode test sur le réseau sentinel-ci
                            docker run -d \
                                --name sentinel-ci-web \
                                --network sentinel-ci \
                                -e RAILS_ENV=test \
                                -e POSTGRES_HOST=sentinel-ci-db \
                                -e POSTGRES_USER=sentinel_ci \
                                -e POSTGRES_PASSWORD=sentinel_ci \
                                -e SECRET_KEY_BASE=ci-secret-key-base-for-sentinel-test-32bytes-long \
                                sentinel-ci-app:latest \
                                bin/rails server -b 0.0.0.0 -p 3000

                            # Attendre que le serveur Rails soit prêt à répondre
                            for i in $(seq 1 30); do
                                if docker exec sentinel-ci-web curl -s -f http://localhost:3000/users/sign_in >/dev/null 2>&1; then
                                    echo "Sentinel web server is ready for E2E tests"
                                    exit 0
                                fi
                                if [ "$i" -eq 30 ]; then
                                    echo "Sentinel web server did not become ready in time"
                                    docker logs sentinel-ci-web
                                    exit 1
                                fi
                                sleep 1
                            done
                        '''
                    }
                }

                stage('Run Playwright') {
                    agent {
                        docker {
                            image 'mcr.microsoft.com/playwright:v1.63.0-noble'
                            args '--network sentinel-ci --ipc=host'
                            reuseNode true
                        }
                    }

                    environment {
                        PLAYWRIGHT_BASE_URL = 'http://sentinel-ci-web:3000'
                        CI = 'true'
                        ADMIN_USERNAME = 'admin'
                        ADMIN_PASSWORD = 'sentinelpassword'
                        HOME = '/tmp'
                    }

                    steps {
                        sh '''
                            npm ci
                            npx playwright test
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            sh '''
                docker rm -f sentinel-ci-db >/dev/null 2>&1 || true
                docker rm -f sentinel-ci-web >/dev/null 2>&1 || true
            '''
        }

        success {
            notifyTelegram('success')
        }

        failure {
            notifyTelegram('failed')
        }
    }
}
