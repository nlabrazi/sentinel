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
    }

    post {
        always {
            sh '''
                docker rm -f sentinel-ci-db >/dev/null 2>&1 || true
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
