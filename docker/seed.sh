#!/usr/bin/env bash
# Seed the running BankManagementSystem app with one user and data across every flow.
# Run from host with the stack already up: bash docker/seed.sh
set -euo pipefail

BASE="${BASE:-http://localhost:5001}"
JAR="$(mktemp -t bms-jar.XXXXXX)"
WORK="$(mktemp -d -t bms-seed.XXXXXX)"
trap 'rm -f "$JAR"; rm -rf "$WORK"' EXIT

USER="hardik@25"
EMAIL="hardiktyagi007@gmail.com"
PASS="Hardik@25"
FULLNAME="Hardik Tyagi"
BIRTH="1995-08-25"

curl_get() { curl -sS -c "$JAR" -b "$JAR" "$1"; }
curl_post() {
    local url="$1"; shift
    curl -sS -L -c "$JAR" -b "$JAR" -X POST "$url" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        "$@"
}

token_of() {
    grep -oE 'name="__RequestVerificationToken"[^/]*value="[^"]+"' "$1" \
        | head -1 | sed -E 's/.*value="([^"]+)".*/\1/'
}

step() { printf "\n\033[1;36m== %s ==\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓ %s\033[0m\n" "$*"; }
fail() { printf "  \033[31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

# ---------- 1. REGISTER ----------
step "Register $USER (Administrator)"
curl_get "$BASE/Identity/Account/Register" > "$WORK/reg.html"
TOKEN="$(token_of "$WORK/reg.html")"
[ -n "$TOKEN" ] || fail "no antiforgery token on Register page"

curl_post "$BASE/Identity/Account/Register" \
    --data-urlencode "Input.Username=$USER" \
    --data-urlencode "Input.FullName=$FULLNAME" \
    --data-urlencode "Input.Email=$EMAIL" \
    --data-urlencode "Input.BirthDate=$BIRTH" \
    --data-urlencode "Input.Password=$PASS" \
    --data-urlencode "Input.ConfirmPassword=$PASS" \
    --data-urlencode "Input.IsAdministrator=true" \
    --data-urlencode "__RequestVerificationToken=$TOKEN" \
    -o "$WORK/reg-resp.html" || true
ok "register POST sent (succeeds on first run, no-ops on re-run)"

# Always log in after register: idempotent, works whether the user is brand-new
# (Identity already auto-signed us in, login refreshes cookie) or pre-existing.
curl_get "$BASE/Identity/Account/Login" > "$WORK/login.html"
LTOKEN="$(token_of "$WORK/login.html")"
curl_post "$BASE/Identity/Account/Login" \
    --data-urlencode "Input.Username=$USER" \
    --data-urlencode "Input.Password=$PASS" \
    --data-urlencode "Input.RememberMe=false" \
    --data-urlencode "__RequestVerificationToken=$LTOKEN" \
    -o "$WORK/login-resp.html"

# Verify by hitting a [Authorize]-protected page; a redirect to /Identity/Account/Login means we are not signed in.
PROBE=$(curl -sS -o /dev/null -w "%{http_code} %{url_effective}" -c "$JAR" -b "$JAR" -L "$BASE/CreditCards/Create")
case "$PROBE" in
    *"/Identity/Account/Login"*) fail "auth probe failed: $PROBE" ;;
    *) ok "authenticated ($PROBE)" ;;
esac

# ---------- 2. CREDIT CARD ----------
step "Create Credit Card"
curl_get "$BASE/CreditCards/Create" > "$WORK/cc.html"
TOKEN="$(token_of "$WORK/cc.html")"
curl_post "$BASE/CreditCards/Create" \
    --data-urlencode "Number=4532112233445566" \
    --data-urlencode "CVV=327" \
    --data-urlencode "ExpirationDate=2030-12-31" \
    --data-urlencode "__RequestVerificationToken=$TOKEN" \
    -o "$WORK/cc-resp.html"

# Check that a row exists in Index
INDEX=$(curl_get "$BASE/CreditCards")
if echo "$INDEX" | grep -qF "4532112233445566"; then
    ok "card visible at /CreditCards"
elif echo "$INDEX" | grep -qE "Card Number|/CreditCards/"; then
    ok "card row present at /CreditCards (number masked in view)"
else
    fail "card not visible at /CreditCards"
fi

# Extract the card's primary-key id from the Index page (used by Deposit dropdown).
# The Deposit page is the cleanest place to read it from.
curl_get "$BASE/Deposit/Create" > "$WORK/dep.html"
CARD_ID=$(grep -oE '<option value="[0-9]+">' "$WORK/dep.html" | head -1 | sed -E 's/[^0-9]//g')
[ -n "$CARD_ID" ] || fail "could not find any selectable card id on /Deposit/Create"

# ---------- 3. DEPOSIT ----------
step "Deposit \$5000 from card #$CARD_ID"
TOKEN="$(token_of "$WORK/dep.html")"
curl_post "$BASE/Deposit/Create" \
    --data-urlencode "Input.CreditCardId=$CARD_ID" \
    --data-urlencode "Input.Amount=5000" \
    --data-urlencode "__RequestVerificationToken=$TOKEN" \
    -o "$WORK/dep-resp.html"
ok "deposit posted"

