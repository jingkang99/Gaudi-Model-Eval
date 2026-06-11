RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m'

readarray -t src < <(ls -1d */)
#echo "${src[@]}"
echo "${#src[@]}"

pwd=`pwd`

for gg in "${src[@]}"; do
	echo -e ${YLW}$gg${NCL}
	cd $gg
	for fd in $( ls -l | grep drwxr | awk '{print $9}' ) ; do
		cd $fd	 &>/dev/null
		printf "checking %50s\t" $(pwd)
		git pull > /tmp/__gitpull 2>&1

		grep 'Already up to date' /tmp/__gitpull &>/dev/null  && echo 'checked' || echo -e "${BCY}UPDATED${NCL}" 
		cd - &>/dev/null
	done
	cd $pwd
done
