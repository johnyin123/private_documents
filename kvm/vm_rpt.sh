#!/usr/bin/env bash
fname=${1:? must input}
amdvcpu=$(awk -F, '/AMD64/{sum+=$8} END{print sum;} ' ${fname})
amdvmem=$(awk -F, '/AMD64/{sum+=$9} END{print sum;} ' ${fname})
armvcpu=$(awk -F, '/ARM64/{sum+=$8} END{print sum;} ' ${fname})
armvmem=$(awk -F, '/ARM64/{sum+=$9} END{print sum;} ' ${fname})
AMDCPU=$(awk -F, '{print $1 $2 $4}' ${fname} | sort | uniq | awk -F'|' '/AMD64/{sum+=$3} END{print sum;} ' ${fname})
AMDMEM=$(awk -F, '{print $1 $2 $4}' ${fname} | sort | uniq | awk -F'|' '/AMD64/{sum+=$4} END{print sum;} ' ${fname})
ARMCPU=$(awk -F, '{print $1 $2 $4}' ${fname} | sort | uniq | awk -F'|' '/ARM64/{sum+=$3} END{print sum;} ' ${fname})
ARMMEM=$(awk -F, '{print $1 $2 $4}' ${fname} | sort | uniq | awk -F'|' '/ARM64/{sum+=$4} END{print sum;} ' ${fname})
printf "X86物理机CPU    : %10d 内存G: %10d\n" "${AMDCPU}" "${AMDMEM}"
printf "X86虚拟机CPU    : %10d 内存G: %10d\n" "${amdvcpu}" "${amdvmem}"
printf "                : %9d%%        %9d%%\n" "$((${amdvcpu}*100/${AMDCPU}))" "$((${amdvmem}*100/${AMDMEM}))"
printf "##############################################\n"
printf "ARM物理机CPU    : %10d 内存G: %10d\n" "${ARMCPU}" "${ARMMEM}"
printf "ARM虚拟机CPU    : %10d 内存G: %10d\n" "${armvcpu}" "${armvmem}"
printf "                : %9d%%        %9d%%\n" "$((${armvcpu}*100/${ARMCPU}))" "$((${armvmem}*100/${ARMMEM}))"
printf "##############################################\n"
printf "物理机IP        :      虚拟机数量\n"
for key in $(tail -n +2 ${fname} | awk -F, '{print $2}' | sort -t. -k 3,3n -k 4,4n | uniq); do
    printf "%-15s : %10d\n" "${key}" $(grep ",${key}," ${fname} | wc -l)
done

