// Publishes the shared Helm chart (app/) to Docker Hub OCI on every push to the main line.
// Published version = Chart.yaml's version + "-${BUILD_NUMBER}"  (e.g. 0.1.0-7) — immutable,
// increasing, SemVer-valid. The committed Chart.yaml keeps the base version (bump its
// major.minor.patch by hand when you want a new line, exactly like the apps' code version).
pipeline {
  agent any
  triggers { pollSCM('H/2 * * * *') }

  environment {
    REGISTRY_HOST  = 'registry-1.docker.io'
    OCI_NS         = 'oci://registry-1.docker.io/andriohanania'   // -> andriohanania/app:<version>
    DOCKERHUB_CRED = 'bb835d88-f2f7-402f-a964-a492f5cd7cbf'
    CHART_DIR      = 'app'
  }

  stages {
    stage('publish chart to OCI') {
      when { branch 'master' }   // the chart's main line (not PRs)
      steps {
        script {
          // Ensure helm is on PATH; if not, fetch it into the workspace.
          sh '''
            if ! command -v helm >/dev/null 2>&1; then
              curl -fsSL https://get.helm.sh/helm-v3.16.2-linux-amd64.tar.gz | tar xz
              install -m 0755 linux-amd64/helm ./helm
            fi
          '''
          def HELM = sh(script: 'command -v helm >/dev/null 2>&1 && echo helm || echo ./helm', returnStdout: true).trim()

          // version = base version in Chart.yaml + build number (e.g. 0.1.0-7)
          def base    = sh(script: "grep '^version:' ${CHART_DIR}/Chart.yaml | awk '{print \$2}'", returnStdout: true).trim()
          def version = "${base}-${env.BUILD_NUMBER}"
          sh "sed -i 's/^version:.*/version: ${version}/' ${CHART_DIR}/Chart.yaml"   // workspace only, not committed

          withCredentials([usernamePassword(credentialsId: env.DOCKERHUB_CRED, usernameVariable: 'U', passwordVariable: 'P')]) {
            sh "echo \"\$P\" | ${HELM} registry login ${REGISTRY_HOST} -u \"\$U\" --password-stdin"
            sh "${HELM} package ${CHART_DIR} -d ."
            sh "${HELM} push app-${version}.tgz ${OCI_NS}"
            sh "${HELM} registry logout ${REGISTRY_HOST} || true"
          }
          echo "Published ${OCI_NS}/app:${version}"
        }
      }
    }
  }

  post {
    failure { echo 'Chart publish failed - check the stage log.' }
  }
}