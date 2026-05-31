#!/usr/bin/env python3
"""Format high-signal feed entries with content enrichment for feed-index.sh.

Reads JSONL entries from stdin (all entries for one feed, pre-filtered).
Outputs formatted markdown suitable for the intelligence digest.

Usage:
    jq -c 'select(.feed == "cc-changelog")' feed-log.jsonl |
        python3 feed-format-enriched.py <summaries_jsonl_path> [max_entries]

Content priority per entry:
    1. summary field  (>50 chars) → strip HTML
    2. content field              → strip HTML
    3. feed-summaries.jsonl lookup by link (for anthropic-news)
    4. title-only fallback

Output format (per entry):
    ### YYYY-MM-DD — [Title](link)
    Stripped content or LLM summary (≤450 chars, one paragraph).
    [blank line]
"""

import sys
import json
import re
from html.parser import HTMLParser


class HtmlStripper(HTMLParser):
    SKIP_TAGS = frozenset({'script', 'style', 'nav', 'header', 'footer',
                           'noscript', 'meta', 'link', 'aside', 'form'})

    def __init__(self):
        super().__init__()
        self._parts = []
        self._depth = 0

    def handle_starttag(self, tag, attrs):
        if tag.lower() in self.SKIP_TAGS:
            self._depth += 1

    def handle_endtag(self, tag):
        if tag.lower() in self.SKIP_TAGS and self._depth > 0:
            self._depth -= 1

    def handle_data(self, data):
        if self._depth == 0:
            self._parts.append(data)


def strip_html(text: str, max_chars: int = 450) -> str:
    p = HtmlStripper()
    p.feed(text)
    result = ' '.join(p._parts)
    result = re.sub(r'\s+', ' ', result).strip()
    if len(result) > max_chars:
        result = result[:max_chars].rsplit(' ', 1)[0] + ' …'
    return result


def load_summaries(path: str) -> dict:
    summaries = {}
    if not path:
        return summaries
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    e = json.loads(line)
                    if e.get('link') and e.get('summary'):
                        summaries[e['link']] = e['summary']
                except json.JSONDecodeError:
                    pass
    except FileNotFoundError:
        pass
    return summaries


def main():
    summaries_path = sys.argv[1] if len(sys.argv) > 1 else ''
    max_entries = int(sys.argv[2]) if len(sys.argv) > 2 else 10

    summaries = load_summaries(summaries_path)

    entries = []
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            pass

    # Sort ascending by date, take last N
    entries.sort(key=lambda e: (e.get('published') or e.get('polled_at') or ''))
    entries = entries[-max_entries:]

    for e in entries:
        date = (e.get('published') or e.get('polled_at') or '')[:10]
        title = re.sub(r'[\n\r]+', ' ', e.get('title') or '').strip()
        link = e.get('link') or ''

        # Content priority
        body = ''
        field_summary = e.get('summary') or ''
        field_content = e.get('content') or ''

        # Treat summary as real content only if it differs from the title
        # (some RSS feeds echo the title in the summary field)
        summary_is_real = len(field_summary) > 50 and field_summary.strip() != title.strip()

        if summary_is_real:
            body = strip_html(field_summary)
        elif field_content:
            body = strip_html(field_content)
        elif link in summaries:
            raw = summaries[link]
            body = raw[:450].rsplit(' ', 1)[0] + ' …' if len(raw) > 450 else raw

        print(f'### {date} — [{title}]({link})')
        if body:
            print(body)
        print()


if __name__ == '__main__':
    main()
