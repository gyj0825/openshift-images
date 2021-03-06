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

if [[ -d /var/run/secrets/openshift.io/push ]] && [[ ! -e /root/.dockercfg ]]; then
  cp /var/run/secrets/openshift.io/push/.dockercfg /root/.dockercfg
fi

echo "start patch image......"
echo $BUILD

###get base image
#if NAMESPACE is't openshift,you must add policy.
if [ ! -n "$NAMESPACE" ];then
  namespace=`cat /var/run/secrets/kubernetes.io/serviceaccount/namespace`
else
  namespace=$NAMESPACE
fi

# support imagestream and image
if [ ! -n "$BASE_PATCH_IMAGE" ];then
  echo "Error: please provide base image to builder."
  exit 1
fi

echo $BASE_PATCH_IMAGE | grep -q "/"
# decide image or imagstream
if [ $? != 0 ];then
   build_base_image=${OUTPUT_REGISTRY}/${namespace}/${BASE_PATCH_IMAGE}:latest
else
   build_base_image=$BASE_PATCH_IMAGE
fi
echo "pacth image: {'image': '$build_base_image'}"

docker pull "$build_base_image"
if [ $? != 0 ];then
  echo "Error: try pull $build_base_image failed."
  exit 1
fi

###whether patch source URL is null
if [[ -n "${SOURCE_REPOSITORY}" ]]; then
  URL="${SOURCE_REPOSITORY}"
  curl --head --silent --fail --location --max-time 16 $URL > /dev/null
  if [ $? != 0 ]; then
    echo "Could not access source url: ${SOURCE_REPOSITORY}"
    exit 1
  fi
fi

### docker build or docker tag
BUILD_DIR=$(mktemp --directory)
# download patch packages
PKG_NAME=`basename $URL`
echo ">> Downloading Patch packages... "
curl -v $URL -o ${BUILD_DIR}/${PKG_NAME}

if [ $? != 0 ]; then
  echo "Error trying to downloading patch packages!"
  exit 1
fi
pushd "${BUILD_DIR}"

# get patch image user id
if [ ! -n "$RUN_UID" ];then
  run_uid=`docker inspect $build_base_image | grep  -E "\"User\": \"[0-9]+\"" | sed -n 1p | awk -F '"' '{print $4}'`
  if [ ! -n "$run_uid" ];then
     echo "Error: $build_base_image do not assign User,please assign user id by RUN_UID Environment variables"
     exit 1 
  fi
else
  run_uid="${RUN_UID}"
  if [ "$run_uid" == "0" ];then
     echo "Error: can't use super user root."
     exit 1
  fi
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

# generated Dockerfile
dockerfile="FROM $build_base_image\nCOPY ${PKG_NAME} /tmp/${PKG_NAME}\nUSER 0\nWORKDIR /\nRUN  ${run_command}\nUSER $run_uid"

if [ -n "$CUSTOM_DOCKERFILE" ];then
  echo "using custom Dockerfile to build......"
  dockerfile=${CUSTOM_DOCKERFILE}
fi

echo -e "${dockerfile}" > Dockerfile

docker build --rm -t "${TAG}" "${BUILD_DIR}"
popd

if [ -n "${OUTPUT_IMAGE}" ] || [ -s "/root/.dockercfg" ]; then
  docker push "${TAG}"
  if [ $? != 0 ]; then
    echo "Error trying to push images!"
    exit 1
  else
    echo "push ${TAG} successful!"
  fi
fi
