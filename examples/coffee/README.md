# Blendhaus — Test-Driven elm-pages Demo

A coffee shop built test-first with elm-pages. The companion to the
[Declarative Server State](https://elm-pages.com) blog post — except this
time every feature lands as a failing assertion in `Test.PagesProgram`'s
visual viewer before any route code is typed.

## Run it

```sh
npm install

# environment for the dev server
export HASURA_ADMIN_SECRET=...        # admin secret for loyal-mammal-32.hasura.app
export SESSION_SECRET=test-secret
export SMOOTHIES_SALT='$2a$10$...'    # bcryptjs salt used by hashPassword

# headless test run
npx elm-pages test

# dev server with the visual test runner
npx elm-pages dev
# → http://localhost:1234        (the shop)
# → http://localhost:1234/_tests (the test viewer)
```

## What's where

```
app/Route/
  Index.elm     -- the shop with optimistic cart (the showcase)
  Login.elm
  Signup.elm
  Checkout.elm

src/Data/       -- BackendTask wrappers around elm-graphql
  Coffee.elm        -- Coffee.all
  CoffeeCart.elm    -- Cart.get, Cart.addItemToCart
  CoffeeUser.elm    -- User.find, User.login, User.signup

src/Request/Hasura.elm  -- HASURA_ADMIN_SECRET env + GraphQL POST
src/MySession.elm       -- signed-cookie session + redirect helper
src/View/Coffee.elm     -- shell, hero, productCard, cartPanel, ...
src/View/Drink.elm      -- the seven hand-drawn SVG illustrations

tests/CoffeeTests.elm     -- the suite
tests/CoffeeFixtures.elm  -- JSON response builders
tests/CoffeeSteps.elm     -- composable Step lists
```

The route module is the demo's typed surface. Everything in `src/` and most
of `tests/` is "Martha Stewart prep" — pre-baked so the live coding stays
focused on `data`, `action`, forms, and `concurrentSubmissions`.

## Hasura schema

Parallel to the smoothie tables in the same `loyal-mammal-32` instance:

```sql
create table coffees (
  id uuid primary key default gen_random_uuid(),
  name text not null, tagline text not null, price integer not null,
  variant text not null, section text not null
);

create table coffee_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  ordered boolean not null default false, total integer not null default 0
);

create table coffee_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references coffee_orders(id) on delete cascade,
  coffee_id uuid not null references coffees(id) on delete cascade,
  quantity integer not null
);
```

`users` is shared with the smoothie shop.
