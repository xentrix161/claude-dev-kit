#!/usr/bin/env bash
# Parser príkazu Bash pre pre-bash.sh (SPEC §4.4.1): pre každý `git commit` / `git add` vráti záznam s `cd`,
# ktoré pred ním (isto alebo možno) prebehnú. Načítava ho pre-bash.sh za lib.sh.
# Samostatne: bash cmd-parse.sh --dump '<príkaz>'   (polia \x1f vypíše ako |)
#
# Výstup (polia oddelené \x1f, jeden záznam na riadok, poradie V/K, R, potom D…C):
#   V NAME value [E]    úvodné priradenie, jediné v príkaze (E = export)
#   K NAME value        iné priradenie / slovo cyklu for → NAME nie je známe, value je kandidát
#   R dôvod             záchrana (chyba rozkladu, commit v tele funkcie, commit mimo štruktúry)
#   D class cmd úryvok home cdpath op…   cd/pushd/popd/chdir pred nasledujúcim C; class C = isté, N = nie je isté
#   C commit|add slovo…                 príkaz commitu / add, slová ako sú napísané (úvodzovky ostávajú)
# read -d '' namiesto $(cat <<…): bash 3.2 v $(…) nezvláda nepárové zátvorky v heredocu.
IFS= read -r -d '' DK_AWK_CMD <<'AWK' || true
BEGIN { US = "\037" }
{ txt = txt $0 "\n" }
END {
    RE_COMMIT = ENVIRON["DK_RE_COMMIT"]; RE_ADD = ENVIRON["DK_RE_ADD"]
    gsub(/\\\n/, "", txt)
    err = ""; ntok = 0; nev = 0; nrec = 0; depth = 0; inFunc = 0; subDepth = 0; leadOK = 1; lastLead = ""
    ncommit = 0; nvar = 0
    lex()
    if (err == "") {
        pos = 1
        parse_list("EOF", "")
        if (err == "" && tt[pos] != "EOF") err = "neočakávané slovo " tx[pos]
    }
    if (err != "") { print "R" US err; exit 0 }
    for (i = 1; i <= nvar; i++) {
        name = vorder[i]
        if (vcount[name] == 1 && vlead[name]) print "V" US name US vval[name] US vexp[name]
        else { n = split(vvals[name], a, US); for (j = 1; j <= n; j++) if (a[j] != "") print "K" US name US substr(a[j], 2) }
    }
    s = txt; raw = 0
    while (match(s, RE_COMMIT)) { raw++; s = substr(s, RSTART + RLENGTH) }
    if (raw > ncommit) print "R" US "commit mimo štruktúry"
    for (k = 1; k <= nrec; k++) printf "%s%s", rec_d[k], rec_c[k]
}

