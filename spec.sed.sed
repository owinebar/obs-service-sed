# i Start with pattern space
# p
/^Substitute=:/ {
  # i "Sub="
  # p
  s/^Substitute=:\s*/subeqk:/
  # i Replaced head with cont
  # p
  b rxquote
  : subeqk
  s~^(\S+)\s(\S.+)$~/^BuildRequires:.*\\s\1(\\s|$)/ s@(\\s)\1(\\s|$)@\\1\2\\2@g ; t \n~
  # i Constructed buildrequires
  # p
  # i ---
  b
}
# i Test 2
/^Substitute:/ {
  # i "Sub"
  # p
  s/^Substitute:\s*/subk:/
  # i Replaced head with cont
  # p
  b rxquote
  : subk
  s~^(\S+)\s*(\S.+)$~s@^BuildRequires:.*\\s\1(\\s.*|$)@BuildRequires: \2@ ; t \n~
  # i Constructed buildrequires
  # p
  # i ---
  b
}
# i Test 3
/^Ignore:/ {
  # i "Ignore"
  # p
  s/^Ignore:\s*/ignorek:/
  # i Replaced head with cont
  # p
  # i ---
  b rxquote
  : ignorek
  s~^(\S+)$~/^BuildRequires:.*\\s\1(\\s|$)/ d \n~
  # i Constructed buildrequires
  # p
  b
}
b
: rxquote
{
    h
    s/^([^:]+:).*/\1/
    x
    s/^([^:]+:)(.*)/\2/
    : rxquotenextchar

    t clearmatchsuccess1
    : clearmatchsuccess1
    s/^$//
    t returnquoted
    s@(.)@\1\n@
    s~^(\[|[@.?*()|+{}/\$\\])~\\\1~
    x
    G
    s/^([^\n]*)\n([^\n]*)\n/\1\2\n/
    h
    s/^([^\n]+)\n.*/\1/
    x
    s/^[^\n]+\n(.*)/\1/
    b rxquotenextchar

    : returnquoted
    x
    G
    s/^([^\n]+)\n/\1/
    t clearmatchsuccess2
    : clearmatchsuccess2
    s/^subeqk://
    t subeqk
    s/^subk://
    t subk
    s/^ignorek://
    t ignorek
    i Unrecognized continuation
    p
    d
}
