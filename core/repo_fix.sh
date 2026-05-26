#!/usr/bin/env bash
# ==============================
# TDOC — repo_fix.sh
# Entrypoint for: tdoc repo-fix [--auto] [--preview]
# Reads ~/.tdoc/repo_fix_state.env written by repo-scan,
# runs appropriate fix handler for each issue found.
# ==============================

: "${TDOC_ROOT:?TDOC_ROOT is not set}"
source "$TDOC_ROOT/core/ui.sh"
source "$TDOC_ROOT/core/i18n.sh"
source "$TDOC_ROOT/core/fix_repo.sh"
load_lang

REPO_FIX_STATE="${HOME}/.tdoc/repo_fix_state.env"
BORDER="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

MODE="${1:-}"  # --auto | --preview

if [[ ! -f "$REPO_FIX_STATE" || ! -s "$REPO_FIX_STATE" ]]; then
  echo -e "${CYAN}${BORDER}${RESET}"
  echo -e "${CYAN}🔧 $(t L_REPO_FIX_HEADER)${RESET}"
  echo -e "${CYAN}${BORDER}${RESET}"
  echo
  print_warn "$(t L_REPO_FIX_NO_STATE)"
  print_info "$(t L_REPO_FIX_RUN_SCAN): tdoc repo-scan [path]"
  echo
  exit 0
fi

echo -e "${CYAN}${BORDER}${RESET}"
case "$MODE" in
  --auto)    echo -e "${CYAN}🤖 $(t L_REPO_FIX_HEADER) (AUTO)${RESET}" ;;
  --preview) echo -e "${CYAN}👁  $(t L_REPO_FIX_HEADER) (PREVIEW)${RESET}" ;;
  *)         echo -e "${CYAN}🔧 $(t L_REPO_FIX_HEADER) (MANUAL)${RESET}" ;;
esac
echo -e "${CYAN}${BORDER}${RESET}"
echo

declare -A _seen=()
declare -a _issues=()

while IFS= read -r entry; do
  [[ -z "$entry" || "$entry" =~ ^# ]] && continue
  IFS='=' read -r key rest <<< "$entry"
  IFS=':' read -r _ ifile iline <<< "$rest"
  local_id="${key}:${ifile}"
  [[ -n "${_seen[$local_id]:-}" ]] && continue
  _seen["$local_id"]=1
  _issues+=("${key}|${ifile}|${iline}")
done < "$REPO_FIX_STATE"

total=${#_issues[@]}
if [[ $total -eq 0 ]]; then
  print_ok "$(t L_REPO_FIX_NOTHING)"
  exit 0
fi

echo -e "${GRAY}  $(t L_REPO_FIX_FOUND): $total $(t L_REPO_FIX_ISSUES)${RESET}"
echo

_fixed=0; _skipped=0; _manual=0

for entry in "${_issues[@]}"; do
  IFS='|' read -r key ifile iline <<< "$entry"

  echo -e "${CYAN}── ${key}${RESET} ${GRAY}${ifile:+→ $ifile}${iline:+:$iline}${RESET}"

  handler="fix_repo_${key}"
  auto_handler="auto_fix_repo_${key}"
  preview_str=""

  case "$MODE" in

    --preview)
      case "$key" in
        InvalidJSON)        preview_str="python3 -m json.tool $ifile > $ifile (reformat)" ;;
        UnpinnedDep)        preview_str="pip freeze > ${ifile}.pinned" ;;
        LangKeyMissing)     preview_str="append stub keys from en.sh → $(basename "${ifile:-?}")" ;;
        LangKeyOrphan)      preview_str="remove orphan keys from $(basename "${ifile:-?}")" ;;
        MakefileSpace)      preview_str="sed -i 's/^    /\t/g' $ifile" ;;
        MissingSourceGuard) preview_str="insert : \"\${TDOC_ROOT:?...}\" after shebang in $ifile" ;;
        ShellSyntax|ShellCheck|PythonSyntax|JSSyntax|YAMLSyntax|InvalidTOML)
                            preview_str="manual edit required — $ifile" ;;
        UnrefFunc|UnrefFuncModule|UnrefModule|UndefCall)
                            preview_str="manual review required — $ifile" ;;
        BrokenMdLink)       preview_str="manual link fix required — $ifile" ;;
        MissingTKey)        preview_str="add missing lang key in lang/*.sh" ;;
        *)                  preview_str="no auto-fix available" ;;
      esac
      echo -e "  ${GRAY}→ ${preview_str}${RESET}"
      ;;

    --auto)
      if declare -f "$auto_handler" >/dev/null 2>&1; then
        if "$auto_handler" "$ifile" "$iline"; then
          _fixed=$((_fixed+1))
        else
          _manual=$((_manual+1))
          print_info "  $(t L_REPO_FIX_NEEDS_MANUAL)"
        fi
      else
        print_skip "  $(t L_REPO_FIX_NO_HANDLER): $key"
        _skipped=$((_skipped+1))
      fi
      ;;

    *)
      if declare -f "$handler" >/dev/null 2>&1; then
        if "$handler" "$ifile" "$iline"; then
          _fixed=$((_fixed+1))
        else
          _manual=$((_manual+1))
        fi
      else
        print_skip "  $(t L_REPO_FIX_NO_HANDLER): $key"
        _skipped=$((_skipped+1))
      fi
      ;;
  esac
  echo
done

echo -e "${CYAN}${BORDER}${RESET}"
echo -e "${CYAN}📊 $(t L_REPO_FIX_SUMMARY)${RESET}"
echo -e "${CYAN}${BORDER}${RESET}"

if [[ "$MODE" != "--preview" ]]; then
  echo -e "  ${GREEN}$(t L_REPO_FIX_FIXED)  : ${_fixed}${RESET}"
  echo -e "  ${YELLOW}$(t L_REPO_FIX_MANUAL) : ${_manual}${RESET}"
  echo -e "  ${GRAY}$(t L_REPO_FIX_SKIPPED): ${_skipped}${RESET}"
  echo
  if [[ $_manual -gt 0 ]]; then
    print_info "$(t L_REPO_FIX_MANUAL_HINT): tdoc diagnose --last"
  fi
  if [[ $_fixed -gt 0 ]]; then
    print_info "$(t L_REPO_FIX_RESCAN): tdoc repo-scan"
  fi
fi
echo
