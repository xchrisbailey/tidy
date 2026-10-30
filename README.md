# Tidy landing page

Static GitHub Pages site for Tidy, maintained on the `gh-pages` branch. GitHub Pages
publishes the root of this branch. No build tools, JavaScript, analytics, or external
fonts are required.

Preview with `python3 -m http.server 8080` and open `http://localhost:8080`.

The icon reuses the approved `Packaging/Icons/Tidy.png` from the app's development
branch. The beta link points to the exact `v0.1.0-beta.1` release, not
`releases/latest`, because GitHub excludes prereleases from that redirect.
Keep the experimental warning and unqualified-hardware caveat. Publishing this
site does not itself publish or qualify an app build. Preserve the owner-managed CNAME.
