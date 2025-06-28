# 脚本会传入一个参数，表示字典文件的位置，例如这里的 wanxiang_radical.dict.yaml
# 对应的 YAML 文件中的非 YAML 部分即为字典文件，字典文件为键值对的形式，并用 tab 分割
# 此脚本将去除键重复的行，并按照文字的 Unicode 编码排序

import sys
import os
import tempfile
import shutil
import re


def clean_dict_file(dict_file_path):
    with open(dict_file_path, "r", encoding="utf-8") as f:
        tmp_fd, tmp_file_path = tempfile.mkstemp()

        lines = []
        is_dict_line = False
        while True:
            line = f.readline()
            if not line:
                break

            if line.strip() == "...":
                is_dict_line = True
                os.write(tmp_fd, line.encode("utf-8"))
                continue

            if not is_dict_line:
                os.write(tmp_fd, line.encode("utf-8"))
                continue

            line = re.sub(r"\t\d*$", "", line)
            if line in lines: 
                continue

            lines.append(line)
            os.write(tmp_fd, line.encode("utf-8"))

        os.close(tmp_fd)
        root, extension = os.path.splitext(dict_file_path)
        shutil.move(tmp_file_path, f'{root}.dedup.{extension}')


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python clean_dict.py <dict_file>")
        sys.exit(1)
    clean_dict_file(sys.argv[1])
