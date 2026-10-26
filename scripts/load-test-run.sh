#!/usr/bin/env bash
# Timeline load test (read-only): the summary, then the newest, busiest and
# quietest 7-day pages, per Contact and window, with the limits each used.
# Usage: scripts/load-test-run.sh <org> <contactId> <label> <history> <future>
set -euo pipefail
ORG=$1 CONTACT=$2 LABEL=$3 HISTORY=$4 FUTURE=$5
SCRIPT=scripts/apex/load-test-measure.apex
RUN=.sfdx/tmp/load-measure-run.apex

measure() { # mode keys
  sed -e "s/__CONTACT__/$CONTACT/" -e "s/__MODE__/$1/" -e "s/__KEYS__/$2/" \
    -e "s/'2', '1'/'$HISTORY', '$FUTURE'/g" "$SCRIPT" > "$RUN"
  sf apex run --file "$RUN" --target-org "$ORG" --json 2>/dev/null | jq -r '
    (.result | select(.success != true) | "FAILED \(.compileProblem) \(.exceptionMessage)"),
    ((.result.logs // "") | split("\n")[]
      | select(test("USER_DEBUG|couldn.t be counted"))
      | sub(".*\\|DEBUG\\|"; "") | sub(".*\\|WARN\\|"; "WARN ") | gsub("&#124;"; "|"))'
}
quote() { echo "$1" | sed "s/,/','/g; s/^/'/; s/$/'/"; }

echo "##### $LABEL (history $HISTORY, future $FUTURE)"
out=$(measure summary "")
echo "$out" | grep -v KEYS_ | sed 's/^/summary      /'
for k in NEWEST BUSY QUIET; do
  keys=$(echo "$out" | grep "KEYS_$k" | sed "s/KEYS_$k //" || true)
  [ -z "$keys" ] && continue
  measure days "$(quote "$keys")" | grep -v KEYS_ | sed "s/^/page-$k  /"
done
