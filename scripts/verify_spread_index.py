#!/usr/bin/env python3

def pages(spread_index, page_count, direction='rtl', cover_alone=False, layout='spread'):
    if layout == 'single':
        return {'right': spread_index if direction=='rtl' else None, 'left': spread_index if direction=='ltr' else None}
    if cover_alone:
        if spread_index == 0:
            first, second = 0, None
        else:
            first = (spread_index - 1) * 2 + 1
            second = first + 1 if first + 1 < page_count else None
    else:
        first = spread_index * 2
        second = first + 1 if first + 1 < page_count else None
    if direction == 'rtl':
        return {'right': first, 'left': second}
    return {'left': first, 'right': second}

assert pages(0, 16)['right'] == 0 and pages(0, 16)['left'] == 1
assert pages(0, 16, cover_alone=True)['right'] == 0 and pages(0, 16, cover_alone=True)['left'] is None
assert pages(1, 16, cover_alone=True)['right'] == 1 and pages(1, 16, cover_alone=True)['left'] == 2
print('verify_spread_index.py: ok')
