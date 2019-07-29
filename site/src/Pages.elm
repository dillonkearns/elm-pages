module Pages exposing (Flags, Parser, Program, program)

import Browser
import Browser.Navigation
import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes
import Json.Decode
import Json.Encode
import Mark
import MarkParser
import Pages.Content as Content exposing (Content)
import Pages.HeadTag exposing (HeadTag)
import Pages.Parser exposing (PageOrPost)
import Platform.Sub exposing (Sub)
import Url exposing (Url)


type alias Content =
    List ( List String, String )


type alias Program userFlags userModel userMsg metadata view =
    Platform.Program (Flags userFlags) (Model userModel userMsg metadata view) (Msg userMsg)


mainView :
    (userModel -> PageOrPost metadata view -> { title : String, body : Html userMsg })
    -> Model userModel userMsg metadata view
    -> { title : String, body : Html userMsg }
mainView pageOrPostView (Model model) =
    case model.parsedContent of
        Ok site ->
            pageView pageOrPostView (Model model) site

        Err errorView ->
            { title = "Error parsing"
            , body = errorView
            }


pageView :
    (userModel -> PageOrPost metadata view -> { title : String, body : Html userMsg })
    -> Model userModel userMsg metadata view
    -> Content.Content metadata view
    -> { title : String, body : Html userMsg }
pageView pageOrPostView (Model model) content =
    case Content.lookup content model.url of
        Just pageOrPost ->
            pageOrPostView model.userModel pageOrPost

        Nothing ->
            { title = "Page not found"
            , body =
                Html.div []
                    [ Html.text "Page not found. Valid routes:\n\n"
                    , content
                        |> List.map Tuple.first
                        |> List.map (String.join "/")
                        |> String.join ", "
                        |> Html.text
                    ]
            }


view :
    Content
    -> Parser metadata view
    -> (userModel -> PageOrPost metadata view -> { title : String, body : Html userMsg })
    -> Model userModel userMsg metadata view
    -> Browser.Document (Msg userMsg)
view content parser pageOrPostView (Model model) =
    let
        { title, body } =
            mainView pageOrPostView (Model model)
    in
    { title = title
    , body =
        [ body
            |> Html.map UserMsg
        ]
    }


encodeHeadTags : List HeadTag -> Json.Encode.Value
encodeHeadTags headTags =
    Json.Encode.list Pages.HeadTag.toJson headTags


type alias Flags userFlags =
    { userFlags
        | imageAssets : Json.Decode.Value
    }


init :
    String
    -> (Json.Encode.Value -> Cmd (Msg userMsg))
    -> (String -> metadata -> List HeadTag)
    -> Parser metadata view
    -> Content
    -> (Flags userFlags -> ( userModel, Cmd userMsg ))
    -> Flags userFlags
    -> Url
    -> Browser.Navigation.Key
    -> ( Model userModel userMsg metadata view, Cmd (Msg userMsg) )
init siteUrl toJsPort headTags parser content initUserModel flags url key =
    let
        ( userModel, userCmd ) =
            initUserModel flags

        imageAssets =
            Json.Decode.decodeValue
                (Json.Decode.dict Json.Decode.string)
                flags.imageAssets
                |> Result.withDefault Dict.empty

        metadata =
            Content.parseMetadata parser imageAssets content
    in
    case metadata of
        Ok okMetadata ->
            ( Model
                { key = key
                , url = url
                , imageAssets = imageAssets
                , userModel = userModel
                , parsedContent =
                    metadata
                        |> Result.andThen
                            (\m ->
                                Content.buildAllData m parser imageAssets content
                            )
                }
            , Cmd.batch
                ([ Content.lookup okMetadata url
                    |> Maybe.map
                        (headTags
                            (siteUrl ++ url.path)
                        )
                    |> Maybe.map encodeHeadTags
                    |> Maybe.map toJsPort
                 , userCmd |> Cmd.map UserMsg |> Just
                 ]
                    |> List.filterMap identity
                )
            )

        Err _ ->
            ( Model
                { key = key
                , url = url
                , imageAssets = imageAssets
                , userModel = userModel
                , parsedContent =
                    metadata
                        |> Result.andThen
                            (\m ->
                                Content.buildAllData m parser imageAssets content
                            )
                }
            , Cmd.batch
                [ userCmd |> Cmd.map UserMsg
                ]
              -- TODO handle errors better
            )


type Msg userMsg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | UserMsg userMsg


type Model userModel userMsg metadata view
    = Model
        { key : Browser.Navigation.Key
        , url : Url.Url
        , imageAssets : Dict String String
        , parsedContent : Result (Html userMsg) (Content.Content metadata view)
        , userModel : userModel
        }


update :
    (userMsg -> userModel -> ( userModel, Cmd userMsg ))
    -> Msg userMsg
    -> Model userModel userMsg metadata view
    -> ( Model userModel userMsg metadata view, Cmd (Msg userMsg) )
update userUpdate msg (Model model) =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( Model model, Browser.Navigation.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( Model model, Browser.Navigation.load href )

        UrlChanged url ->
            ( Model { model | url = url }
            , Cmd.none
            )

        UserMsg userMsg ->
            let
                ( userModel, userCmd ) =
                    userUpdate userMsg model.userModel
            in
            ( Model { model | userModel = userModel }, userCmd |> Cmd.map UserMsg )


type alias Parser metadata view =
    Dict String String
    -> List String
    -> List ( List String, metadata )
    -> Mark.Document (PageOrPost metadata view)


program :
    { init : Flags userFlags -> ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> PageOrPost metadata view -> { title : String, body : Html userMsg }
    , parser : Parser metadata view
    , content : Content
    , toJsPort : Json.Encode.Value -> Cmd (Msg userMsg)
    , headTags : String -> metadata -> List HeadTag
    , siteUrl : String
    }
    -> Program userFlags userModel userMsg metadata view
program config =
    Browser.application
        { init = init config.siteUrl config.toJsPort config.headTags config.parser config.content config.init
        , view = view config.content config.parser config.view
        , update = update config.update
        , subscriptions =
            \(Model model) ->
                config.subscriptions model.userModel
                    |> Sub.map UserMsg
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }
