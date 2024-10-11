import argparse
import os
import time
import urllib.request
from urllib.error import HTTPError


def main():
    parser = argparse.ArgumentParser(description='Download images from Picsum.')
    parser.add_argument('-c', type=int, default=10, help='Number of images to download')
    parser.add_argument('-f', type=str, required=True, help='Folder to save images')

    args = parser.parse_args()

    count = args.c
    folder = args.f

    # Create the directory if it doesn't exist
    os.makedirs(folder, exist_ok=True)

    for i in range(1, count + 1):
        print(i)
        try:
            urllib.request.urlretrieve("https://picsum.photos/200", f"{folder}/{i}.png")
        except FileNotFoundError as err:
            print(err)  # something wrong with local path
        except HTTPError as err:
            print(err)  # something wrong with url

        time.sleep(0.5)


if __name__ == "__main__":
    main()
