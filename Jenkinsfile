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
            sh '''
                export HOME="$WORKSPACE"
                export XDG_DATA_HOME="$WORKSPACE/.local/share"

                mkdir -p "$XDG_DATA_HOME"

                bin/bundler-audit
            '''
          }
        }

        stage('Importmap audit') {
            steps {
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
