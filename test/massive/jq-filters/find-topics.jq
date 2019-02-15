select(
    (.queries | length > 0)
    and (.queries | any(.comment == "Query found: {publishers: OrderedSet(), topicNames: OrderedSet(), subscribers: OrderedSet()}") | not)
) | .queries |= [.[] | select(.rule == "user:topics")]
