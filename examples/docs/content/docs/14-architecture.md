# The elm-pages Architecture

Let's look at the lifecycle of a request in an elm-pages app.

This will walk through 3 different interactions.

1. Open Page
2. Click Button
3. Submit Form

These 3 interactions show the key components of The elm-pages Architecture.

## Interaction 1 - Open Page

If we open our browser to a server-rendered `elm-pages` Route `https://my-app.com/feed`, it will render from our Route module `app/Route/Feed.elm`.

## 1a - Resolving `data`

1. `data` is resolved first
2. The `elm-pages` Engine resolves our `data`, performing HTTP requests, reading data, and running any custom tasks we've defined.
3. BackendTask's `BackendTask.Custom.run` are executed by running our `custom-backend-task` Node module, which `elm-pages` transpiles using `esbuild`.

![Step 1](/images/architecture-1.png)

## 1b - Rendering the Page

Now that we have our `data` from Step 1, we can render the page.

First, we will server-render the HTML. So the Browser will get an HTML page with all of our initial page content (not an empty shell).

This has some benefits for both performance and SEO. With a fully rendered HTML page, the initial page load allows the browser to start loading all of the images on the page immediately before parsing and hydrating the Elm app. It also means that we have a meaningful and interactive app before hydration.

Our `elm-pages` Backend takes the `data` resolved from Step 1, calls our Route Module's `init` to get any initial page state, and then calls our Route Module's `view` to render the HTML for the page. Note that `update` is never called by the Backend during server-side rendering, so we have a predictable `view` from our Backend.

![Step 2](/images/architecture-2.png)

## 1c - Hydration

Now that the browser has received the HTML from Step 1b, it can show the user a meaningful page, and then it's time for the next step - hydration.

![Step 3](/images/architecture-3.png)

## Interaction 2 - Client-Side Interaction

Client-side interactions that trigger a `Msg` in our Route Module go through the standard Elm Architecture lifecycle, calling `update` and re-rendering the `view` in the browser.

![Step 4](/images/architecture-4.png)

## Interaction 3 - Form Submission

![Step 5](/images/architecture-5.png)

## The Code

We could define our Route Module like this:

```elm
module Route.Feed exposing (ActionData, Data, Model, Msg, RouteParams, route)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import Effect
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field
import Form.Validation
import Head
import Html
import Html.Attributes
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import PagesMsg exposing (PagesMsg)
import Pages.Form
import RouteBuilder
import Server.Request
import Server.Response
import Server.Session
import Server.SetCookie
import Shared
import View


type alias Model =
    { showMenu : Bool }


type Msg
    = ToggleMenu


type alias RouteParams =
    {}


route : RouteBuilder.StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender { data = data, action = action, head = head }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , init = init
            , update = update
            , subscriptions = \_ _ _ _ -> Sub.none
            }


init :
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect.Effect Msg )
init app shared =
    ( { showMenu = False }, Effect.none )


update :
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect.Effect Msg )
update app shared msg model =
    case msg of
        ToggleMenu ->
            ( { model | showMenu = not model.showMenu }, Effect.none )


type alias Data =
    { user : User
    , posts : List Post
    }


type alias ActionData =
    {}


data :
    RouteParams
    -> Request
    -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    Server.Request.succeed ()
        |> Server.Session.withSession
            { name = "session"
            , options = Server.SetCookie.options
            , secrets = BackendTask.succeed [ "my-secret" ]
            }
            (\() sessionResult ->
                BackendTask.map2 Data
                    (getUser sessionResult)
                    (BackendTask.Custom.run "getPosts" Encode.null postsDecoder |> BackendTask.allowFatal)
                    |> BackendTask.map Server.Response.render
                    |> BackendTask.map (Tuple.pair (sessionResult |> Result.withDefault Server.Session.empty))
            )


head : RouteBuilder.App Data ActionData RouteParams -> List Head.Tag
head app =
    []


view :
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View.View (PagesMsg Msg)
view app shared model =
    { title = "Feed"
    , body =
        [ navbarView app.data.user ToggleMenu model.showMenu
        , postsView app
        ]
    }


postsView app =
    app.data.posts
        |> List.map (\post -> favoriteFormView app post)
        |> Html.div []


favoriteFormView app post =
    Pages.Form.renderHtml []
        (Form.options ("favorite-" ++ post.id)
            |> Form.withInput post.isFavorited
        )
        app


action :
    RouteParams
    -> Request
    -> BackendTask FatalError (Response ActionData ErrorPage)
action routeParams request =
    case request |> Server.Request.formData formHandlers of
        Just ( _, parsedForm ) ->
                case parsedForm of
                    Ok (ToggleFavorite validatedForm) ->
                        validatedForm.setFavorite
                            |> toggleFavorite
                            |> BackendTask.map (\() -> Server.Response.render {})

                    Err error ->
                        BackendTask.succeed (Server.Response.render {})

        Nothing ->
            BackendTask.succeed (Server.Response.render {})


toggleFavoriteForm : Form.HtmlForm String ToggleFavoriteForm Bool Msg
toggleFavoriteForm =
    (\setFavorite ->
        { combine =
            ToggleFavoriteForm
                |> Form.Validation.succeed
                |> Form.Validation.andMap setFavorite
        , view =
            \formState -> [ favoriteButton formState ]
        }
    )
        |> Form.init
        |> Form.hiddenKind ( "kind", "regular" ) "Expected kind."
        |> Form.hiddenField "set-favorite" Form.Field.checkbox


type Action
    = ToggleFavorite ToggleFavoriteForm


type alias ToggleFavoriteForm =
    { setFavorite : Bool }


formHandlers : Form.ServerForms String Action
formHandlers =
    Form.Handler.init ToggleFavorite toggleFavoriteForm
```