# ---------------------------------------------------------------- lexer
# Tokeny: W kus slova (tm = maskovaný: úvodzovky → Q; tu = bez úvodzoviek), S/E otvorenie/koniec $(…) `…` <(…) >(…),
# O operátor, D presmerovanie, N nový riadok, EOF. tg = prilepený k predchádzajúcemu, tr = operand presmerovania.
function addtok(t, x, m, u, p, e, g,   i) {
    i = ++ntok; tt[i] = t; tx[i] = x; tm[i] = m; tu[i] = u; tp[i] = p; te[i] = e; tg[i] = g; tr[i] = 0
    if ((t == "W" || t == "S" || t == "E") && redirOp) { tr[i] = 1; redirSeen = 1 }
    glue = 1
}
function popen(i) { if (!pOpen) { pOpen = 1; pStart = i; pM = ""; pU = ""; pGlue = glue } }
function pflush(i) { if (pOpen) { addtok("W", substr(txt, pStart, i - pStart), pM, pU, pStart, i, pGlue); pOpen = 0 } }
function boundary() { glue = 0; if (redirSeen) { redirOp = 0; redirSeen = 0 } }
function skip_paren(i, dep,   n, c) { # od i, dep otvorených zátvoriek; vráti pozíciu za uzavretím
    n = length(txt)
    while (i <= n) {
        c = substr(txt, i, 1)
        if (c == "(") dep++
        else if (c == ")") { dep--; if (dep == 0) return i + 1 }
        i++
    }
    err = "neuzavretá zátvorka"; return i
}
function skip_brace(i,   n, c, dep) {
    n = length(txt); dep = 0
    while (i <= n) {
        c = substr(txt, i, 1)
        if (c == "{") dep++
        else if (c == "}") { dep--; if (dep == 0) return i + 1 }
        i++
    }
    err = "neuzavretá zátvorka"; return i
}
function find_dbracket(i,   n, k) {
    n = length(txt)
    for (k = i + 2; k + 1 <= n; k++)
        if (substr(txt, k, 2) == "]]" && substr(txt, k - 1, 1) ~ /[ \t\n]/ && (k + 2 > n || substr(txt, k + 2, 1) ~ /[ \t\n;&|)]/))
            return k + 2
    return 0
}
function lex(   i, n, c, c2, c3, top, j, op, i0) {
    n = length(txt); i = 1; sd = 0; glue = 0; redirOp = 0; redirSeen = 0; pOpen = 0
    while (i <= n && err == "") {
        c = substr(txt, i, 1); c2 = substr(txt, i, 2); c3 = substr(txt, i, 3)
        top = (sd > 0) ? sk[sd] : ""
        if (top == "dq") {
            if (c == "\"") { popen(i); sd--; i++; continue }
            popen(i)
            if (c == "\\") { pU = pU substr(txt, i + 1, 1); i += 2; continue }
            if (c3 == "$((") { j = skip_paren(i + 1, 0); pU = pU substr(txt, i, j - i); i = j; continue }
            if (c2 == "$(") { pflush(i); addtok("S", "$(", "", "", i, i + 2, glue); sd++; sk[sd] = "sub"; sp[sd] = 0; i += 2; continue }
            if (c == "`") { pflush(i); addtok("S", "`", "", "", i, i + 1, glue); sd++; sk[sd] = "bt"; i++; continue }
            if (c2 == "${") { j = skip_brace(i + 1); pU = pU substr(txt, i, j - i); i = j; continue }
            pU = pU c; i++; continue
        }
        if (c == " " || c == "\t" || c == "\r") { pflush(i); boundary(); i++; continue }
        if (c == "\n") { pflush(i); boundary(); addtok("N", "\n", "", "", i, i + 1, 0); glue = 0; i++; continue }
        if (c == "#" && !pOpen && !glue) { while (i <= n && substr(txt, i, 1) != "\n") i++; continue }
        if (c == "\\") { popen(i); pM = pM substr(txt, i + 1, 1); pU = pU substr(txt, i + 1, 1); i += 2; continue }
        if (c == "'") {
            popen(i); j = index(substr(txt, i + 1), "'")
            if (j == 0) { err = "neuzavretá úvodzovka"; return }
            pM = pM "Q"; pU = pU substr(txt, i + 1, j - 1); i = i + j + 1; continue
        }
        if (c2 == "$'") {
            popen(i); j = i + 2
            while (j <= n) { c = substr(txt, j, 1); if (c == "\\") { j += 2; continue } if (c == "'") break; j++ }
            if (j > n) { err = "neuzavretá úvodzovka"; return }
            pM = pM "Q"; pU = pU substr(txt, i + 2, j - i - 2); i = j + 1; continue
        }
        if (c == "\"") { popen(i); pM = pM "Q"; sd++; sk[sd] = "dq"; i++; continue }
        if (c3 == "$((") { popen(i); j = skip_paren(i + 1, 0); pM = pM "Q"; pU = pU substr(txt, i, j - i); i = j; continue }
        if (c2 == "$(") { pflush(i); addtok("S", "$(", "", "", i, i + 2, glue); sd++; sk[sd] = "sub"; sp[sd] = 0; i += 2; continue }
        if (c2 == "${") { popen(i); j = skip_brace(i + 1); pM = pM substr(txt, i, j - i); pU = pU substr(txt, i, j - i); i = j; continue }
        if (c == "`") {
            pflush(i)
            if (top == "bt") { addtok("E", "`", "", "", i, i + 1, glue); sd--; i++; continue }
            addtok("S", "`", "", "", i, i + 1, glue); sd++; sk[sd] = "bt"; i++; continue
        }
        if (c2 == "<(" || c2 == ">(") { pflush(i); addtok("S", c2, "", "", i, i + 2, glue); sd++; sk[sd] = "proc"; sp[sd] = 0; i += 2; continue }
        if (c == "(") {
            if (!pOpen && !glue && c2 == "((") { j = skip_paren(i, 0); popen(i); pM = "(("; pU = substr(txt, i, j - i); i = j; continue }
            pflush(i); boundary()
            if (top == "sub" || top == "proc") sp[sd]++
            addtok("O", "(", "", "", i, i + 1, 0); glue = 0; i++; continue
        }
        if (c == ")") {
            pflush(i); boundary()
            if ((top == "sub" || top == "proc") && sp[sd] == 0) { addtok("E", ")", "", "", i, i + 1, 1); sd--; i++; continue }
            if (top == "sub" || top == "proc") sp[sd]--
            addtok("O", ")", "", "", i, i + 1, 0); glue = 0; i++; continue
        }
        if (c == ";") {
            pflush(i); boundary()
            if (c3 == ";;&") { addtok("O", ";;&", "", "", i, i + 3, 0); i += 3 }
            else if (c2 == ";;" || c2 == ";&") { addtok("O", c2, "", "", i, i + 2, 0); i += 2 }
            else { addtok("O", ";", "", "", i, i + 1, 0); i++ }
            glue = 0; continue
        }
        if (c == "&") {
            pflush(i); boundary()
            if (c2 == "&&") { addtok("O", "&&", "", "", i, i + 2, 0); i += 2 }
            else if (c3 == "&>>") { addtok("D", "&>>", "", "", i, i + 3, 0); redirOp = 1; redirSeen = 0; i += 3 }
            else if (c2 == "&>") { addtok("D", "&>", "", "", i, i + 2, 0); redirOp = 1; redirSeen = 0; i += 2 }
            else { addtok("O", "&", "", "", i, i + 1, 0); i++ }
            glue = 0; continue
        }
        if (c == "|") {
            pflush(i); boundary()
            if (c2 == "||") { addtok("O", "||", "", "", i, i + 2, 0); i += 2 }
            else if (c2 == "|&") { addtok("O", "|", "", "", i, i + 2, 0); i += 2 }
            else { addtok("O", "|", "", "", i, i + 1, 0); i++ }
            glue = 0; continue
        }
        if (c == "<" || c == ">") {
            if (pOpen && pM ~ /^[0-9]+$/ && !pGlue) pOpen = 0
            else pflush(i)
            boundary(); i0 = i
            if (c3 == "<<<" || c3 == "<<-") { op = c3; i += 3 }
            else if (c2 == "<<" || c2 == "<>" || c2 == "<&" || c2 == ">>" || c2 == ">&" || c2 == ">|") { op = c2; i += 2 }
            else { op = c; i++ }
            addtok("D", op, "", "", i0, i, 0); redirOp = 1; redirSeen = 0; glue = 0; continue
        }
        if (c2 == "[[" && !pOpen && !glue && substr(txt, i + 2, 1) ~ /[ \t\n]/) {
            j = find_dbracket(i)
            if (j > 0) { popen(i); pM = "[[Q]]"; pU = substr(txt, i, j - i); i = j; continue }
        }
        popen(i); pM = pM c; pU = pU c; i++
    }
    if (err != "") return
    pflush(i)
    if (sd > 0) { err = (sk[sd] == "dq") ? "neuzavretá úvodzovka" : "neuzavretá zátvorka"; return }
    addtok("EOF", "", "", "", i, i, 0)
}

