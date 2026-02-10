#!/bin/bash
# Download a JS-rendered webpage as clean markdown
# Usage: bash command.sh <url> <output.md>
# Requires: pip install playwright beautifulsoup4 && playwright install chromium

URL="${1:?Usage: bash command.sh <url> <output.md>}"
OUT="${2:-output.md}"

python3 -c "
import sys
from playwright.sync_api import sync_playwright
from bs4 import BeautifulSoup

url = sys.argv[1]
with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page()
    page.goto(url)
    for selector in ['article', 'main', '[role=main]', 'h1']:
        try:
            page.wait_for_selector(selector, timeout=8000)
            break
        except:
            pass
    html = page.content()
    browser.close()

soup = BeautifulSoup(html, 'html.parser')
for tag in soup(['script', 'style', 'nav', 'footer', 'header', 'svg', 'noscript', 'button']):
    tag.decompose()
for tag in soup.find_all(True):
    kept = {}
    if tag.name == 'a' and tag.get('href'):
        kept['href'] = tag['href']
    if tag.name == 'img' and tag.get('src') and not tag['src'].startswith('data:'):
        kept['src'] = tag['src']
    tag.attrs = kept
for tag in soup.find_all(['div', 'span']):
    tag.unwrap()
main = soup.find('article') or soup.find('main') or soup.body
print(str(main))
" "$URL" | pandoc -f html -t markdown --wrap=none | cat -s > "$OUT"

echo "Saved to $OUT"
