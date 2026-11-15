module Route.HotData exposing (ActionData, Data, Model, Msg, route)

{-| A page whose data comes from files, for the hot data reloading tests
(`cypress/e2e/hot-data-reload.cy.js`). Those tests edit the files under
`hot-data/` while the page is open and check that the page shows exactly the
new data.

Some of the names have characters that mean something in a glob pattern
(`[2024]`, `[draft]`), to check that those files are watched like any other.
-}

import BackendTask exposing (BackendTask)
import BackendTask.File
import BackendTask.Glob as Glob
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Head
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr
import Html.Styled.Events as Events
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Shared
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    { count : Int
    }


type Msg
    = Increment


type alias RouteParams =
    {}


type alias ActionData =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildWithLocalState
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }


type alias Note =
    { name : String
    , body : String
    }


type alias Data =
    { notes : List Note

    -- The names of the files in `hot-data/archive [2024]`, from a glob that
    -- runs in that directory (`BackendTask.inDir`).
    , archive : List String

    -- Only used inside `View.freeze`.
    , frozenLines : List String
    }


data : BackendTask FatalError Data
data =
    BackendTask.map3 Data
        notes
        archive
        (BackendTask.File.rawFile "hot-data/frozen [draft].txt"
            |> BackendTask.allowFatal
            |> BackendTask.map nonEmptyLines
        )


notes : BackendTask FatalError (List Note)
notes =
    Glob.succeed
        (\name filePath ->
            BackendTask.File.rawFile filePath
                |> BackendTask.allowFatal
                |> BackendTask.map (\body -> { name = name, body = String.trim body })
        )
        |> Glob.match (Glob.literal "hot-data/notes/")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".txt")
        |> Glob.captureFilePath
        |> Glob.toBackendTask
        |> BackendTask.andThen BackendTask.combine
        |> BackendTask.map (List.sortBy .name)


archive : BackendTask FatalError (List String)
archive =
    Glob.succeed identity
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".txt")
        |> Glob.toBackendTask
        |> BackendTask.inDir "hot-data/archive [2024]"
        |> BackendTask.map List.sort


nonEmptyLines : String -> List String
nonEmptyLines text =
    text
        |> String.lines
        |> List.filter (\line -> String.trim line /= "")


init : App Data ActionData RouteParams -> Shared.Model -> ( Model, Effect Msg )
init _ _ =
    ( { count = 0 }, Effect.none )


update : App Data ActionData RouteParams -> Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update _ _ msg model =
    case msg of
        Increment ->
            ( { model | count = model.count + 1 }, Effect.none )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions _ _ _ _ =
    Sub.none


head : App Data ActionData RouteParams -> List Head.Tag
head _ =
    []


view : App Data ActionData RouteParams -> Shared.Model -> Model -> View (PagesMsg Msg)
view app _ model =
    { title = "Hot Data"
    , body =
        [ Html.h1 [] [ Html.text "Hot Data" ]
        , Html.p [ Attr.id "count" ] [ Html.text ("Count: " ++ String.fromInt model.count) ]
        , Html.button [ Events.onClick (PagesMsg.fromMsg Increment) ] [ Html.text "+" ]
        , Html.ul [ Attr.id "notes" ]
            (app.data.notes
                |> List.map
                    (\note ->
                        Html.li [] [ Html.text (note.name ++ ": " ++ note.body) ]
                    )
            )
        , Html.p [ Attr.id "archive" ] [ Html.text ("Archive: " ++ String.join ", " app.data.archive) ]
        , View.freeze (frozenView app.data.frozenLines)
        ]
    }


frozenView : List String -> Html Never
frozenView lines =
    Html.ul [ Attr.id "frozen" ]
        (lines |> List.map (\line -> Html.li [] [ Html.text line ]))
