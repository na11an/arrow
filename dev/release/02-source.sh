#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
set -e

SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <version> <rc-num> <artifact_dir>"
  exit
fi

version=$1
rc=$2
artifact_dir=$3

if [ -d tmp/ ]; then
  echo "Cannot run: tmp/ exists"
  exit
fi

if [ -z "$artifact_dir" ]; then
  echo "artifact_dir is empty"
  exit 1
fi

if [ ! -e "$artifact_dir" ]; then
  echo "$artifact_dir does not exist"
  exit 1
fi

if [ ! -d "$artifact_dir" ]; then
  echo "$artifact_dir is not a directory"
  exit 1
fi

tag=apache-arrow-${version}
tagrc=${tag}-rc${rc}

echo "Preparing source for tag ${tag}"

release_hash=`git rev-list $tag 2> /dev/null | head -n 1 `

if [ -z "$release_hash" ]; then
  echo "Cannot continue: unknown git tag: $tag"
  exit
fi

echo "Using commit $release_hash"

tarball=${tag}.tar.gz

extract_dir=tmp-apache-arrow
rm -rf ${extract_dir}
# be conservative and use the release hash, even though git produces the same
# archive (identical hashes) using the scm tag
git archive ${release_hash} --prefix ${extract_dir}/ | tar xf -

# build Apache Arrow C++ before building Apache Arrow GLib because
# Apache Arrow GLib requires Apache Arrow C++.
mkdir -p ${extract_dir}/cpp/build
cpp_install_dir=${PWD}/${extract_dir}/cpp/install
cd ${extract_dir}/cpp/build
cmake .. \
  -DCMAKE_INSTALL_PREFIX=${cpp_install_dir} \
  -DCMAKE_INSTALL_LIBDIR=${cpp_install_dir}/lib \
  -DARROW_BUILD_TESTS=no
make -j8
make install
cd -

# build source archive for Apache Arrow GLib by "make dist".
cd ${extract_dir}/c_glib
./autogen.sh
./configure \
  PKG_CONFIG_PATH=$cpp_install_dir/lib/pkgconfig \
  --enable-gtk-doc
LD_LIBRARY_PATH=$cpp_install_dir/lib:$LD_LIBRARY_PATH make -j8
make dist
tar xzf *.tar.gz
rm *.tar.gz
cd -
rm -rf tmp-c_glib/
mv ${extract_dir}/c_glib/apache-arrow-glib-* tmp-c_glib/
rm -rf ${extract_dir}

# replace c_glib/ by tar.gz generated by "make dist"
rm -rf ${tag}
git archive $release_hash --prefix ${tag}/ | tar xf -
rm -rf ${tag}/c_glib
mv tmp-c_glib ${tag}/c_glib

# Create new tarball from modified source directory
tar czhf ${tarball} ${tag}
rm -rf ${tag}

${SOURCE_DIR}/run-rat.sh ${tarball}

# sign the archive
gpg --armor --output ${tarball}.asc --detach-sig ${tarball}
shasum -a 1 $tarball > ${tarball}.sha1
shasum -a 256 $tarball > ${tarball}.sha256

# check out the arrow RC folder
svn co --depth=empty https://dist.apache.org/repos/dist/dev/arrow tmp

# add the release candidate for the tag
mkdir -p tmp/${tagrc}/binaries

# copy the rc tarball into the tmp dir
cp ${tarball}* tmp/${tagrc}

# copy binary artifacts into a subdirectory of the rc dir
cp -rf "$artifact_dir"/* tmp/${tagrc}/binaries/

# commit to svn
svn add tmp/${tagrc}
svn ci -m 'Apache Arrow ${version} RC${rc}' tmp/${tagrc}

# clean up
rm -rf tmp

echo "Success! The release candidate is available here:"
echo "  https://dist.apache.org/repos/dist/dev/arrow/${tagrc}"
echo ""
echo "Commit SHA1: ${release_hash}"