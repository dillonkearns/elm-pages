module ProgramTest.Program exposing (Program, renderView)

import Dict exposing (Dict)
import Html exposing (Html)
import Test.Html.Query as Query
import Url exposing (Url)


{-| Since we can't inspect `Platform.Program`s in Elm,
this type represents the same thing as a record that we can access.

Note that we also parameterize `effect` and `sub` separately because
`Platform.Cmd` and `Platform.Sub` are not inspectable in Elm.

-}
type alias Program model msg effect sub =
    { update : msg -> model -> ( model, effect )
    , view : model -> Html msg
    , onRouteChange : Url -> Maybe msg
    , subscriptions : Maybe (model -> sub)
    , withinFocus : Query.Single msg -> Query.Single msg
    , onFormSubmit : Maybe (Dict String String -> effect)
    }


renderView : Program model msg effect sub -> model -> Query.Single msg
renderView program model =
    program.view model
        |> Query.fromHtml
        |> program.withinFocus
