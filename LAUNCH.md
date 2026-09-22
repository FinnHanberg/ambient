# Launching Ambient

Three gates, in the order they block you.

---

## 1 · Distribution — $99/year, unavoidable

macOS 26 does not show a scary dialog for an unsigned downloaded app. It
**refuses to open it**. Right-click → Open still works, but you are asking every
tester to defeat a security warning before they see your product, and some will
simply not bother.

    Apple Developer Program → developer.apple.com/programs → $99/year

Then create a **Developer ID Application** certificate, install it in your login
keychain, and store notarization credentials once:

```bash
xcrun notarytool store-credentials ambient \
  --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PW
```

After that, `./release.sh 0.2` signs, notarizes, staples and packages in one
step. It refuses to pretend, and tells you exactly which piece is missing.

Nothing else on this page matters until this is done.

## 2 · Hosting — free

GitHub Releases. Versioned, free, permanent URLs, and it is the feed the app
already reads.

```bash
cd "~/Claude 1/ambient" && git init && git add -A && git commit -m "Ambient 0.2"
# create the repo, push, then attach dist/Ambient-0.2.zip to a release tagged v0.2
```

Point the app at it once:

```bash
echo "https://api.github.com/repos/OWNER/ambient/releases/latest" > ~/.ambient/updates.txt
```

Every build then checks on launch and offers the newer one in Settings → About.
Deliberately **not** an auto-updater: people testing something that changes
daily want to know a build landed, not to have it swapped under them mid-pass.

## 3 · Payment — only if you decide to charge

You are in Belgium, so use a **merchant of record**. They become the seller,
handle EU VAT and remit it. Do not wire Stripe directly unless you want to file
VAT returns yourself.

| | cut | notes |
|---|---|---|
| **Polar** | 4% + 40¢ | developer-first, good licence-key API, the easiest of these |
| **Lemon Squeezy** | 5% + 50¢ | Stripe-owned now, mature licence API |
| **Paddle** | ~5% + 50¢ | heavier, aimed at bigger sellers |
| **Gumroad** | 10% | simplest to set up, most expensive to keep |

The app is **vendor-agnostic on purpose** — the endpoint is configuration, not
code, so switching providers never needs a new build:

```bash
cat > ~/.ambient/license.json <<'JSON'
{
  "endpoint": "https://api.polar.sh/v1/customer-portal/license-keys/validate",
  "product": "YOUR_PRODUCT_ID",
  "buyURL": "https://polar.sh/you/ambient"
}
JSON
```

Settings shows a licence field only once that file exists. It POSTs
`{"key": ..., "product": ...}` and accepts any JSON answer containing a truthy
`valid` / `activated` / `status` — vendors all spell success differently and a
rename should not brick paying users. A valid key is stored in the Keychain and
flips the plan to Pro.

---

## The honest part

`product/offers.html` already holds nine monetization architectures with sourced
2026 numbers, and the conclusion there was **free notarized app as a lead magnet
for the $20K practice, product revenue $0 by design** — because on-device plus
bring-your-own-key means zero marginal cost per user.

Two facts that have not changed:

- **aloud.sh ships this free and does more** — voice plus screen plus transcript,
  rewrites, disambiguates, exports to Claude Code and Cursor, on-device Whisper.
- **Pricing is downstream of the install.** No offer survives an install that
  looks broken, and right now the install *is* broken for anyone but you.

So the sequence that makes sense is: enrol, notarize, put it in five friends'
hands free, and watch whether they open it a second time. If they do, the
licence plumbing above is already there. If they don't, you have saved yourself
a pricing page for a product nobody reopened.

Paid tier as it stands: 100 notes free, then 25/month, €15/mo for unlimited —
metered at export, never at capture.

---

## Today

```bash
cd "~/Claude 1/ambient" && ./release.sh 0.2
```

Produces `dist/Ambient-0.2.zip` plus a SHA-256. Openable by you and by anyone
willing to right-click → Open. That is enough to test the loop with one or two
patient friends while the Developer ID is in flight.
