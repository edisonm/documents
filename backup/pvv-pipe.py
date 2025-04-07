#!/usr/bin/env python3
import sys
import argparse
from tqdm import tqdm

def main():
    parser = argparse.ArgumentParser(description="Pipe progress with offset using tqdm")
    parser.add_argument(
        "-s", "--size", type=int, required=True,
        help="Total number of bytes to process (same as pv -s)"
    )
    parser.add_argument(
        "--offset", type=int, default=0,
        help="Initial bytes already processed (starts progress from this value)"
    )
    parser.add_argument(
        "--chunk", type=int, default=1048576,
        help="Chunk size for reading/writing (default: 1048576)"
    )
    parser.add_argument(
        "--desc", type=str, default="Progress",
        help="Label to show on the progress bar"
    )
    args = parser.parse_args()

    pbar = tqdm(
        total=args.size,
        initial=args.offset,
        unit='B',
        unit_scale=True,
        unit_divisor=1024,
        dynamic_ncols=True,
        bar_format='{l_bar}{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}, {rate_fmt}]',
        desc=args.desc
    )

    try:
        while True:
            chunk = sys.stdin.buffer.read(args.chunk)
            if not chunk:
                break
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            pbar.update(len(chunk))
    except KeyboardInterrupt:
        pass
    finally:
        pbar.close()

if __name__ == "__main__":
    main()
