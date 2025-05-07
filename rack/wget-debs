#echo $BASH_VERSION

VERN119=1.19.1-26
VERSION=1.20.1-97

REPOURL=https://vault.habana.ai/artifactory/debian/noble/pool/main/h

declare -A DEB

DEB["rdma-core"]="all"
DEB["habanalabs-dkms"]="all"
DEB["habanalabs-thunk"]="all"

DEB["habanalabs-firmware"]="amd64"
DEB["habanalabs-firmware-odm"]="amd64"
DEB["habanalabs-firmware-tools"]="amd64"

DEB["habanalabs-qual"]="amd64"
DEB["habanalabs-graph"]="amd64"

DEB["habanalabs-tools"]="amd64"
DEB["habanalabs-perf-test"]="amd64"
DEB["habanacontainerruntime"]="amd64"

DEB["habanalabs-qual-workloads"]="all"
DEB["habanalabs-hypervisor-msv"]="all"
DEB["habanalabs-hypervisor-utils"]="amd64"

#echo ${!DEB[@]}# key
#echo ${DEB[@]}	# val

mkdir -p $VERSION
cd $VERSION

SECONDS=0
for ddd in ${!DEB[@]}
do
	echo ${REPOURL}/${ddd}/${ddd}_${VERSION}_${DEB[$ddd]}.deb
	wget -q ${REPOURL}/${ddd}/${ddd}_${VERSION}_${DEB[$ddd]}.deb
done

for deb in *.deb
do
	echo -e "list $deb"
	dpkg --contents $deb > .z_${deb}-list.txt
done

cd -

echo -e "habana deb downloaded in ${SECONDS}"
