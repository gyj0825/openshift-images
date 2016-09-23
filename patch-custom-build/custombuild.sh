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

echo "start patch image......"
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
echo ">> Downloading Patch packages... "
curl -v $URL -o ${BUILD_DIR}/${PKG_NAME}

if [ $? != 0 ]; then
  echo "Error trying to downloading patch packages!"
  exit 1
fi
pushd "${BUILD_DIR}"

if [ ! -n "$BUILD_BASE_IMAGE_NAME" ];then
  echo "Error: please provide base image to builder"
  exit 1
fi

RUN_UID=`docker inspect $BUILD_BASE_IMAGE_NAME | grep  -E "\"User\": \"[0-9]+\"" | sed -n 1p | awk -F '"' '{print $4}'`

if [ ! -n "$RUN_UID" ];then
   echo "Error: $BUILD_BASE_IMAGE_NAME do not assign User"
   exit 1 
fi

#define patch command,default unzip ,you can use "tar -zxf","rpm -ivh" etc
patch_command="unzip"

if [ -n "$PATCH_COMMAND" ];then
  echo "using custom command to pacth......"
  patch_command=${PATCH_COMMAND}
fi

# define run command, default "${patch_command} /tmp/${PKG_NAME}"
run_command="${patch_command} /tmp/${PKG_NAME}"

if [ -n "$RUN_COMMAND" ];then
  echo "using custom run_command to run......"
  run_command=${RUN_COMMAND}
fi

dockerfile="FROM $BUILD_BASE_IMAGE_NAME\nCOPY ${PKG_NAME} /tmp/${PKG_NAME}\nUSER 0\nWORKDIR /\nRUN  ${run_command}\nUSER $RUN_UID"

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
