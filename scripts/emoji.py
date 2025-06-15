import requests
from pathlib import Path

# 下载上游 emoji-map.txt
upstream_emoji_map_url = "https://raw.githubusercontent.com/iDvel/rime-ice/refs/heads/main/others/emoji-map.txt"
root_path = Path(__file__).parent.parent
local_emoji_map_path = root_path / "scripts/emoji-map.txt"
local_emoji_order_path = root_path / "scripts/emoji-order.txt"
opencc_emoji_txt_path = root_path / "opencc/emoji.txt"
tips_txt_path = root_path / "lua/tips/tips_show.txt"

# TODO: 实现 tips key 重复时按照优先级去重

def main():
    emoji_words_dict = get_emoji_words_dict(
        upstream_emoji_map_url, local_emoji_map_path
    )

    # word_emoji_dict = get_word_emojis_dict(emoji_words_dict)
    # emoji_dict = {}
    # for word, emojis in word_emoji_dict.items():
    #     # if len(emojis) > 1:
    #     #     print(f"{word},{' '.join(emojis)}")
    #     for emoji in emojis:
    #         if emoji not in emoji_dict:
    #             emoji_dict[emoji] = []
    #         emoji_dict[emoji].append(word)
    # for emoji, words in emoji_dict.items():
    #     print(f"{emoji},{' | '.join(words)}")

    update_opencc_txt(opencc_emoji_txt_path, emoji_words_dict)
    update_tips(tips_txt_path, emoji_words_dict)

    print(f"已生成 {opencc_emoji_txt_path}")


def get_emoji_words_dict(upstream_emoji_map_url, local_emoji_map_path):
    upstream = requests.get(upstream_emoji_map_url).text

    # 读取本地 emoji-map.txt
    local = ""
    if local_emoji_map_path.exists():
        with open(local_emoji_map_path, encoding="utf-8") as f:
            local = f.read()

    # 合并并去重
    emoji_words_dict = {}
    for content in [upstream, local]:
        for line in content.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            emoji, words = line.split(maxsplit=1)
            if emoji not in emoji_words_dict:
                emoji_words_dict[emoji] = []

            current_words = words.split()

            existing_words_filter = lambda w: w not in [
                x.lstrip("-")
                for x in filter(lambda w: w.startswith("-"), current_words)
            ]
            filtered_existing_words = list(
                filter(existing_words_filter, emoji_words_dict[emoji])
            )

            current_words_filter = lambda w: w not in emoji_words_dict[
                emoji
            ] and not w.startswith("-")
            current_words = list(filter(current_words_filter, current_words))

            emoji_words_dict[emoji] = filtered_existing_words + current_words

    return emoji_words_dict


def sort_by_ordered_list(list_to_sort, ordered_list):
    # Create a dictionary mapping elements to their indices in the ordered list
    order_map = {item: index for index, item in enumerate(ordered_list)}

    # Sort the list using the dictionary mapping
    list_to_sort.sort(key=lambda item: order_map.get(item, float("inf")))

    return list_to_sort


def get_word_emojis_dict(emoji_words_dict):
    word_emojis_dict = {}
    for emoji in emoji_words_dict.keys():
        words = emoji_words_dict[emoji]
        for word in words:
            if word not in word_emojis_dict:
                word_emojis_dict[word] = []
            word_emojis_dict[word].append(emoji)

    # 排序
    emoji_order_lines = set()
    if local_emoji_order_path.exists():
        is_valid_line = lambda l: not (l.startswith("#") or len(l.strip()) == 0)
        with open(local_emoji_order_path, encoding="utf-8") as f:
            valid_lines = filter(is_valid_line, f.readlines())
            emoji_order_lines.update(valid_lines)

    for line in emoji_order_lines:
        word, emojis = line.split(maxsplit=1)
        word_emojis_dict[word] = sort_by_ordered_list(word_emojis_dict[word], emojis)

    return word_emojis_dict


def update_opencc_txt(opencc_emoji_txt_path, emoji_words_dict):
    word_emojis_dict = get_word_emojis_dict(emoji_words_dict)

    # 生成 emoji.txt 格式
    opencc_lines = []
    # 先按照 emoji 排序，然后按 word
    for word, emojis in sorted(
        word_emojis_dict.items(), key=lambda x: f"{x[1][0]} {x[0]}"
    ):
        opencc_lines.append(f"{word}\t{word} {' '.join(emojis)}\n")

    # 写入 emoji.txt
    with open(opencc_emoji_txt_path, "w", encoding="utf-8") as f:
        f.writelines(opencc_lines)


# 写入 tips
def update_tips(tips_txt_path, emoji_words_dict):
    word_emojis_dict = get_word_emojis_dict(emoji_words_dict)

    with open(tips_txt_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    new_tips_lines = []
    exist_tips_words = set()
    for line in lines:
        is_emoji_line = line.startswith("表情：")
        if not is_emoji_line:
            new_tips_lines.append(line)
            exist_tips_words.add(line.split()[-1])

    # 表情：🍉	西瓜
    tips_txt_lines = []
    # 先按照 emoji 排序，然后按 word
    for word, emojis in sorted(
        word_emojis_dict.items(), key=lambda x: f"{x[1][0]} {x[0]}"
    ):
        # 如果在 tips 中已经有其他项目关联此 word，则忽略该 emoji
        if word in exist_tips_words:
            continue
        # 只取首个匹配的emoji，重复的在 tips 中也匹配不上
        prefer_emoji = emojis[0]
        tips_txt_lines.append(f"表情：{prefer_emoji}\t{word}\n")

    new_tips_lines += tips_txt_lines
    with open(tips_txt_path, "w", encoding="utf-8") as f:
        f.writelines(sorted(new_tips_lines))


if __name__ == "__main__":
    main()
