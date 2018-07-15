#!/bin/bash
# Script to build OpenNMS branches in isolated environments in parallel
# set -x

DOCKER_IMAGE=opennms/build-env:latest
GIT_URL=https://github.com/OpenNMS/opennms.git
DISPLAY_VERSION=SNAPSHOT
INSTALL_VERSION=opennms-SNAPSHOT
BRANCH=develop

# Error codes
E_ILLEGAL_ARGS=126
E_INIT_CONFIG=127

# Help function used in error messages and -h option
usage() {
  echo ""
  echo "Docker build script for parallel builds of branches using a Docker build image"
  echo ""
  echo "-b: Name of the branch to build"
  echo "-s: Name of the branch to build and launch using docker-compose"
  echo "-h: Show this help."
  echo ""
}

checkRequirements() {
  docker -v
  if [ ! $? -eq 0 ]; then
    echo "Docker is not installed or in search path."
    exit E_ILLEGAL_ARGS
  fi

  docker-compose -v
  if [ ! $? -eq 0 ]; then
    echo "Docker compose is not installed or in search path."
    exit E_ILLEGAL_ARGS
  fi
}

getBranch() {
  BRANCH=${1}
  BRANCH=${BRANCH/\//-}

  if [ ! -d ${BRANCH} ]; then
    mkdir ${BRANCH}
  fi

  if [ ! -d ${BRANCH}/opennms ]; then
    git clone ${GIT_URL} ${BRANCH}/opennms
    cd ${BRANCH}/opennms
    git checkout origin/${1}
  else
    cd ${BRANCH}/opennms
    git checkout origin/${1}
    git pull origin ${1}
  fi
  cd ../..
}

versioning() {
  cd ${BRANCH}/opennms

  # Version number built in the target directory
  INSTALL_VERSION=$(grep '<version>' pom.xml | sed -e 's,^[^>]*>,,' -e 's,<.*$,,' | head -n 1)
  INSTALL_VERSION=opennms-${INSTALL_VERSION}

  # Identify version to display you try to compile and extend version number with branch
  DISPLAY_VERSION=$(grep '<version>' pom.xml | sed -e 's,^[^>]*>,,' -e 's,<.*$,,' -e 's,-[^-]*-SNAPSHOT$,,' -e 's,-SNAPSHOT$,,' -e 's,-testing$,,' -e 's,-,.,g' | head -n 1)
  DISPLAY_VERSION=${DISPLAY_VERSION}-${BRANCH}
  DISPLAY_VERSION=${DISPLAY_VERSION}-$(git describe)
  cd ../..
}

build() {
  docker run --rm \
    -l "branch=${1}" \
    -v $(pwd)/${BRANCH}/opennms:/usr/src/opennms \
    -v $(pwd)/m2:/root/.m2 \
    -v $(pwd)/${BRANCH}/m2:/root/.m2/repository/org/opennms \
    ${DOCKER_IMAGE} /usr/bin/perl compile.pl -DskipTests

  docker run --rm \
    -l "branch=${1}" \
    -v $(pwd)/${BRANCH}/opennms:/usr/src/opennms \
    -v $(pwd)/m2:/root/.m2 \
    -v $(pwd)/${BRANCH}/m2:/root/.m2/repository/org/opennms \
    ${DOCKER_IMAGE} /usr/bin/perl ./assemble.pl -DskipTests -p dir -Dopennms.home=/opt/opennms

  # Use etc-overlay directory to set a custom version number displayed in the Web UI
  if [ ! -d ${BRANCH}/etc-overlay/opennms-properties.d ]; then
    mkdir -p ${BRANCH}/etc-overlay/opennms.properties.d
  fi
  echo "version.display=${DISPLAY_VERSION}" > ${BRANCH}/etc-overlay/opennms.properties.d/version.properties

  cd ${BRANCH}
  cp ../docker-compose.tpl docker-compose.yml
  sed -i "s/INSTALL_VERSION/${INSTALL_VERSION}/g" docker-compose.yml
}

run() {
  docker-compose up -d
  docker ps
}

# Evaluate arguments for build script.
if [[ "${#}" == 0 ]]; then
  usage
  exit ${E_ILLEGAL_ARGS}
fi

# Evaluate arguments for build script.
while getopts "b:hs:" flag; do
  case ${flag} in
    b)
      checkRequirements
      getBranch ${OPTARG}
      versioning
      build
      exit
      ;;
    s)
      checkRequirements
      getBranch ${OPTARG}
      versioning
      build
      run
      exit
      ;;
    h)
      usage
      exit
      ;;
    *)
      usage
      exit ${E_ILLEGAL_ARGS}
      ;;
  esac
done

# Strip of all remaining arguments
shift $((OPTIND - 1));

# Check if there are remaining arguments
if [[ "${#}" > 0 ]]; then
  echo "Error: To many arguments: ${*}."
  usage
  exit ${E_ILLEGAL_ARGS}
fi
