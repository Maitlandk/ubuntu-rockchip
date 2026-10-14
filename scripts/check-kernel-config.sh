#!/bin/bash
#
# Check a kernel .config against one or more requirement profiles.
#
#   usage: check-kernel-config.sh <kernel .config> <profile>...
#
# A profile lists one requirement per line:
#
#   CONFIG_SYMBOL   level   # why it is needed
#
# where level is
#
#   builtin    must be =y
#   required   must be =y or =m
#   optional   reported, never fails the check
#
# A symbol that does not appear in the .config at all is reported as
# "absent": it does not exist in that kernel (renamed, removed, or a typo
# in the profile). That is a failure for builtin/required symbols, because
# guessing is worse than looking.
#
# Exit status: 0 all builtin/required met, 1 something unmet, 2 usage error.
#
# Under GitHub Actions the results are also published where they can be read
# without signing in to GitHub: each unmet requirement as an ::error
# annotation, and the whole table as one ::notice annotation. Annotations are
# served by the check-runs API; job logs are not (see CLAUDE.md). A markdown
# table also goes to $GITHUB_STEP_SUMMARY for people looking at the web UI.

set -euo pipefail

if [ "$#" -lt 2 ]; then
	echo "usage: $0 <kernel .config> <profile>..." >&2
	exit 2
fi

# Workflow-command escaping, per GitHub's toolkit: the message escapes
# % CR LF, properties (title=...) additionally escape : and ,
gh_data() {
	local s=${1//%/%25}
	s=${s//$'\r'/%0D}
	printf '%s' "${s//$'\n'/%0A}"
}

gh_prop() {
	local s
	s=$(gh_data "$1")
	s=${s//:/%3A}
	printf '%s' "${s//,/%2C}"
}

config=$1
shift

declare -A have
while IFS= read -r line; do
	case $line in
	CONFIG_*=*)
		have[${line%%=*}]=${line#*=}
		;;
	"# CONFIG_"*" is not set")
		line=${line#\# }
		have[${line%% *}]=n
		;;
	esac
done < "$config"

summary=${GITHUB_STEP_SUMMARY:-/dev/null}
unmet=0
total=0
report=

printf '| Profile | Symbol | Level | Value | Status | Why |\n' >> "$summary"
printf '|---|---|---|---|---|---|\n' >> "$summary"

for profile in "$@"; do
	name=$(basename "$profile" .txt)
	printf '\n== %s ==\n' "$name"
	printf '%-40s %-9s %-6s %s\n' SYMBOL LEVEL VALUE STATUS
	report+="== $name =="$'\n'

	while read -r sym level why; do
		case $sym in
		'' | \#*) continue ;;
		esac

		why=${why#\#}
		why=${why# }
		val=${have[$sym]:-absent}

		case $level:$val in
		builtin:y | required:y | required:m | optional:y | optional:m)
			status=ok
			;;
		optional:*)
			status=missing
			;;
		builtin:* | required:*)
			status=UNMET
			unmet=$((unmet + 1))
			if [ -n "${GITHUB_ACTIONS:-}" ]; then
				echo "::error title=$(gh_prop "$name $sym")::$(gh_data "$sym is '$val', needs $level. $why")"
			fi
			;;
		*)
			echo "$profile: unknown level '$level' for $sym" >&2
			exit 2
			;;
		esac

		total=$((total + 1))
		line=$(printf '%-7s %-36s %-6s %s' "$status" "$sym" "$val" "$level")
		echo "$line"
		report+="$line"$'\n'
		printf '| %s | `%s` | %s | %s | %s | %s |\n' \
			"$name" "$sym" "$level" "$val" "$status" "$why" >> "$summary"
	done < "$profile"
done

result="$total symbols checked, $unmet builtin/required unmet"
printf '\n%s\n' "$result"

if [ -n "${GITHUB_ACTIONS:-}" ]; then
	echo "::notice title=$(gh_prop "kernel config: $result")::$(gh_data "$report")"
fi

[ "$unmet" -eq 0 ]
