@Library('nabster-ci') _

pipeline {
    agent {
        dockerfile {
            filename 'Dockerfile'
            args '--network sentinel_default'
        }
    }

    environment {
        RAILS_ENV = 'test'
        POSTGRES_HOST = 'sentinel-db'
        POSTGRES_USER = 'postgres'
        POSTGRES_PASSWORD = 'postgres'
    }

    stages {
        stage('Notify start') {
            steps {
                notifyTelegram('started')
            }
        }

        stage('Prepare test DB') {
            steps {
                sh 'bin/rails db:prepare'
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

    post {
        success {
            notifyTelegram('success')
        }

        failure {
            notifyTelegram('failed')
        }
    }
}
