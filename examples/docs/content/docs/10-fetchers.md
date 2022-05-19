# Fetchers

The difference between a Fetcher and the built-in submission/page reloading Effects/Msg's is:

## Fetcher

- Doesn't cause a page change ever
- Gives you a Msg back when the data arrives
- Can have multiple concurrent fetchers

## Non-Fetcher

- Available through static argument in view/init/update (not a Msg), so you don't need to keep anything in your Model (the static.data : Data and static.action : Maybe ActionData)
- Only one in-flight at once
- Can cause a page navigation

So if you don't want to keep things in your Model at all, you just don't use fetchers, and you can have a dynamic app with client-side submissions where the client-side state is entirely owned by elm-pages by accessible to the user
