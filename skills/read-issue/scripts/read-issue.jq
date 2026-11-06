"# " + .title,
"----- body -----",
(.body | gsub("(?m)^-----"; "\\-----")),
(.comments[] | "----- comment by \(.author.login) at \(.createdAt) -----", (.body | gsub("(?m)^-----"; "\\-----")))
