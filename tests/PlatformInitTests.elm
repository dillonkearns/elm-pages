module PlatformInitTests exposing (all)

{-| How the browser app starts in the two cases that a browser test cannot
reach by visiting a page.

The usual cases (the first view is the page, or the not found page, and
navigation announces the new page's title) are tested in a real browser, in
`examples/end-to-end/cypress/e2e/first-render.cy.js`,
`cypress/production/first-render.cy.js` and `cypress/e2e/aria-announcer.cy.js`.

These two are left here:

  - The page data in the flags is a redirect. A browser never gets that from a
    visit, because the server answers with an HTTP redirect first.
  - There is no page data in the flags. `elm-pages.js` always passes it, but
    `Platform.init` (which `Test.PagesProgram` uses) starts this way.

-}

import BackendTask
import Bytes exposing (Bytes)
import Bytes.Decode
import Bytes.Encode
import Expect
import FatalError
import Html
import Json.Encode as Encode
import Pages.Internal.Platform as Platform
import Pages.Internal.ResponseSketch as ResponseSketch exposing (ResponseSketch)
import Pages.ProgramConfig exposing (ProgramConfig)
import Test exposing (Test, describe, test)
import Url exposing (Url)


all : Test
all =
    describe "Pages.Internal.Platform.initWithPageData"
        [ test "a redirect in the flags loads the page it points to" <|
            \() ->
                let
                    ( model, effect ) =
                        initWith (Just redirectResponse)
                in
                { pendingRedirect = model.pendingRedirect
                , waitingFor = model.pendingFrozenViewsUrl |> Maybe.map .path
                , fetches = fetchedPaths effect
                }
                    |> Expect.equal
                        { pendingRedirect = True
                        , waitingFor = Just "/elsewhere"
                        , fetches = [ "/elsewhere" ]
                        }
        , test "without page data in the flags, it waits for the data and then shows the page" <|
            \() ->
                let
                    ( waitingModel, _ ) =
                        initWith Nothing

                    ( model, _ ) =
                        Platform.update config (Platform.FrozenViewsReady (Just pageResponse)) waitingModel
                in
                { waitingAtFirst = waitingModel.pendingFrozenViewsUrl |> Maybe.map .path
                , title = (Platform.view config model).title
                , waitingForPageData = model.pendingFrozenViewsUrl /= Nothing
                }
                    |> Expect.equal
                        { waitingAtFirst = Just "/start"
                        , title = "Title for /start"
                        , waitingForPageData = False
                        }
        ]


initWith :
    Maybe Bytes
    -> ( Platform.Model () String () (), Platform.Effect () String () () () () )
initWith pageData =
    Platform.initWithPageData config
        { pageData = pageData, userFlags = Encode.null }
        (urlWithPath "/start")
        Nothing


fetchedPaths : Platform.Effect userMsg pageData actionData sharedData userEffect errorPage -> List String
fetchedPaths effect =
    case effect of
        Platform.FetchFrozenViews { path } ->
            [ path ]

        Platform.Batch effects ->
            List.concatMap fetchedPaths effects

        _ ->
            []


urlWithPath : String -> Url
urlWithPath path =
    { protocol = Url.Https
    , host = "example.com"
    , port_ = Nothing
    , path = path
    , query = Nothing
    , fragment = Nothing
    }



-- RESPONSES, in the made up format that `config.decodeResponse` reads


{-| What the server sends with a page's HTML.
-}
pageResponse : Bytes
pageResponse =
    response 0


redirectResponse : Bytes
redirectResponse =
    response 2


response : Int -> Bytes
response tag =
    Bytes.Encode.encode (Bytes.Encode.unsignedInt8 tag)


decodeResponse : Bytes.Decode.Decoder (ResponseSketch String () ())
decodeResponse =
    Bytes.Decode.unsignedInt8
        |> Bytes.Decode.andThen
            (\tag ->
                case tag of
                    0 ->
                        Bytes.Decode.succeed (ResponseSketch.HotUpdate "page data" () Nothing)

                    2 ->
                        Bytes.Decode.succeed (ResponseSketch.Redirect "/elsewhere")

                    _ ->
                        Bytes.Decode.fail
            )



-- CONFIG


{-| The route is the URL path, and each page's title says which route it is for.
-}
config : ProgramConfig () () String String () () () mappedMsg ()
config =
    { toJsPort = \_ -> Cmd.none
    , fromJsPort = Sub.none
    , init = \_ _ _ _ _ -> ( (), () )
    , getStaticRoutes = BackendTask.succeed []
    , handleRoute = \_ -> BackendTask.succeed Nothing
    , urlToRoute = .path
    , update = \_ _ _ _ _ _ _ _ -> ( (), () )
    , basePath = []
    , onActionData = \() -> Nothing
    , data = \_ _ -> BackendTask.fail (FatalError.fromString "Not used.")
    , site = Nothing
    , view =
        \_ _ _ page _ _ _ _ ->
            { view = \_ -> { title = "Title for " ++ page.route, body = [ Html.text "" ] }
            , head = []
            }
    , subscriptions = \_ _ _ -> Sub.none
    , routeToPath = String.split "/"
    , sharedData = BackendTask.succeed ()
    , onPageChange = \_ -> ()
    , apiRoutes = \_ -> []
    , pathPatterns = []
    , byteDecodePageData = \_ -> Bytes.Decode.fail
    , sendPageData = \_ -> Cmd.none
    , encodeResponse = \_ -> Bytes.Encode.signedInt8 0
    , hotReloadData = Sub.none
    , pageDataFromJs = Sub.none
    , decodeResponse = decodeResponse
    , byteEncodePageData = \_ -> Bytes.Encode.signedInt8 0
    , gotBatchSub = Sub.none
    , globalHeadTags = Nothing
    , perform = \_ _ -> Cmd.none
    , cmdToEffect = \_ -> ()
    , errorStatusCode = \_ -> 404
    , notFoundPage = ()
    , notFoundRoute = "/not-found"
    , internalError = \_ -> ()
    , errorPageToData = \_ -> ""
    , action = \_ _ -> BackendTask.fail (FatalError.fromString "Not used.")
    , encodeAction = \_ -> Bytes.Encode.signedInt8 0
    , pageModelToString = \_ -> ""
    }
