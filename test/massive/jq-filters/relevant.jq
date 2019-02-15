select(
    (.total > 0) and (.launch > 0)
) | .package
| [.name, .url, .hash, .vcs] | join(" ")
