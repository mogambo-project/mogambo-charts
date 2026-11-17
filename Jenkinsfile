// Publishes the shared Helm chart (app/) to Docker Hub OCI on every push to the main line,
// then tags the exact commit in GitHub with the version it published.
// Published version = Chart.yaml's version + "-${BUILD_NUMBER}"  (e.g. 0.1.0-7) — immutable,
// increasing, SemVer-valid. The committed Chart.yaml keeps the base version (bump its
// major.minor.patch by hand when you want a new line, exactly like the apps' code version).
//
// The work is deliberately split into one stage per step: the "Stages" table (rows = builds,
// columns = stages) renders one column per stage, so while a build runs you can see which
// step it is standing on instead of one opaque "everything" cell.
pipeline {
  agent any
  triggers { pollSCM('H/2 * * * *') }

  environment {
    REGISTRY_HOST  = 'registry-1.docker.io'
    OCI_NS         = 'oci://registry-1.docker.io/andriohanania'   // -> andriohanania/app:<version>
    DOCKERHUB_CRED = 'bb835d88-f2f7-402f-a964-a492f5cd7cbf'
    GITHUB_CRED    = 'github-userpass'                            // same cred the branch source scans with
    CHART_DIR      = 'app'
  }

  stages {
    stage('Install Helm') {
      when { branch 'master' }   // the chart's main line (not PRs)
      steps {
        // Ensure helm is on PATH; if not, fetch it into the workspace.
        sh '''
          if ! command -v helm >/dev/null 2>&1; then
            curl -fsSL https://get.helm.sh/helm-v3.16.2-linux-amd64.tar.gz | tar xz
            install -m 0755 linux-amd64/helm ./helm
          fi
        '''
        script {
          env.HELM = sh(script: 'command -v helm >/dev/null 2>&1 && echo helm || echo ./helm', returnStdout: true).trim()
        }
      }
    }

    stage('Lint & validate') {
      when { branch 'master' }   // gate the chart BEFORE we package/publish it
      steps {
        // kubeconform validates the RENDERED manifests against the Kubernetes schemas.
        sh '''
          if ! command -v kubeconform >/dev/null 2>&1 && [ ! -x ./kubeconform ]; then
            curl -fsSL https://github.com/yannh/kubeconform/releases/download/v0.6.7/kubeconform-linux-amd64.tar.gz | tar xz kubeconform
            install -m 0755 kubeconform ./kubeconform
          fi
        '''
        script {
          env.KUBECONFORM = sh(script: 'command -v kubeconform >/dev/null 2>&1 && echo kubeconform || echo ./kubeconform', returnStdout: true).trim()
        }
        // For each CI fixture: helm lint (also validates values.schema.json), then render and
        // kubeconform the output. -ignore-missing-schemas skips CRDs we don't ship schemas for
        // (HTTPRoute, VPA) while still strictly checking the core kinds (Deployment, Service, ...).
        sh """
          set -eu
          for v in ${env.CHART_DIR}/ci/*-values.yaml; do
            echo "== lint \$v =="
            ${env.HELM} lint ${env.CHART_DIR} --values "\$v"
            echo "== template + kubeconform \$v =="
            ${env.HELM} template ${env.CHART_DIR} --values "\$v" | ${env.KUBECONFORM} -strict -ignore-missing-schemas -summary
          done
        """
      }
    }

    stage('Resolve version') {
      when { branch 'master' }
      steps {
        script {
          env.CHART_NAME = sh(script: "grep '^name:' ${CHART_DIR}/Chart.yaml | awk '{print \$2}'", returnStdout: true).trim()
          def base       = sh(script: "grep '^version:' ${CHART_DIR}/Chart.yaml | awk '{print \$2}'", returnStdout: true).trim()
          env.CHART_VERSION = "${base}-${env.BUILD_NUMBER}"
          sh "sed -i 's/^version:.*/version: ${env.CHART_VERSION}/' ${CHART_DIR}/Chart.yaml"   // workspace only, not committed

          env.GIT_TAG  = "${env.CHART_NAME}-${env.CHART_VERSION}"                 // e.g. app-0.1.0-6
          env.OCI_REF  = "${env.OCI_NS}/${env.CHART_NAME}:${env.CHART_VERSION}".replace('oci://', '')
          env.REPO_WEB = (env.GIT_URL ?: '').replaceAll(/\.git$/, '')              // https://github.com/<owner>/<repo>

          // Name the build after what it publishes, so the build history is readable at a glance.
          currentBuild.displayName = "#${env.BUILD_NUMBER} · ${env.GIT_TAG}"
        }
      }
    }

    stage('Package chart') {
      when { branch 'master' }
      steps {
        sh "${env.HELM} package ${CHART_DIR} -d ."
        archiveArtifacts artifacts: "${env.CHART_NAME}-${env.CHART_VERSION}.tgz", fingerprint: true
      }
    }

    stage('Push to OCI') {
      when { branch 'master' }
      steps {
        withCredentials([usernamePassword(credentialsId: env.DOCKERHUB_CRED, usernameVariable: 'U', passwordVariable: 'P')]) {
          sh "echo \"\$P\" | ${env.HELM} registry login ${REGISTRY_HOST} -u \"\$U\" --password-stdin"
          // Keep the push output so the summary can quote the digest; still fail loudly on error.
          sh "${env.HELM} push ${env.CHART_NAME}-${env.CHART_VERSION}.tgz ${OCI_NS} > push.log 2>&1 || { cat push.log; exit 1; }"
          sh 'cat push.log'
          script {
            env.CHART_DIGEST = sh(script: "sed -n 's/.*Digest: *//p' push.log | tail -1", returnStdout: true).trim()
          }
          sh "${env.HELM} registry logout ${REGISTRY_HOST} || true"
        }
      }
    }

    stage('Tag in GitHub') {
      when { branch 'master' }
      steps {
        // The chart is already published at this point, so a tagging failure must not turn a
        // successful publish red - it marks the build UNSTABLE and this stage red instead.
        catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE', message: 'Could not push the git tag') {
          withCredentials([usernamePassword(credentialsId: env.GITHUB_CRED, usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
            // The token is fed through a credential helper, so it never lands in .git/config
            // or in a remote URL that git might echo back.
            sh '''
              set -eu
              git config user.email "jenkins@mogambo.local"
              git config user.name  "Jenkins CI"
              git tag -a "$GIT_TAG" "$GIT_COMMIT" -m "Helm chart $CHART_NAME $CHART_VERSION published to $OCI_REF"
              git -c credential.helper= -c credential.helper='!f() { echo "username=$GH_USER"; echo "password=$GH_TOKEN"; }; f' push origin "refs/tags/$GIT_TAG"
            '''
          }
          script { env.GIT_TAG_PUSHED = 'true' }
        }
      }
    }

    stage('Summary') {
      when { branch 'master' }
      steps {
        script {
          def shortSha  = (env.GIT_COMMIT ?: '')
          if (shortSha.length() > 8) { shortSha = shortSha.substring(0, 8) }
          def tagged    = env.GIT_TAG_PUSHED == 'true'
          def tagUrl    = env.REPO_WEB ? "${env.REPO_WEB}/releases/tag/${env.GIT_TAG}" : ''
          def commitUrl = env.REPO_WEB ? "${env.REPO_WEB}/commit/${env.GIT_COMMIT}"    : ''
          def hubUrl    = "https://hub.docker.com/r/andriohanania/${env.CHART_NAME}/tags?name=${env.CHART_VERSION}"
          def pullRef   = env.OCI_REF.substring(0, env.OCI_REF.lastIndexOf(':'))

          echo """
==================== PUBLISHED ====================
 chart        : ${env.CHART_NAME}
 version      : ${env.CHART_VERSION}
 OCI ref      : ${env.OCI_REF}
 digest       : ${env.CHART_DIGEST ?: '(not reported)'}
 branch       : ${env.BRANCH_NAME}
 commit       : ${shortSha}
 git tag      : ${env.GIT_TAG} ${tagged ? '(pushed to GitHub)' : '(PUSH FAILED - see the Tag in GitHub stage)'}
 tag URL      : ${tagUrl}
 commit URL   : ${commitUrl}
 Docker Hub   : ${hubUrl}
 pull with    : helm pull oci://${pullRef} --version ${env.CHART_VERSION}
===================================================
"""

          // Shown on the build page, right under the build name. Renders as links only when
          // Manage Jenkins -> Security -> Markup Formatter is set to "Safe HTML".
          currentBuild.description =
            "<b>${env.CHART_NAME}</b> ${env.CHART_VERSION} &rarr; <code>${env.OCI_REF}</code><br/>" +
            "tag: " + (tagged ? "<a href=\"${tagUrl}\">${env.GIT_TAG}</a>" : "${env.GIT_TAG} <b>(not pushed)</b>") +
            " &middot; commit: <a href=\"${commitUrl}\">${shortSha}</a>" +
            " &middot; <a href=\"${hubUrl}\">Docker Hub</a>"
        }
      }
    }
  }

  post {
    failure { echo 'Chart publish failed - check the stage log.' }
  }
}
