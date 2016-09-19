#!/bin/bash
set -o pipefail
IFS=$'\n\t'

DOCKER_SOCKET=/var/run/docker.sock

# Arguments:
# $1 env variable name to check
# $2 default value if environemnt variable was not set
function find_env() {
  var=`printenv "$1"`

  # If environment variable exists
  if [ -n "$var" ]; then
    echo $var
  else
    echo $2
  fi
}


if [ ! -e "${DOCKER_SOCKET}" ]; then
  echo "Docker socket missing at ${DOCKER_SOCKET}"
  exit 1
fi

if [ -n "${OUTPUT_IMAGE}" ]; then
  TAG="${OUTPUT_REGISTRY}/${OUTPUT_IMAGE}"
fi

echo "start war build......"
echo $BUILD

if [[ -n "${SOURCE_REPOSITORY}" ]]; then
  URL="${SOURCE_REPOSITORY}"
  curl --head --silent --fail --location --max-time 16 $URL > /dev/null
  if [ $? != 0 ]; then
    echo "Could not access source url: ${SOURCE_REPOSITORY}"
    exit 1
  fi
fi

BUILD_DIR=$(mktemp --directory)

PKG_NAME=`basename $URL`
echo ">> Downloading WAR [$PKG_NAME]"
curl -v $URL -o ${BUILD_DIR}/${PKG_NAME}

if [ $? != 0 ]; then
  echo "Error trying to downloading war: ${PKG_NAME}"
  exit 1
fi
pushd "${BUILD_DIR}"

DEPLOY_DIR=$(find_env "WAR_DEPLOY_DIR" "/opt/webserver/webapps")

if [ ! -n "$BUILD_BASE_IMAGE_NAME" ];then
  echo "Error! please provide base image to builder"
  exit 1
fi

CMD=$(find_env "DOCKERFILE_CMD" "/opt/webserver/bin/launch.sh")
RUN_UID=$(find_env "DOCKER_RUN_UID" "185")

dockerfile="FROM $BUILD_BASE_IMAGE_NAME\nADD $PKG_NAME $DEPLOY_DIR/$PKG_NAME\nUSER 0\nRUN chown $RUN_UID:$RUN_UID $DEPLOY_DIR/$PKG_NAME\nUSER $RUN_UID\nCMD [\"${CMD}\"]"

if [ -n "$CUSTOM_DOCKERFILE" ];then
  echo "using custom Dockerfile to build......"
  dockerfile=${CUSTOM_DOCKERFILE}
fi

echo -e "${dockerfile}" > Dockerfile

docker build --rm -t "${TAG}" "${BUILD_DIR}"
popd

if [[ -d /var/run/secrets/openshift.io/push ]] && [[ ! -e /root/.dockercfg ]]; then
  cp /var/run/secrets/openshift.io/push/.dockercfg /root/.dockercfg
fi

if [ -n "${OUTPUT_IMAGE}" ] || [ -s "/root/.dockercfg" ]; then
  docker push "${TAG}"
  if [ $? != 0 ]; then
    echo "Error trying to push images!"
    exit 1
  else
    echo "push ${TAG} successful!"
  fi
fi
