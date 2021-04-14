port module TemplateModulesBeta exposing (..)

import Browser
import Route exposing (Route)
import Document
import Json.Decode
import Json.Encode
import Pages.Internal.Platform
import Pages.Internal.Platform.ToJsPayload
import Pages.Manifest as Manifest
import Shared
import Site
import Head
import Html exposing (Html)
import Pages.PagePath exposing (PagePath)
import Url
import Url.Parser as Parser exposing ((</>), Parser)
import Pages.StaticHttp as StaticHttp

import Template.Slide.Number_


type alias Model =
    { global : Shared.Model
    , page : TemplateModel
    , current :
        Maybe
            { path :
                { path : PagePath
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : Maybe Route
            }
    }


type TemplateModel
    = ModelSlide__Number_ Template.Slide.Number_.Model

    | NotFound




type Msg
    = MsgGlobal Shared.Msg
    | OnPageChange
        { path : PagePath
        , query : Maybe String
        , fragment : Maybe String
        , metadata : Maybe Route
        }
    | MsgSlide__Number_ Template.Slide.Number_.Msg



view :
    { path : PagePath
    , frontmatter : Maybe Route
    }
    ->
        StaticHttp.Request
            { view : Model -> { title : String, body : Html Msg }
            , head : List Head.Tag
            }
view page =
    case page.frontmatter of
        Nothing ->
            StaticHttp.fail <| "Page not found: " ++ Pages.PagePath.toString page.path
        Just (Route.Slide__Number_ s) ->
            StaticHttp.map2
                (\data globalData ->
                    { view =
                        \model ->
                            case model.page of
                                ModelSlide__Number_ subModel ->
                                    Template.Slide.Number_.template.view
                                        subModel
                                        model.global
                                        { static = data
                                        , sharedStatic = globalData
                                        , routeParams = s
                                        , path = page.path
                                        }
                                        |> (\{ title, body } ->
                                                Shared.template.view
                                                    globalData
                                                    page
                                                    model.global
                                                    MsgGlobal
                                                    ({ title = title, body = body }
                                                        |> Document.map MsgSlide__Number_
                                                    )
                                           )

                                _ ->
                                    { title = "Model mismatch", body = Html.text <| "Model mismatch" }
                    , head = Template.Slide.Number_.template.head
                        { static = data
                        , sharedStatic = globalData
                        , routeParams = s
                        , path = page.path
                        }
                    }
                )
                (Template.Slide.Number_.template.staticData s)
                (Shared.template.staticData)



init :
    Maybe Shared.Model
    ->
        Maybe
            { path :
                { path : PagePath
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : Maybe Route
            }
    -> ( Model, Cmd Msg )
init currentGlobalModel maybePagePath =
    let
        ( sharedModel, globalCmd ) =
            currentGlobalModel |> Maybe.map (\m -> ( m, Cmd.none )) |> Maybe.withDefault (Shared.template.init maybePagePath)

        ( templateModel, templateCmd ) =
            case maybePagePath |> Maybe.andThen .metadata of
                Nothing ->
                    ( NotFound, Cmd.none )

                Just (Route.Slide__Number_ routeParams) ->
                    Template.Slide.Number_.template.init routeParams
                        |> Tuple.mapBoth ModelSlide__Number_ (Cmd.map MsgSlide__Number_)


    in
    ( { global = sharedModel
      , page = templateModel
      , current = maybePagePath
      }
    , Cmd.batch
        [ templateCmd
        , globalCmd |> Cmd.map MsgGlobal
        ]
    )



update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        MsgGlobal msg_ ->
            let
                ( sharedModel, globalCmd ) =
                    Shared.template.update msg_ model.global
            in
            ( { model | global = sharedModel }
            , globalCmd |> Cmd.map MsgGlobal
            )

        OnPageChange record ->
            (init (Just model.global) <|
                Just
                    { path =
                        { path = record.path
                        , query = record.query
                        , fragment = record.fragment
                        }
                    , metadata = record.metadata
                    }
            )
                |> (\( updatedModel, cmd ) ->
                        case Shared.template.onPageChange of
                            Nothing ->
                                ( updatedModel, cmd )

                            Just thingy ->
                                let
                                    ( updatedGlobalModel, globalCmd ) =
                                        Shared.template.update
                                            (thingy
                                                { path = record.path
                                                , query = record.query
                                                , fragment = record.fragment
                                                }
                                            )
                                            model.global
                                in
                                ( { updatedModel
                                    | global = updatedGlobalModel
                                  }
                                , Cmd.batch [ cmd, Cmd.map MsgGlobal globalCmd ]
                                )
                   )


        
        MsgSlide__Number_ msg_ ->
            let
                ( updatedPageModel, pageCmd, ( newGlobalModel, newGlobalCmd ) ) =
                    case ( model.page, model.current |> Maybe.andThen .metadata ) of
                        ( ModelSlide__Number_ pageModel, Just (Route.Slide__Number_ routeParams) ) ->
                            Template.Slide.Number_.template.update
                                routeParams
                                msg_
                                pageModel
                                model.global
                                |> mapBoth ModelSlide__Number_ (Cmd.map MsgSlide__Number_)
                                |> (\( a, b, c ) ->
                                        case c of
                                            Just sharedMsg ->
                                                ( a, b, Shared.template.update (Shared.SharedMsg sharedMsg) model.global )

                                            Nothing ->
                                                ( a, b, ( model.global, Cmd.none ) )
                                   )

                        _ ->
                            ( model.page, Cmd.none, ( model.global, Cmd.none ) )
            in
            ( { model | page = updatedPageModel, global = newGlobalModel }
            , Cmd.batch [ pageCmd, newGlobalCmd |> Cmd.map MsgGlobal ]
            )



type alias SiteConfig =
    { canonicalUrl : String
    , manifest : Manifest.Config
    }

templateSubscriptions : Route -> PagePath -> Model -> Sub Msg
templateSubscriptions route path model =
    case ( model.page, route ) of
        
        ( ModelSlide__Number_ templateModel, Route.Slide__Number_ routeParams ) ->
            Template.Slide.Number_.template.subscriptions
                routeParams
                path
                templateModel
                model.global
                |> Sub.map MsgSlide__Number_



        _ ->
            Sub.none


main : Pages.Internal.Platform.Program Model Msg (Maybe Route)
main =
    Pages.Internal.Platform.application
        { init = init Nothing
        , urlToRoute = Route.urlToRoute
        , routeToPath = Route.routeToPath
        , site = Site.config
        , getStaticRoutes = getStaticRoutes
        , view = view
        , update = update
        , subscriptions =
            \path model ->
                Sub.batch
                    [ Shared.template.subscriptions path model.global |> Sub.map MsgGlobal
                    -- , templateSubscriptions (Route.Blog {}) path model
                    ]
        , onPageChange = Just OnPageChange
        , canonicalSiteUrl = "TODO"
        , toJsPort = toJsPort
        , fromJsPort = fromJsPort identity
        , generateFiles =
            getStaticRoutes
                |> StaticHttp.andThen
                    (\resolvedStaticRoutes ->
                        StaticHttp.map2 (::)
                            (manifestGenerator
                                resolvedStaticRoutes
                            )
                            (Site.config
                                resolvedStaticRoutes
                                |> .generateFiles
                            )
                    )
        }


getStaticRoutes =
    StaticHttp.combine
        [ StaticHttp.succeed
            [ 
            ]
        , Template.Slide.Number_.template.staticRoutes |> StaticHttp.map (List.map Route.Slide__Number_)
        ]
        |> StaticHttp.map List.concat
        |> StaticHttp.map (List.map Just)


manifestGenerator : List ( Maybe Route ) -> StaticHttp.Request (Result anyError { path : List String, content : String })
manifestGenerator resolvedRoutes =
    Site.config resolvedRoutes
        |> .staticData
        |> StaticHttp.map
            (\data ->
                (Site.config resolvedRoutes |> .manifest) data
                    |> manifestToFile ((Site.config resolvedRoutes |> .canonicalUrl) data)
            )


manifestToFile : String -> Manifest.Config -> Result anyError { path : List String, content : String }
manifestToFile resolvedCanonicalUrl manifestConfig =
    manifestConfig
        |> Manifest.toJson resolvedCanonicalUrl
        |> (\manifestJsonValue ->
                Ok
                    { path = [ "manifest.json" ]
                    , content = Json.Encode.encode 0 manifestJsonValue
                    }
           )



port toJsPort : Json.Encode.Value -> Cmd msg

port fromJsPort : (Json.Decode.Value -> msg) -> Sub msg


mapDocument : Browser.Document Never -> Browser.Document mapped
mapDocument document =
    { title = document.title
    , body = document.body |> List.map (Html.map never)
    }


mapBoth fnA fnB ( a, b, c ) =
    ( fnA a, fnB b, c )
