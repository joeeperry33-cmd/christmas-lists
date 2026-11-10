# Perry Family Christmas Lists

A simple site where each family member keeps a Christmas list.

- Everyone who signs in can see every list.
- Only you can add, edit, or remove items on your own list.
- Others can mark an item "I'll get this" so nobody double-buys. The list owner never sees claims.

## How it works

- `index.html` is the whole site (plain HTML + JavaScript), hosted on GitHub Pages.
- Logins and data live in Supabase (shared with the recipe-box project). Tables are prefixed `xmas_`.
- `supabase/schema.sql` creates the tables and the security rules that enforce who can edit what.

The Supabase key in `index.html` is the public "publishable" key; it's safe to be in the page because the database rules do the protecting.
