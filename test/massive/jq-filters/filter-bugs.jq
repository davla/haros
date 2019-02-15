select(
    (.queries | length > 0)
    and (.queries | any(.comment | contains("{publishers: OrderedSet(), topicNames: OrderedSet(), subscribers: OrderedSet()}")) | not)
    and (.queries | any(.rule == "user:match_topics"))
) | .queries |= [.[] | select(.rule | startswith("user:"))]
