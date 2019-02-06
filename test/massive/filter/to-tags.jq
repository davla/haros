select((.total > 0) and (.launch > 0))
    | .package
    | (.name | gsub("/"; "--")) + "-" + .hash
