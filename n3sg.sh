#!/bin/sh

start=$(date +%s.%N)

# jekyll-cache is cached by netlify plugin
mkdir -p .jekyll-cache

## lowdown
if [ ! -f .jekyll-cache/lowdown ]; then
  wget https://kristaps.bsd.lv/lowdown/snapshots/lowdown.tar.gz
  tar xf lowdown.tar.gz
  cd lowdown-*
  ./configure
  make
  cp lowdown ../.jekyll-cache
  cd ..
fi

PATH=".jekyll-cache:$PATH"

markdown() {
  tail -n +$(($(sed -n '/---/,/---/p' $1 | wc -l)+1)) $1 | \
    lowdown --html-no-skiphtml --html-no-escapehtml
}

usage() {
  echo "n3sg - Netlify Simple Static Site Generator"
  echo "Usage:"
  echo "    ./n3sg.sh src dest site_name site_url"
  exit 1
}

test -n "$1" || usage
test -n "$2" || usage
test -n "$3" || usage
test -n "$4" || usage

src="$1"
dst="$2"
title="$3"
url="$4"

rm -r $dst || true
mkdir -p $dst

echo "Building..."

## Bootstrap directory structure from $src into $dst
for f in `cd $src && find . -type d ! -name '.' ! -path '*/_*'`; do
  mkdir -p "$dst/$f"
done

## Copy non-markdown files
for f in `cd $src && find . -type f ! -name '*.md' ! -name 'index.md' ! -name '.' ! -path './_*'`; do
  echo "C $f"
  cp $src/$f $dst/$f
done

## For all markdown files
for f in `cd $src && find . -type f -name '*.md' ! -name 'index.md' ! -path './kronika*'`; do

  echo "> $f"
  page=${f%\.*}
  ## HTML
  cat $src/_header.html > $dst/$page.html
  echo "<div class=\"content\">" >> $dst/$page.html
  markdown $src/$f >> $dst/$page.html
  echo "</div>" >> $dst/$page.html
  cat $src/_footer.html >> $dst/$page.html

done


## Index page generation
cat $src/_header.html > $dst/index.html
[ -f $src/index.md ] && markdown $src/index.md >> $dst/index.html
echo "<div class=\"content post-list\">" >> $dst/index.html

## RSS generation
cat > $dst/rss.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
<atom:link href="$url/rss.xml" rel="self" type="application/rss+xml" />
<title>$title</title>
<description></description>
<link>$url</link>
<lastBuildDate>$(date -R)</lastBuildDate>
EOF

## For markdown files in `kronika`
for f in `cd $src && find . -type f -wholename './kronika/*.md' ! -name 'index.md' ! -name '.' ! -path '*/_*' | sort -r`; do

  echo ">> $f"

  ## Meta extraction
  title=`sed -n '/---/,/---/p' $src/$f | grep title | cut -d':' -f2`
  author=`sed -n '/---/,/---/p' $src/$f | grep author | cut -d':' -f2`
  photo=`grep "!\[.*\]\(.*\)" $src/$f | head -n 1 | cut -d "(" -f2 | cut -d ")" -f1`
  if ! echo $photo | grep "^http" > /dev/null; then
    [ -z $photo ] && photo="/assets/default_tree.jpg"
    [ ! -f $dst/$photo ] && photo="$(dirname $f)/$photo"
  fi
  description=`grep -E "^[A-Z]" $src/$f | grep -v "|" | head -n 1 | cut -d" " -f1-30`
  date=`git log -n 1 --date="format:%d-%m-%Y %H:%M:%SZ" --pretty=format:%ad -- $src/$f`
  page=${f%\.*}

  ## HTML
  cat $src/_header.html > $dst/$page.html
  echo "<article class=\"kronika\">" >> $dst/$page.html
  markdown $src/$f >> $dst/$page.html
  echo "</article>" >> $dst/$page.html
  cat $src/_footer.html >> $dst/$page.html

  ## Add to index
  cat >> $dst/index.html << EOF
<div class="post-link">
  <a href="$page.html">
    <div>
      <div class="image" style="background-image: url('$photo')"></div>
      <div class="post-container">
        <h4 class="post-title">$title</h4>
        <p class="post-description">$description</p>
      </div>
    </div>
  </a>
</div>
EOF

  ## Add to rss
  cat >> $dst/rss.xml << EOF
<item>
  <guid>$page</guid>
  <link>$url/$page.html</link>
  <pubDate>$date</pubDate>
  <title>$title</title>
  <description><![CDATA[
EOF
  markdown $src/$f >> $dst/rss.xml
  cat >> $dst/rss.xml << EOF
  ]]></description>
</item>
EOF
done

## Close tags
echo "</div>" >> $dst/index.html
cat $src/_footer.html >> $dst/index.html
echo "</channel></rss>" >> $dst/rss.xml

duration=$(echo "$(date +%s.%N) - $start" | bc)
execution_time=`printf "%.2f seconds" $duration`
echo "Done! [$execution_time]"
