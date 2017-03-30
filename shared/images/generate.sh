#!/bin/sh

set -eu

MANIFEST_SOURCE="${MANIFEST_SOURCE:-https://raw.githubusercontent.com/docker-library/official-images/master/library/${BASE_REPO}}"
IMAGE_CUSTOMIZATIONS=${IMAGE_CUSTOMIZATIONS:-}

NEW_ORG=${NEW_ORG:-circleci}
BASE_REPO_BASE=$(echo $BASE_REPO | cut -d/ -f2)
NEW_REPO=${NEW_REPO:-${NEW_ORG}/${BASE_REPO_BASE}}

INCLUDE_ALPINE=${INCLUDE_ALPINE:-false}

function find_tags() {
  ALPINE_TAG="-e alpine"
  if [[ $INCLUDE_ALPINE == "true" ]]
  then
    ALPINE_TAG=""
  fi

  curl -sSL "$MANIFEST_SOURCE" \
    | grep Tags \
    | sed  's/Tags: //g' \
    | sed 's|, | |g' \
    | grep -v $ALPINE_TAG -e 'slim' -e 'onbuild' -e windows -e wheezy -e stretch -e nanoserver
}

SHARED_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

TEMPLATE=${TEMPLATE:-basic}
VARIANTS=${VARIANTS:-none}

function find_template() {
  # find the right template - start with invoker path
  # then check this path
  template=$1
  PREFIX=$2

  if [ -e "$(dirname pwd)/resources/$PREFIX-${template}.template" ]
  then
    echo "$(dirname pwd)/resources/$PREFIX-${template}.template"
    exit 0
  fi

  if [ -e "${SHARED_DIR}/$PREFIX-${template}.template" ]
  then
    echo "${SHARED_DIR}/$PREFIX-${template}.template"
    exit 0
  fi

  exit 1
}

GENERATED_HEADER='###
### DO NOT MODIFY THIS FILE.  THIS FILE HAS BEEN AUTOGENERATED
###'

function render_dockerfile_template() {
  TEMP=$(mktemp)
  printf "%s\n" "${IMAGE_CUSTOMIZATIONS}" > $TEMP

  TEMPLATE_PATH=$(find_template $1 Dockerfile)

  echo "$GENERATED_HEADER"

  cat $TEMPLATE_PATH | \
    sed "s|{{BASE_IMAGE}}|$BASE_IMAGE|g" | \
    sed "/# BEGIN IMAGE CUSTOMIZATIONS/ r $TEMP"

  rm $TEMP
}

function render_readme_template() {
  BASIC_TEMP_PATH=$(mktemp)
  BROWSERS_TEMP_PATH=$(mktemp)

  TEMPLATE_TYPE=basic

  echo "$GENERATED_HEADER"

  cat images/latest/Dockerfile | \
    grep -v -e '^###' -e '^{{' -e '^# BEGIN' -e '^# END BEGIN' | \
    grep -v -e '^ *$' > $BASIC_TEMP_PATH

  if [ -e images/latest/browsers/Dockerfile ]
  then
    cat images/latest/browsers/Dockerfile | \
     grep -v -e '^###' -e '^{{' -e '^# BEGIN' -e '^# END BEGIN' | \
     grep -v -e '^ *$' > $BROWSERS_TEMP_PATH
  else
    TEMPLATE_TYPE=service
  fi

  TEMPLATE_PATH=$(find_template $TEMPLATE_TYPE README)

  cat $TEMPLATE_PATH | \
    sed "s|{{NAME}}|${NAME}|g" | \
    sed "s|{{BASE_IMAGE}}|$BASE_IMAGE|g" | \
    sed "s|{{BASE_REPO}}|$BASE_REPO|g" | \
    sed "/{{DOCKERFILE_BASIC_SAMPLE}}/ r ${BASIC_TEMP_PATH}" | \
    sed "/{{DOCKERFILE_BROWSERS_SAMPLE}}/ r ${BROWSERS_TEMP_PATH}" | \
    grep -v -e '^###' -e '^{{' -e '^# BEGIN' -e '^# END BEGIN'

  rm $BASIC_TEMP_PATH
  rm $BROWSERS_TEMP_PATH
}


rm -rf images
mkdir -p images

for tag in $(find_tags)
do
  echo $tag

  mkdir -p images/$tag

  BASE_IMAGE=${BASE_REPO}:${tag}
  NEW_IMAGE=${NEW_REPO}:${tag}

  render_dockerfile_template $TEMPLATE > images/$tag/Dockerfile

  # variants based on the basic image
  if [ ${VARIANTS} != "none" ]
  then
    for variant in ${VARIANTS[@]}
    do

      echo "  $variant"
      BASE_IMAGE=${NEW_REPO}:${tag}
      NEW_IMAGE=${NEW_REPO}:${tag}-${variant}

      mkdir -p images/$tag/$variant
      render_dockerfile_template $variant > images/$tag/$variant/Dockerfile
    done
  fi
done

render_readme_template > images/README.md
