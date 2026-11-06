"# " + (.title | gsub("\r?\n"; " ")),
"----- body -----",
(.body | gsub("(?m)^-----"; "\\-----")),
(.comments[] | "----- comment by \(.author.login) at \(.createdAt) -----", (.body | gsub("(?m)^-----"; "\\-----")))
