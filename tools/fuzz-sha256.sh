#!/usr/bin/env bash
#
# Hash a pile of awkward inputs with ./sha256 and with the system sha256sum and
# complain about any disagreement.  Which of the block / word / byte / bulk-NUL
# / padding paths runs depends on where NUL bytes land, so this walks every
# length and NUL placement that changes the answer.
#
# Usage: tools/fuzz-sha256.sh [sha256-binary]
#
# License: MIT

set -u

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
sha256=${1:-./sha256}
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

checked=0
failed=0

check() {
	local file=$1 label=$2 want have have_arg have_debug have_single

	want=$(sha256sum < "$file" | cut -d' ' -f1)
	have=$("$sha256" < "$file")
	have_arg=$("$sha256" "$file")
	have_debug=$(DEBUG=1 "$sha256" < "$file" 2>/dev/null)
	have_single=$(SHA256_PROCS=1 "$sha256" < "$file")

	((checked++))

	if [[ $want != "$have" || $want != "$have_arg" ||
		$want != "$have_debug" || $want != "$have_single" ]]; then
		echo "FAIL $label"
		echo "  want    $want"
		echo "  stdin   $have"
		echo "  arg     $have_arg"
		echo "  debug   $have_debug"
		echo "  1-proc  $have_single"
		((failed++))
	fi
}

nonul() {
	# Read from an unbounded stream so we always produce exactly $1 non-NUL bytes.
	tr -d '\000' < /dev/urandom | head -c "$1"
}

echo 'lengths 0..200 and the block/chunk boundaries...'
for n in $(seq 0 200) 254 255 256 511 512 513 575 576 577 1023 1024 1025 \
	4095 4096 4097 5000; do
	head -c "$n" /dev/zero > "$tmp/f"
	check "$tmp/f" "zeros($n)"

	nonul "$n" > "$tmp/f"
	check "$tmp/f" "no-nul($n)"

	head -c "$n" /dev/urandom > "$tmp/f"
	check "$tmp/f" "random($n)"

	# NUL-dense but not all NUL
	head -c "$n" /dev/urandom | tr 'a-zA-Z0-9' '\000' > "$tmp/f"
	check "$tmp/f" "nul-dense($n)"
done

echo 'NUL runs at every awkward offset...'
for prefix in 0 1 2 3 61 62 63 64 65 127; do
	for run in 1 2 3 4 63 64 65 128 129; do
		{
			nonul "$prefix"
			head -c "$run" /dev/zero
			nonul 70
		} > "$tmp/f"
		check "$tmp/f" "prefix=$prefix run=$run"
	done
done

echo 'every byte value, including bash CTLESC (0x01) and CTLNUL (0x7f)...'
for ((v = 0; v < 256; v++)); do
	if ((v == 0)); then
		# a command substitution would swallow these
		head -c 300 /dev/zero > "$tmp/f"
	else
		printf -v byte '\\x%02x' "$v"
		printf "$byte%.0s" {1..300} > "$tmp/f"
	fi
	check "$tmp/f" "300 x byte $v"
done

for ((v = 0; v < 256; v++)); do printf "\\x$(printf %02x "$v")"; done > "$tmp/all"
check "$tmp/all" 'all 256 byte values'
for _ in {1..40}; do cat "$tmp/all"; done > "$tmp/f"
check "$tmp/f" 'all 256 byte values x40'

echo 'a large random file...'
head -c 200000 /dev/urandom > "$tmp/f"
check "$tmp/f" 'random 200k'

echo
echo "checked $checked inputs, $failed failed"
((failed == 0))
