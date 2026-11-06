def block($info): ("`" * ([([scan("`+") | length] | max // 0) + 1, 3] | max)) as $fence
  | $fence + $info + "\n" + . + "\n" + $fence;
"# issue",
"",
"## title",
"",
(.title | block("text")),
"",
"## body",
"",
(.body | block("markdown")),
(.comments[] | "", "## comment by \(.author.login) at \(.createdAt)", "", (.body | block("markdown")))
