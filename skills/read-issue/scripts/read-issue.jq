def block: ([([scan("`+") | length] | max // 0) + 1, 3] | max) as $k
  | ([range($k)] | map("`") | add) as $fence
  | $fence + "markdown\n" + . + "\n" + $fence;
"# " + (.title | gsub("\r\n|\r|\n"; " ")),
"",
"## body",
"",
(.body | block),
(.comments[] | "", "## comment by \(.author.login) at \(.createdAt)", "", (.body | block))
