pipeline {
    agent any

    environment {
        IMAGE_NAME = 'harisharan634/hello'
        PATH = "C:\\Users\\harih\\AppData\\Local\\Programs\\DockerDesktop\\resources\\bin;${env.PATH}"
    }

    stages {

        stage('Generate Image Tag') {
            steps {
                script {
                    env.IMAGE_TAG  = new Date().format('yyyy-MM-dd-HHmmss')
                    env.FULL_IMAGE = "${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                }
                echo "Image: ${env.FULL_IMAGE}"
            }
        }

        stage('Check Docker') {
            steps {
                bat '''
                    @echo off
                    where docker
                    docker --version
                '''
            }
        }

        stage('Docker Login') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'docker_cred',
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {
                    bat '''
                        @echo off
                        echo|set /p="%DOCKER_PASSWORD%"| docker login -u "%DOCKER_USERNAME%" --password-stdin
                    '''
                }
            }
        }

        stage('Docker Build') {
            steps {
                bat 'docker build -t "%FULL_IMAGE%" .'
            }
        }

        stage('Docker Push') {
            steps {
                
                retry(3) {
                    
                    bat 'docker push "%FULL_IMAGE%"'
                }
            }
        }
    }

    post {
        always {
            bat 'docker logout || exit 0'
        }
        success {
            echo "Successfully pushed ${env.FULL_IMAGE}"
        }
        failure {
            echo 'Pipeline failed. Check the console output.'
        }
    }
}