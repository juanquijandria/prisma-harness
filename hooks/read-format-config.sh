#!/bin/sh
# Prisma Harness. Reads the format configuration as data, documented in README.md, section "What is inside".

FORMAT_CONFIG_FLAGS="RULE_KEBAB_CASE RULE_H1_FIRST_LINE RULE_EM_DASH RULE_COLON_IN_PROSE RULE_HEADING_COUNTS RULE_VOSEO RULE_SOURCES_FOOTER RULE_WIKILINKS RULE_VERIFY_TAG RULE_RATE_SECOND_READING"
FORMAT_CONFIG_NUMBERS="RULE_LINE_CEILING RATE_CELLS_FLOOR"
FORMAT_CONFIG_LISTS="EXEMPT_NAMES EXEMPT_DIRS RATE_EXEMPT_DIRS"
FORMAT_CONFIG_CARRIAGE_RETURN=$(printf '\r')
FORMAT_CONFIG_TAB=$(printf '\t')

format_config_reject() {
  printf 'WARN: %s line %s ignored, %s.\n' "$1" "$2" "$3" >&2
}

format_config_kind() {
  for known in $FORMAT_CONFIG_FLAGS; do [ "$1" = "$known" ] && { printf flag; return 0; }; done
  for known in $FORMAT_CONFIG_NUMBERS; do [ "$1" = "$known" ] && { printf number; return 0; }; done
  for known in $FORMAT_CONFIG_LISTS; do [ "$1" = "$known" ] && { printf list; return 0; }; done
  return 1
}

format_config_wants() {
  case "$1" in
    flag) printf '0 or 1' ;;
    number) printf 'a whole number of at most nine digits and no leading zero' ;;
    list) printf 'names separated by spaces' ;;
  esac
}

format_config_accepts() {
  case "$1" in
    flag) printf '%s' "$2" | grep -q '^[01]$' ;;
    number) printf '%s' "$2" | grep -qE '^(0|[1-9][0-9]{0,8})$' ;;
    list) printf '%s' "$2" | grep -q '^[A-Za-z0-9._ -]*$' ;;
    *) return 1 ;;
  esac
}

read_format_config() {
  file="$1"
  [ -f "$file" ] || return 0
  number=0
  while IFS= read -r line || [ -n "$line" ]; do
    number=$((number+1))
    line=${line%"$FORMAT_CONFIG_CARRIAGE_RETURN"}
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in *=*) ;; *) format_config_reject "$file" "$number" "it is neither a comment nor a setting"; continue ;; esac
    key=${line%%=*}
    value=${line#*=}
    case "$value" in
      \"*) value=${value#\"}; value=${value%%\"*} ;;
      \'*) value=${value#\'}; value=${value%%\'*} ;;
      *) value=${value%% #*}; value=${value%%"$FORMAT_CONFIG_TAB"#*} ;;
    esac
    kind=$(format_config_kind "$key") || { format_config_reject "$file" "$number" "$key is not a setting this gate has"; continue; }
    format_config_accepts "$kind" "$value" || { format_config_reject "$file" "$number" "$key takes $(format_config_wants "$kind")"; continue; }
    eval "$key=\$value"
  done < "$file"
  return 0
}
