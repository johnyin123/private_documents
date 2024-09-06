# # apt -y install bcache-tools
HDD=/dev/vdb
SSD=/dev/vdc
# echo /dev/ram0 > /sys/fs/bcache/register
# cache_set_uuid=$(cat /proc/sys/kernel/random/uuid)

# # Format the backing device (This will typically be your mechanical drive).
make-bcache --bdev ${HDD}
# # Format the cache device (This will typically be your SSD). --block 4k, sector size of SSD
make-bcache --block 512 --bucket 2M --cache ${SSD} #--cset-uuid 485ef315-a296-434c-8eb8-72c4945c93a2

cache_set_uuid=$(bcache-super-show ${SSD} | grep cset | awk '{ print $2 }')
echo ${cache_set_uuid} > /sys/block/bcache0/bcache/attach
# # Safely remove the cache device
echo ${cache_set_uuid} > /sys/block/bcache0/bcache/detach
# # Force flush of cache to backing device
echo 0 > /sys/block/bcache0/bcache/writeback_percent

cat /sys/block/bcache0/bcache/state
cat /sys/block/bcache0/bcache/cache_mode

mkfs /dev/bcache0
