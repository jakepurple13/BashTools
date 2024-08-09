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
    curl -o "$folder/$i.png" -L "https://picsum.photos/200"
    sleep .5
done