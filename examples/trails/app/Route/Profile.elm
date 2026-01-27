module Route.Profile exposing (ActionData, Data, Model, Msg, route)

import Api.InputObject
import Api.Mutation
import Api.Object exposing (Users)
import Api.Object.Users
import Api.Query
import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Graphql.Operation exposing (RootQuery)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Request.Hasura
import RouteBuilder exposing (StatefulRoute, StatelessRoute, App)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
import Time
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init :
    Maybe PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    { user : Profile
    }


type ActionData
    = Success
    | ValidationError String


data : RouteParams -> Request.Parser (BackendTask (Response Data ErrorPage))
data routeParams =
    Request.requestTime
        |> Request.map
            (\requestTime ->
                Request.Hasura.backendTask
                    (requestTime |> Time.posixToMillis |> String.fromInt)
                    profile
                    |> BackendTask.andThen
                        (\users ->
                            case users of
                                [ user ] ->
                                    BackendTask.succeed user

                                _ ->
                                    BackendTask.fail "Expected one user."
                        )
                    |> BackendTask.map
                        (\user -> Response.render { user = user })
            )


profile : SelectionSet (List Profile) RootQuery
profile =
    Api.Query.users
        (\optionals ->
            { optionals
                | where_ =
                    Present
                        (Api.InputObject.buildUsers_bool_exp
                            (\whereOptionals ->
                                { whereOptionals
                                    | id =
                                        Present
                                            (Api.InputObject.buildInt_comparison_exp
                                                (\compareOptionals ->
                                                    { compareOptionals
                                                        | eq_ = Present 1
                                                    }
                                                )
                                            )
                                }
                            )
                        )
            }
        )
        profileSelection


updateUser : Int -> Profile -> SelectionSet () Graphql.Operation.RootMutation
updateUser userId profileData =
    Api.Mutation.update_users_by_pk
        (\optionals ->
            { optionals
                | set_ =
                    Api.InputObject.buildUsers_set_input
                        (\user ->
                            { user
                                | first = Present profileData.first
                                , last = Present profileData.last
                                , username = Present profileData.username
                            }
                        )
                        |> Present
            }
        )
        { pk_columns = { id = userId } }
        --profileSelection
        SelectionSet.empty
        |> SelectionSet.nonNullOrFail


profileSelection : SelectionSet Profile Users
profileSelection =
    SelectionSet.map3 Profile
        Api.Object.Users.username
        Api.Object.Users.first
        Api.Object.Users.last


type alias Profile =
    { username : String
    , first : String
    , last : String
    }


action : RouteParams -> Request.Parser (BackendTask (Response ActionData ErrorPage))
action routeParams =
    Request.requestTime
        |> Request.andThen
            (\requestTime ->
                Request.expectFormPost
                    (\{ field } ->
                        Request.map3 Profile
                            (field "username")
                            (field "first")
                            (field "last")
                            |> Request.map
                                (\profileData ->
                                    let
                                        _ =
                                            Debug.log "action" profileData
                                    in
                                    Request.Hasura.mutationBackendTask
                                        (requestTime |> Time.posixToMillis |> String.fromInt)
                                        (updateUser 1 profileData)
                                        |> BackendTask.map
                                            (\_ ->
                                                Response.render Success
                                             --(ValidationError ("Username " ++ profileData.name ++ " is taken"))
                                            )
                                )
                    )
            )


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = static.data.user.first ++ "'s Profile"
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> App Data ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel model static =
    { title = "Profile"
    , body =
        [ errorsView static.action
        , Html.form
            [ Attr.method "POST"
            ]
            [ Html.div []
                [ Html.label []
                    [ Html.text "Username "
                    , Html.input
                        [ Attr.value static.data.user.username
                        , Attr.name "username"
                        ]
                        []
                    ]
                ]
            , Html.div []
                [ Html.label []
                    [ Html.text "First "
                    , Html.input
                        [ Attr.value static.data.user.first
                        , Attr.name "first"
                        ]
                        []
                    ]
                ]
            , Html.div []
                [ Html.label []
                    [ Html.text "Last "
                    , Html.input
                        [ Attr.value static.data.user.last
                        , Attr.name "last"
                        ]
                        []
                    ]
                ]
            , Html.button [] [ Html.text "Submit" ]
            ]
        ]
    }


errorsView : Maybe ActionData -> Html msg
errorsView maybeActionData =
    case maybeActionData of
        Just (ValidationError error) ->
            Html.div []
                [ Html.text error
                ]

        _ ->
            Html.div [] []