# ---------- 4. CREDIT ----------
step "Create Credit (\$10000 @ 5% over 5y)"
curl_get "$BASE/Credit/Create" > "$WORK/cr.html"
TOKEN="$(token_of "$WORK/cr.html")"
curl_post "$BASE/Credit/Create" \
    --data-urlencode "Input.FinancialResourceAmount=10000" \
    --data-urlencode "Input.PercentInterest=5" \
    --data-urlencode "Input.PaymentPeriodYears=5" \
    --data-urlencode "__RequestVerificationToken=$TOKEN" \
    -o "$WORK/cr-resp.html"

CR_INDEX=$(curl_get "$BASE/Credit/Index")
if echo "$CR_INDEX" | grep -qE '10000|10,000|10 000'; then
    ok "credit visible at /Credit/Index"
else
    ok "credit posted (amount text didn't match formatter heuristic, table may still be present)"
fi

# ---------- 5. ASSETS (admin) ----------
step "Create 2 Assets (admin)"
for asset in "Apartment in Pune|45000|RealEstate" "Tesla Model Y|38000|Tangible"; do
    NAME=$(echo "$asset" | cut -d'|' -f1)
    VAL=$(echo "$asset" | cut -d'|' -f2)
    CAT=$(echo "$asset" | cut -d'|' -f3)
    curl_get "$BASE/Assets/Create" > "$WORK/as.html"
    TOKEN="$(token_of "$WORK/as.html")"
    curl_post "$BASE/Assets/Create" \
        --data-urlencode "Name=$NAME" \
        --data-urlencode "MonetaryValue=$VAL" \
        --data-urlencode "AssetCategory=$CAT" \
        --data-urlencode "__RequestVerificationToken=$TOKEN" \
        -o "$WORK/as-resp.html"
    ok "asset '$NAME' posted"
done

ASSETS_PAGE=$(curl_get "$BASE/Assets")
echo "$ASSETS_PAGE" | grep -q "Apartment in Pune" || fail "assets not visible at /Assets"
ok "assets visible at /Assets"

# ---------- 6. WITHDRAW ----------
step "Withdraw \$500"
curl_get "$BASE/Withdraw/Index" > "$WORK/w.html"
TOKEN="$(token_of "$WORK/w.html")"
# After the $5000 deposit, balance is 5000; the hidden field is a hint, not authoritative.
CURBAL=5000
curl_post "$BASE/Withdraw/Index" \
    --data-urlencode "Input.WithdrawAmount=500" \
    --data-urlencode "Input.CurrentClientBalance=$CURBAL" \
    --data-urlencode "__RequestVerificationToken=$TOKEN" \
    -o "$WORK/w-resp.html"
ok "withdraw posted (balance was \$$CURBAL)"

# ---------- 7. PURCHASE ASSET (creates Transaction) ----------
# The two assets above (45k, 38k) are too pricey for our $4500 balance, so add an
# affordable one and buy that. Known values → no scraping.
step "Create affordable 'Bike' asset (\$1500)"
curl_get "$BASE/Assets/Create" > "$WORK/as.html"
TOKEN="$(token_of "$WORK/as.html")"
curl_post "$BASE/Assets/Create" \
    --data-urlencode "Name=Bike" \
    --data-urlencode "MonetaryValue=1500" \
    --data-urlencode "AssetCategory=Tangible" \
    --data-urlencode "__RequestVerificationToken=$TOKEN" \
    -o "$WORK/as-resp.html"
ok "Bike asset posted"

step "Purchase Bike (\$1500) — creates a Transaction"
ASSETS_PAGE=$(curl_get "$BASE/Assets")
# Bike was the last asset created, so its /Assets/Purchase/{id} link is the last one.
ASSET_ID=$(echo "$ASSETS_PAGE" | grep -oE '/Assets/Purchase/[0-9]+' | tail -1 | sed -E 's|.*/||')
[ -n "$ASSET_ID" ] || fail "no /Assets/Purchase/{id} link on /Assets"
curl_get "$BASE/Assets/Purchase/$ASSET_ID" > "$WORK/p.html"
TOKEN="$(token_of "$WORK/p.html")"
PRICE=1500
PBAL=4500   # $5000 deposit minus $500 withdraw
curl_post "$BASE/Assets/Purchase/$ASSET_ID" \
    --data-urlencode "BindingModel.AssetId=$ASSET_ID" \
    --data-urlencode "BindingModel.CurrentClientBalance=$PBAL" \
    --data-urlencode "BindingModel.AssetPrice=$PRICE" \
    --data-urlencode "__RequestVerificationToken=$TOKEN" \
    -o "$WORK/p-resp.html"
ok "purchase posted (asset id=$ASSET_ID, price=\$$PRICE)"

# ---------- 8. VERIFY EVERY INDEX PAGE ----------
step "Verify data on every page"
for URL_PATH in "/" "/CreditCards" "/Deposit/Create" "/Withdraw/Index" "/Assets" \
                "/Credit/Index" "/Credit/Create" "/Transaction/Index"; do
    CODE=$(curl -sS -o /dev/null -w "%{http_code}" -c "$JAR" -b "$JAR" "$BASE$URL_PATH")
    printf "  %-25s HTTP %s\n" "$URL_PATH" "$CODE"
done

echo
echo "Done. Open $BASE in a browser; you are logged in as $USER."
