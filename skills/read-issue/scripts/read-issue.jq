def esc: gsub("(?m)^(?<x>\\\\*-----)"; "\\\(.x)");
"# " + (.title | gsub("\r?\n"; " ")),
"----- body -----",
(.body | esc),
(.comments[] | "----- comment by \(.author.login) at \(.createdAt) -----", (.body | esc))
