count=10
folder=""

while getopts f:c: flag
do
    case "${flag}" in
        c) count=${OPTARG};;
        f) folder=${OPTARG};;
    esac
done

mkdir -p $folder

for i in $(seq 1 $count);
do
    echo $i
    j=$((i + 1000))
    adb shell screencap -p "$folder/$j.png"
#    sleep .5
done