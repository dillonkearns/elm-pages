---
{
  "author": "Dillon Kearns",
  "title": "A time-traveling full-stack test debugger",
  "description": "Test.PagesProgram introduces end-to-end testing for elm-pages Route Modules",
  "published": "2026-04-29",
  "unsplash": "1447069387593-a5de0862481e"
}
---

Between Elm's purity, the full-stack Elm in [The `elm-pages` Architecture](/docs/architecture), and the [Use the Platform philosophy](/docs/use-the-platform), the latest `elm-pages` release brings a new testing experience that is uniquely made possible with this convergence of design choices.

You can try it out right now:

- Write a test using the new [`Test.PagesProgram`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Test-PagesProgram) API (more info in the docs there)
- Run tests headlessly with `npx elm-pages test`, OR
- Start your dev server with `npx elm-pages dev` and open up `localhost:1234/_tests` to explore them with the interactive test debugger!


![Scrubbing through the repeat-toggle test in the viewer](/repeat-toggle.gif)


## Purity + Realism -> Confidence + Clarity

### Purity

Early on in Elm's release, the time traveling debugger made a splash. It presented a uniquely powerful way to debug your app state, yet one that trivially and robustly fell out of The Elm Architecture. Because your Elm app is just a set of pure functions operating on immutable data, and the Elm runtime handles all of the managed effects you tell it to perform by returning `Cmd`s, a time traveling debugger is a natural thing to build. You can even think of the timeline of events as your initial `Model` state from `init`, and then a series of changes to your `Model` by saving and replaying every `Msg` your app sends.
Your `view` function gives you the exact `view` to render given a `Model` state. Since `init` and `update` are pure functions, you now have a deterministic way to replay all of your app states.

### Realism

With `elm-pages`, you are still working with pure functions, but now we are dealing with full-stack Elm apps. When you navigate to a page, a Route Module resolves its `data` function's `BackendTask` to get initial data from the server.

The key ingredients are:

- `data` (resolved backend data that is sent to the client-side `init` function)
- Form submissions (fetchers, all in-flight form submissions are in `app.concurrentSubmissions` - after a successful form submission, the `data` function reloads the page's data)
- Cookies and signed sessions
- Redirect responses
- [Error Page](/docs/error-pages/)s

### Confidence

The more that we can realistically test in our code without sacrificing speed and determinism, the better. The `Test.PagesProgram` API defines tests as pure functions just like a vanilla `Test` in Elm, so it is completely deterministic. That does mean that we can't reach out to the outside world, so no hitting your database, external HTTP service, etc. However, beyond that, you can see the realistic behavior of your `elm-pages` app because the cookie state, server redirect responses, etc. are all faithfully simulated in the test runner. This is the same approach that `elm-program-test` uses, but applied to the full-stack Elm framework features in `elm-pages`. We even run your app's full Vite configuration so you can see what your page will actually look like in production. The `lamdera/program-test` tool was a big inspiration for this idea that you could emulate framework behavior in pure tests.

While there is value to testing your application all the way through the actual database queries, it is inherently prone to flakiness, slow test runs, and difficult setup. Having pure tests that give complete realism for everything but the outside world has a lot of value because they are a lot more lightweight, plus they allow you to more easily recreate specific outside world conditions in your test cases.


### Clarity

Now that we have highly realistic, and completely deterministic full-stack tests, what can we do with that? The purity of Elm gives us yet another benefit here. We can easily peek into the framework states at any given step.


Not only is an elm-pages test suite a great way to develop features with TDD and prevent regressions, but I would now recommend this as a great way to understand and debug your app's states and to understand the elm-pages architecture overall.

The `elm-pages` visual test viewer gives you several tabs that allow you to inspect the state of your app:

- Network
- Data
- Fetchers
- Cookies
- Effects

![Inspecting step 8 of the repeat-toggle test](/repeat-toggle.png)

## An Example

Let's walk through a single test to make this concrete for the `examples/todo` app, which is a version of the TodoMVC app but as a full-stack app with database persistence.

Optimistic UI (showing immediate UI updates before we get the roundtrip from the server confirming that the database updates landed) can be tricky to test all the edge cases. It's the perfect candidate for end-to-end testing.

Let's write a test checking what happens when we click a todo checkbox to toggle an item 3 times, THEN the resolved server response comes back. If we designed it right, we should see:

- The todo list loads, let's say it contains an incomplete item "Buy milk" (we provide a fake database response to include this item in our test)
- We click "Buy milk" 3 times, making it go from incomplete -> complete -> incomplete -> complete (fetchers still in-flight, frontend state is still optimstic about server succeeding)
- Then we say the server returns with the state saying complete and the UI lands in that final state


```elm
suite = 
    PagesProgram.test "repeats toggles on a single item"
        startAfterMagicLink
        [ finishMagicLinkLoginAndLoadTodos todosResponse
        , ensureItemsLeft 2
        , PagesProgram.group "Toggle todo 3x (optimistic)"
            [ toggleTodo "Buy milk"
            , ensureItemsLeft 1
            , toggleTodo "Buy milk"
            , ensureItemsLeft 2
            , toggleTodo "Buy milk"
            , ensureItemsLeft 1
            , PagesProgram.withinFind
                [ PSelector.tag "li"
                , PSelector.containing [ PSelector.attribute (Attr.value "Buy milk") ]
                ]
                [ PagesProgram.ensureViewHas [ PSelector.class "completed" ] ]
            ]
        , PagesProgram.group "Resolve three fetchers + reload"
            [ simulateToggle
            , simulateToggle
            , simulateToggle
            , PagesProgram.simulateCustom "getTodosBySession" reloadedTodos
            , ensureItemsLeft 1
            , PagesProgram.withinFind
                [ PSelector.tag "li"
                , PSelector.containing [ PSelector.attribute (Attr.value "Buy milk") ]
                ]
                [ PagesProgram.ensureViewHas [ PSelector.class "completed" ] ]
            ]
        ]


toggleTodo : String -> TestApp.Step
toggleTodo description =
    PagesProgram.withinFind
        [ PSelector.tag "li"
        , PSelector.containing [ PSelector.attribute (Attr.value description) ]
        ]
        [ PagesProgram.clickButtonWith [ PSelector.class "toggle" ] ]


ensureItemsLeft : Int -> TestApp.Step
ensureItemsLeft n =
    PagesProgram.withinFind
        [ PSelector.class "todo-count" ]
        [ PagesProgram.ensureViewHas [ PSelector.text (String.fromInt n) ] ]


simulateToggle : TestApp.Step
simulateToggle =
    PagesProgram.simulateCustom "setTodoCompletion" Encode.null
```


## Understanding the Test Debugger

There is a lot of information to look at, so lets break down what it all means and how to use it to understand your app state.

### The Timeline

Most importantly, the steps are presented in the left sidebar. This represents **a timeline of the states** that your app went through over the course of this test case. Every action in your tests (typing, clicking, simulating an `BackendTask` resolving a pending HTTP response) results in a new step, e.g. `4`. Any assertions within that get a letter within that state (`4a`, `4b`).

Whenever there is an interaction with or assertion against a given UI element, we highlight that element in green (and purple for the item we interact with, like clicking or typing text).

### Step Chips

Throughout the other tabs you will see these little boxes with numbers in them (let's call them Step Chips for short). Anywhere you see a Step Chip, you can click on it to navigate to that step in the timeline, just as if you clicked that step in the lefthand sidebar.

When a Step Chip is highlighted with a color background, that means it is the current step you are viewing. When it is highlighted with an outline, that means it is the current state but that state begin at an earlier step.

### Network Tab

In the Network tab, you can see a timeline of every `BackendTask` (both [HTTP](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask-Http) and [Custom](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask-Custom)), with the Step Chips showing when they were triggered and when they landed.

You can click on a request to inspect the HTTP request and response bodies and headers.

### Fetchers Tab

The Fetchers are the most important state for our optimistic UI. In the case of our todo item toggling its completion status, you can see that each step where we click (2, 3, 4) has a corresponding fetcher Step Chip with an up arrow. This means that the fetcher is submitting form data at that step. You can see the payload it is submitting underneath the Step Chips, and it changes as we click.

Note that `complete="on"` and `complete=""` may seem like odd choices to serialize `complete=true` and `complete=false`. But this is just the standard format for form encoded data for checkboxes. The nice thing here is that if we turn off JavaScript in our browser this submission will still work and the server understands it!


### Cookies Tab

### Data Tab

This lets you inspect your Route Module's resolved `BackendTask` and all other app state:

- `app` (`data`, `action`, `concurrentSubmissions`, etc.)
- `model`
- `shared`

You will see all of these values with their state at the step you are currently viewing. Plus navigating between steps will automatically expand and highlight changed values between steps.
