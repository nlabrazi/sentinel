@Library('nabster-ci') _

pipeline {
    agent {
        dockerfile {
            filename 'Dockerfile'
        }
    }

    stages {
        stage('Notify start') {
            steps {
                notifyTelegram('started')
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
                sh 'bin/bundler-audit'
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
