select(
    (.queries | length > 0)
    and (.queries | any(.comment | contains("{publishers: OrderedSet(), topicNames: OrderedSet(), subscribers: OrderedSet()}")))
) | .queries |= [.[] | select(.rule | startswith("user:"))]
