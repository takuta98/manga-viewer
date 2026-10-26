#!/usr/bin/env python3
"""Mirror of SpreadIndex RTL rules for Linux CI without Xcode."""

from __future__ import annotations


def spread_count(page_count: int) -> int:
    return max((page_count + 1) // 2, 1)


def pages(spread_index: int, page_names: list[str], direction: str = "rtl"):
    page_count = len(page_names)
    clamped = max(0, min(spread_index, spread_count(page_count) - 1))
    if direction == "rtl":
        right_num = clamped * 2 + 1
        left_num = clamped * 2 + 2
        return {
            "left": page_names[left_num - 1] if left_num <= page_count else None,
            "right": page_names[right_num - 1] if right_num <= page_count else None,
            "left_num": left_num if left_num <= page_count else None,
            "right_num": right_num if right_num <= page_count else None,
        }
    left_num = clamped * 2 + 1
    right_num = clamped * 2 + 2
    return {
        "left": page_names[left_num - 1] if left_num <= page_count else None,
        "right": page_names[right_num - 1] if right_num <= page_count else None,
        "left_num": left_num if left_num <= page_count else None,
        "right_num": right_num if right_num <= page_count else None,
    }


def main() -> None:
    names = [f"night-station-{i:03d}" for i in range(1, 17)]
    assert spread_count(16) == 8
    first = pages(0, names, "rtl")
    assert first["right_num"] == 1 and first["left_num"] == 2
    second = pages(1, names, "rtl")
    assert second["right_num"] == 3 and second["left_num"] == 4
    odd = pages(7, names[:15], "rtl")
    assert odd["right_num"] == 15 and odd["left"] is None
    print("verify_spread_index.py: ok")


if __name__ == "__main__":
    main()