# ---------------------------------------------------------------- parser + vyhodnotenie
# Rámec hĺbky d: f_base = zdedené udalosti (id/trieda), f_done = ukončené zoznamy, f_and = bežiaci and-or zoznam
# (id/trieda/prvý), f_pipe = bežiaca rúra (id/trieda). Trieda C = cd isto prebehne pred C, N = nie je isté.
function standalone(i) { return tt[i] == "W" && !((tt[i + 1] == "W" || tt[i + 1] == "S") && tg[i + 1]) }
function skip_nl() { while (tt[pos] == "N") pos++ }
function is_stop(stops,   n, a, i, t, w) {
    t = tt[pos]; w = tx[pos]
    n = split(stops, a, " ")
    for (i = 1; i <= n; i++) {
        if (a[i] == "EOF" && t == "EOF") return 1
        if (a[i] == "E" && t == "E") return 1
        if (a[i] == ")" && t == "O" && w == ")") return 1
        if ((a[i] == ";;" || a[i] == ";&" || a[i] == ";;&") && t == "O" && w == a[i]) return 1
        if (t == "W" && standalone(pos) && tm[pos] == a[i]) return 1
    }
    return 0
}
function nify(s) { gsub(/\/C/, "/N", s); return s }
function visible(d,   s, n, a, i, b) {
    s = f_base[d] " " f_done[d]
    n = split(f_and[d], a, " ")
    for (i = 1; i <= n; i++) if (a[i] != "") { split(a[i], b, "/"); s = s " " b[1] "/" (f_or[d] ? "N" : b[2]) }
    n = split(f_pipe[d], a, " ")
    for (i = 1; i <= n; i++) if (a[i] != "") { split(a[i], b, "/"); s = s " " b[1] "/N" }
    return s
}
function end_pipeline(d,   n, a, i, b) {
    n = split(f_pipe[d], a, " ")
    for (i = 1; i <= n; i++) if (a[i] != "") { split(a[i], b, "/"); f_and[d] = f_and[d] " " b[1] "/" ((f_np[d] > 1 || f_bang[d]) ? "N" : b[2]) "/" f_first[d] }
    f_pipe[d] = ""
}
function end_andor(d, term,   n, a, i, b) {
    n = split(f_and[d], a, " ")
    for (i = 1; i <= n; i++) if (a[i] != "") { split(a[i], b, "/"); f_done[d] = f_done[d] " " b[1] "/" ((b[3] == 1 && term != "&") ? b[2] : "N") }
    f_and[d] = ""; f_or[d] = 0; f_first[d] = 1
}
function add_export(d, ev, forceN,   n, a, i, b) {
    n = split(ev, a, " ")
    for (i = 1; i <= n; i++) if (a[i] != "") { split(a[i], b, "/"); f_pipe[d] = f_pipe[d] " " b[1] "/" (forceN ? "N" : b[2]) }
}
function new_frame(base,   d) {
    d = ++depth
    f_base[d] = base; f_done[d] = ""; f_and[d] = ""; f_pipe[d] = ""; f_or[d] = 0; f_first[d] = 1; f_np[d] = 0; f_bang[d] = 0
    return d
}
function demote_lead() { if (lastLead != "") { vlead[lastLead] = 0; lastLead = "" } leadOK = 0 }
function parse_list(stops, base,   d, ev, t, w, p0) {
    d = new_frame(base)
    while (err == "") {
        skip_nl()
        t = tt[pos]; w = tx[pos]
        if (is_stop(stops)) break
        if (t == "EOF") { err = "neuzavretá zátvorka"; break }
        if (t == "E" || (t == "O" && w != "(")) { err = "neočakávané slovo " w; break }
        if (t == "W" && standalone(pos) && tm[pos] ~ /^(\}|fi|done|esac|then|do|elif|else|in)$/) { err = "neočakávané slovo " tm[pos]; break }
        p0 = pos
        parse_pipeline(d)
        if (err != "") break
        if (pos == p0) { err = "neočakávané slovo " tx[pos]; break }
        t = tt[pos]; w = tx[pos]
        if (t == "O" && (w == "&&" || w == "||")) {
            end_pipeline(d); f_first[d] = 0
            if (w == "||") { f_or[d] = 1; demote_lead() }
            pos++; skip_nl(); continue
        }
        end_pipeline(d)
        if (t == "O" && w == "&") { end_andor(d, "&"); demote_lead(); pos++; continue }
        if (t == "O" && w == ";") { end_andor(d, ";"); pos++; continue }
        if (t == "N") { end_andor(d, ";"); pos++; continue }
        end_andor(d, ";")
        if (!(is_stop(stops) || t == "EOF")) { err = "neočakávané slovo " w; break }
    }
    ev = f_done[d]
    depth--
    return ev
}
function parse_pipeline(d,   w) {
    f_np[d] = 0; f_bang[d] = 0
    while (tt[pos] == "W" && standalone(pos) && (tm[pos] == "!" || tm[pos] == "time")) {
        w = tm[pos]; f_bang[d] = 1; leadOK = 0; pos++
        if (w == "time" && tt[pos] == "W" && tm[pos] == "-p") pos++
    }
    while (err == "") {
        parse_command(d)
        f_np[d]++
        if (tt[pos] == "O" && tx[pos] == "|") { pos++; skip_nl(); demote_lead(); continue }
        break
    }
}
function parse_body(d,   dd, ev) { # jeden (zložený) príkaz vo vlastnom rámci, vráti jeho udalosti
    dd = new_frame(visible(d))
    parse_command(dd)
    if (err == "") { end_pipeline(dd); end_andor(dd, ";") }
    ev = f_done[dd]; depth--
    return ev
}
function parse_redirs(d) { while (tt[pos] == "D") { pos++; if (tt[pos] == "W" || tt[pos] == "S") read_word(d) } }
function parse_command(d,   t, w, ev) {
    t = tt[pos]; w = tm[pos]
    if (t == "O" && tx[pos] == "(") {
        pos++
        if (tt[pos] == "O" && tx[pos] == ")") { pos++; skip_nl(); ev = parse_body(d) }
        else { ev = parse_list(")", visible(d)); if (err != "") return; pos++ }
        add_export(d, ev, 1); demote_lead(); parse_redirs(d); return
    }
    if (t == "W" && standalone(pos)) {
        if (w == "{") { pos++; ev = parse_list("}", visible(d)); if (err != "") return; pos++; add_export(d, ev, 0); demote_lead(); parse_redirs(d); return }
        if (w == "if") { parse_if(d); return }
        if (w == "while" || w == "until") { parse_loop(d); return }
        if (w == "for" || w == "select") { parse_for(d); return }
        if (w == "case") { parse_case(d); return }
        if (w == "function") {
            pos++
            if (tt[pos] != "W") { err = "neočakávané slovo " tx[pos]; return }
            pos++
            if (tt[pos] == "O" && tx[pos] == "(" && tt[pos + 1] == "O" && tx[pos + 1] == ")") pos += 2
            skip_nl(); parse_funcbody(d); return
        }
        if (tt[pos + 1] == "O" && tx[pos + 1] == "(" && tt[pos + 2] == "O" && tx[pos + 2] == ")") { pos += 3; skip_nl(); parse_funcbody(d); return }
    }
    parse_simple(d)
}
function parse_funcbody(d,   ev) {
    inFunc++; ev = parse_body(d); inFunc--
    if (err != "") return
    add_export(d, ev, 1); demote_lead()
}
function parse_if(d,   ev, base) {
    pos++
    ev = parse_list("then", visible(d)); if (err != "") return
    pos++
    base = visible(d)
    ev = ev " " parse_list("elif else fi", base " " nify(ev)); if (err != "") return
    while (tt[pos] == "W" && tm[pos] == "elif") {
        pos++
        ev = ev " " parse_list("then", base " " nify(ev)); if (err != "") return
        pos++
        ev = ev " " parse_list("elif else fi", base " " nify(ev)); if (err != "") return
    }
    if (tt[pos] == "W" && tm[pos] == "else") { pos++; ev = ev " " parse_list("fi", base " " nify(ev)); if (err != "") return }
    pos++
    add_export(d, ev, 1); demote_lead(); parse_redirs(d)
}
function loop_rule(rs, es,   k, id) { # cd v tele cyklu aj za commitom nie je isté (druhá iterácia)
    for (k = rs + 1; k <= nrec; k++) {
        if (substr(rec_c[k], 1, 1) != "C") continue
        for (id = es + 1; id <= nev; id++) if (ev_pos[id] > rec_pos[k] && !ev_sub[id]) rec_d[k] = rec_d[k] dline(id, "N")
    }
}
function parse_loop(d,   ev, rs, es) {
    rs = nrec; es = nev
    pos++
    ev = parse_list("do", visible(d)); if (err != "") return
    pos++
    ev = ev " " parse_list("done", visible(d) " " nify(ev)); if (err != "") return
    pos++
    loop_rule(rs, es)
    add_export(d, ev, 1); demote_lead(); parse_redirs(d)
}
function parse_for(d,   ev, rs, es, name, any) {
    rs = nrec; es = nev
    pos++
    if (tt[pos] != "W") { err = "neočakávané slovo " tx[pos]; return }
    if (substr(tm[pos], 1, 2) == "((") { pos++ }
    else {
        name = tu[pos]; pos++; skip_nl()
        any = 0
        if (tt[pos] == "W" && tm[pos] == "in") {
            pos++
            while (tt[pos] == "W" || tt[pos] == "S") { read_word(d); if (err != "") return; taint(name, W_RAW); any = 1 }
        }
        if (!any) taint(name, "")
    }
    if (tt[pos] == "O" && tx[pos] == ";") pos++
    skip_nl()
    if (!(tt[pos] == "W" && tm[pos] == "do")) { err = "neočakávané slovo " tx[pos]; return }
    pos++
    ev = parse_list("done", visible(d)); if (err != "") return
    pos++
    loop_rule(rs, es)
    add_export(d, ev, 1); demote_lead(); parse_redirs(d)
}
function parse_case(d,   ev, base) {
    pos++
    if (tt[pos] == "W" || tt[pos] == "S") { read_word(d); if (err != "") return }
    skip_nl()
    if (!(tt[pos] == "W" && tm[pos] == "in")) { err = "neočakávané slovo " tx[pos]; return }
    pos++; skip_nl()
    base = visible(d); ev = ""
    while (err == "") {
        if (tt[pos] == "W" && standalone(pos) && tm[pos] == "esac") { pos++; break }
        if (tt[pos] == "O" && tx[pos] == "(") pos++
        while (!(tt[pos] == "O" && tx[pos] == ")")) {
            if (tt[pos] == "W" || tt[pos] == "S") { read_word(d); if (err != "") return }
            else if (tt[pos] == "O" && tx[pos] == "|") pos++
            else { err = (tt[pos] == "EOF") ? "neuzavretá zátvorka" : "neočakávané slovo " tx[pos]; return }
        }
        pos++
        ev = ev " " parse_list(";; ;& ;;& esac", base " " nify(ev)); if (err != "") return
        if (tt[pos] == "O") { pos++; skip_nl() }
        else { pos++; break }
    }
    add_export(d, ev, 1); demote_lead(); parse_redirs(d)
}
function read_word(d,   start, m, u, e, trf) {
    start = tp[pos]; m = ""; u = ""; trf = tr[pos]; e = te[pos]
    while (1) {
        if (tt[pos] == "W") { m = m tm[pos]; u = u tu[pos]; e = te[pos]; pos++ }
        else if (tt[pos] == "S") {
            pos++; subDepth++
            parse_list("E", visible(d))
            subDepth--
            if (err != "") return
            e = te[pos]; pos++; m = m "Q"; u = u "Q"
        }
        else break
        if (!((tt[pos] == "W" || tt[pos] == "S") && tg[pos])) break
    }
    W_M = m; W_U = u; W_RAW = substr(txt, start, e - start); W_END = e; W_TR = trf
    gsub(/\n/, " ", W_RAW)
}
function taint(name, val) {
    if (!(name in vseen)) { vorder[++nvar] = name; vseen[name] = 1 }
    vcount[name]++; vvals[name] = vvals[name] US "=" val
}
function assign(name, val, lead, isexp) {
    taint(name, val)
    if (lead) { vlead[name] = 1; vval[name] = val; vexp[name] = isexp ? "E" : "" }
}
function dline(id, c) { return "D" US c US ev_cmd[id] US ev_snip[id] US ev_home[id] US ev_cdpath[id] ev_ops[id] "\n" }
function emit_rec(kind, words, startpos, d,   k, vis, n, a, i, b) {
    k = ++nrec; rec_pos[k] = startpos; rec_d[k] = ""
    ncommit += (kind == "commit")
    if (inFunc > 0) { rec_c[k] = "R" US "commit v tele funkcie\n"; return }
    vis = visible(d)
    n = split(vis, a, " ")
    for (i = 1; i <= n; i++) if (a[i] != "") { split(a[i], b, "/"); rec_d[k] = rec_d[k] dline(b[1], b[2]) }
    rec_c[k] = "C" US kind words "\n"
}
function parse_simple(d,   nw, i, j, startpos, endpos, lead, name, val, cmd, snip, ops, home, cdpath, m, words, id, plus, first, sm, sr, su) {
    # Slová najprv do reťazcov: polia wm/wr/wu sú globálne a vnorený $(…) by ich prepísal.
    nw = 0; startpos = tp[pos]; endpos = te[pos]; home = ""; cdpath = 0; sm = ""; sr = ""; su = ""
    while (err == "") {
        if (tt[pos] == "D") { pos++; if (tt[pos] == "W" || tt[pos] == "S") { read_word(d); endpos = W_END } continue }
        if (tt[pos] != "W" && tt[pos] != "S") break
        read_word(d); if (err != "") return
        endpos = W_END
        if (W_TR) continue
        nw++; sm = sm US W_M; sr = sr US W_RAW; su = su US W_U
    }
    if (nw == 0) return
    split(substr(sm, 2), wm, US); split(substr(sr, 2), wr, US); split(substr(su, 2), wu, US)
    first = wu[1]
    if (first == "export" || first == "declare" || first == "typeset" || first == "local" || first == "readonly") {
        lead = (first == "export" && depth == 1 && leadOK && inFunc == 0 && f_or[1] == 0 && f_np[1] == 0)
        for (j = 2; j <= nw; j++) {
            if (wm[j] ~ /^-/) continue
            if (wm[j] ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=/) {
                name = wr[j]; sub(/\+?=.*/, "", name); val = wr[j]; sub(/^[^=]*=/, "", val)
                if (wm[j] ~ /^[A-Za-z_][A-Za-z0-9_]*\+=/) { taint(name, ""); continue }
                assign(name, val, lead, 1); if (lead) lastLead = name
            } else taint(wu[j], "")
        }
        if (first != "export") leadOK = 0
        return
    }
    if (first == "unset" || first == "read") {
        for (j = 2; j <= nw; j++) if (wm[j] !~ /^-/) taint(wu[j], "")
        leadOK = 0; return
    }
    i = 1
    while (i <= nw && wm[i] ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=/) i++
    if (i > nw) {
        lead = (depth == 1 && leadOK && inFunc == 0 && f_or[1] == 0 && f_np[1] == 0)
        for (j = 1; j <= nw; j++) {
            name = wr[j]; sub(/\+?=.*/, "", name); val = wr[j]; sub(/^[^=]*=/, "", val)
            plus = (wm[j] ~ /^[A-Za-z_][A-Za-z0-9_]*\+=/)
            if (plus) taint(name, "")
            else { assign(name, val, lead, 0); if (lead) lastLead = name }
        }
        return
    }
    while (i <= nw && (wu[i] == "builtin" || wu[i] == "command")) i++
    if (i > nw) { leadOK = 0; return }
    cmd = wu[i]; leadOK = 0; lastLead = ""
    if (cmd == "cd" || cmd == "pushd" || cmd == "popd" || cmd == "chdir") {
        for (j = 1; j < i; j++) {
            if (wm[j] ~ /^HOME=/) { home = wr[j]; sub(/^HOME=/, "", home) }
            if (wm[j] ~ /^CDPATH=/) cdpath = 1
        }
        ops = ""
        for (j = i + 1; j <= nw; j++) ops = ops US wr[j]
        snip = substr(txt, startpos, endpos - startpos); gsub(/\n/, " ", snip)
        id = ++nev; ev_cmd[id] = cmd; ev_snip[id] = snip; ev_ops[id] = ops; ev_home[id] = home; ev_cdpath[id] = cdpath
        ev_pos[id] = startpos; ev_sub[id] = (subDepth > 0)
        f_pipe[d] = f_pipe[d] " " id "/" ((cmd == "chdir") ? "N" : "C")
        return
    }
    m = ""; words = ""
    for (j = 1; j <= nw; j++) { m = m (j > 1 ? " " : "") wm[j]; words = words US wr[j] }
    if (match(m, RE_COMMIT)) emit_rec("commit", words, startpos, d)
    else if (match(m, RE_ADD)) emit_rec("add", words, startpos, d)
}
AWK

dk_cmd_parse() { # <príkaz> — záznamy na stdout
    printf '%s\n' "$1" | DK_RE_COMMIT="$DK_RE_COMMIT" DK_RE_ADD="$DK_RE_ADD" awk "$DK_AWK_CMD"
}

if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "${1:-}" = --dump ]; then
    DK_NO_STDIN=1
    . "$(dirname "$0")/lib.sh" || exit 1
    dk_cmd_parse "${2:-}" | tr '\037' '|'
fi
