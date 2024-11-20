src=(		/sox/code		\
		/sox/chat		\
		/sox/cncf		\
		/sox/meta		\
		/sox/msft		\
		/sox/perf		\
		/sox/tool		\
		/sox/web3		\
		/sox/llms		\
		/sox/tutml		\
		/sox/mlperf		\
		/sox/mlperf		\
		/sox/nvidia		\
		/sox/google		\
		/sox/huggingface/hub/server
)
for gg in "${src[@]}"; do
	cd $gg
	for fd in $( ls -l | grep drwxr | awk '{print $9}' ) ; do
		cd $fd	 &>/dev/null
		echo -e "update" $(pwd)
		git pull &>/dev/null
		cd -	 &>/dev/null
	done
done
