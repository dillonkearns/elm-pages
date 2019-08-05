module Pages exposing (Flags, Parser, Program, application)

import Browser
import Browser.Navigation
import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes
import Json.Decode
import Json.Encode
import Mark
import Pages.Content as Content exposing (Content)
import Pages.Head as Head
import Pages.Parser exposing (Page)
import Platform.Sub exposing (Sub)
import Result.Extra
import Url exposing (Url)


type alias Content =
    { markdown : List ( List String, { frontMatter : String, body : String } ), markup : List ( List String, String ) }


type alias Program userFlags userModel userMsg metadata view =
    Platform.Program (Flags userFlags) (Model userModel userMsg metadata view) (Msg userMsg)


mainView :
    (userModel -> Page metadata view -> { title : String, body : Html userMsg })
    -> ModelDetails userModel userMsg metadata view
    -> { title : String, body : Html userMsg }
mainView pageOrPostView model =
    case model.parsedContent of
        Ok site ->
            pageView pageOrPostView model site

        Err errorView ->
            { title = "Error parsing"
            , body = errorView
            }


pageView :
    (userModel -> Page metadata view -> { title : String, body : Html userMsg })
    -> ModelDetails userModel userMsg metadata view
    -> Content.Content metadata view
    -> { title : String, body : Html userMsg }
pageView pageOrPostView model content =
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
    -> (userModel -> Page metadata view -> { title : String, body : Html userMsg })
    -> ModelDetails userModel userMsg metadata view
    -> Browser.Document (Msg userMsg)
view content parser pageOrPostView model =
    let
        { title, body } =
            mainView pageOrPostView model
    in
    { title = title
    , body =
        [ body
            |> Html.map UserMsg
        ]
    }


encodeHeads : List Head.Tag -> Json.Encode.Value
encodeHeads head =
    Json.Encode.list Head.toJson head


type alias Flags userFlags =
    { userFlags
        | imageAssets : Json.Decode.Value
    }


combineTupleResults :
    List ( List String, Result error success )
    -> Result error (List ( List String, success ))
combineTupleResults input =
    input
        |> List.map
            (\( path, result ) ->
                result
                    |> Result.map (\success -> ( path, success ))
            )
        |> Result.Extra.combine


init :
    (String -> view)
    -> Json.Decode.Decoder metadata
    -> (Json.Encode.Value -> Cmd (Msg userMsg))
    -> (metadata -> List Head.Tag)
    -> Parser metadata view
    -> Content
    -> (Flags userFlags -> ( userModel, Cmd userMsg ))
    -> Flags userFlags
    -> Url
    -> Browser.Navigation.Key
    -> ( ModelDetails userModel userMsg metadata view, Cmd (Msg userMsg) )
init markdownToHtml frontmatterParser toJsPort head parser content initUserModel flags url key =
    let
        ( userModel, userCmd ) =
            initUserModel flags

        imageAssets =
            Json.Decode.decodeValue
                (Json.Decode.dict Json.Decode.string)
                flags.imageAssets
                |> Result.withDefault Dict.empty

        parsedMarkdown =
            content.markdown
                |> List.map
                    (Tuple.mapSecond
                        (\{ frontMatter, body } ->
                            Json.Decode.decodeString frontmatterParser frontMatter
                                |> Result.map (\parsedFrontmatter -> { parsedFrontmatter = parsedFrontmatter, body = body })
                                |> Result.mapError
                                    (\error ->
                                        Html.text (Json.Decode.errorToString error)
                                    )
                        )
                    )

        metadata =
            [ Content.parseMetadata parser imageAssets content.markup
            , parsedMarkdown
                |> List.map (Tuple.mapSecond (Result.map (\{ parsedFrontmatter } -> parsedFrontmatter)))
                |> combineTupleResults
            ]
                |> Result.Extra.combine
                |> Result.map List.concat
    in
    case metadata of
        Ok okMetadata ->
            ( { key = key
              , url = url
              , imageAssets = imageAssets
              , userModel = userModel
              , parsedContent =
                    metadata
                        |> Result.andThen
                            (\m ->
                                [ Content.buildAllData m parser imageAssets content.markup
                                , parseMarkdown markdownToHtml parsedMarkdown
                                ]
                                    |> Result.Extra.combine
                                    |> Result.map List.concat
                            )
              }
            , Cmd.batch
                ([ Content.lookup okMetadata url
                    |> Maybe.map head
                    |> Maybe.map encodeHeads
                    |> Maybe.map toJsPort
                 , userCmd |> Cmd.map UserMsg |> Just
                 ]
                    |> List.filterMap identity
                )
            )

        Err _ ->
            ( { key = key
              , url = url
              , imageAssets = imageAssets
              , userModel = userModel
              , parsedContent =
                    metadata
                        |> Result.andThen
                            (\m ->
                                Content.buildAllData m parser imageAssets content.markup
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
    = Model (ModelDetails userModel userMsg metadata view)


type alias ModelDetails userModel userMsg metadata view =
    { key : Browser.Navigation.Key
    , url : Url.Url
    , imageAssets : Dict String String
    , parsedContent : Result (Html userMsg) (Content.Content metadata view)
    , userModel : userModel
    }


update :
    (userMsg -> userModel -> ( userModel, Cmd userMsg ))
    -> Msg userMsg
    -> ModelDetails userModel userMsg metadata view
    -> ( ModelDetails userModel userMsg metadata view, Cmd (Msg userMsg) )
update userUpdate msg model =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Browser.Navigation.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Browser.Navigation.load href )

        UrlChanged url ->
            ( { model | url = url }
            , Cmd.none
            )

        UserMsg userMsg ->
            let
                ( userModel, userCmd ) =
                    userUpdate userMsg model.userModel
            in
            ( { model | userModel = userModel }, userCmd |> Cmd.map UserMsg )


type alias Parser metadata view =
    Dict String String
    -> List String
    -> List ( List String, metadata )
    -> Mark.Document (Page metadata view)


application :
    { init : Flags userFlags -> ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> Page metadata view -> { title : String, body : Html userMsg }
    , parser : Parser metadata view
    , content : Content
    , toJsPort : Json.Encode.Value -> Cmd (Msg userMsg)
    , head : metadata -> List Head.Tag
    , frontmatterParser : Json.Decode.Decoder metadata
    , markdownToHtml : String -> view
    }
    -> Program userFlags userModel userMsg metadata view
application config =
    Browser.application
        { init =
            \flags url key ->
                init config.markdownToHtml config.frontmatterParser config.toJsPort config.head config.parser config.content config.init flags url key
                    |> Tuple.mapFirst Model
        , view = \(Model model) -> view config.content config.parser config.view model
        , update = \msg (Model model) -> update config.update msg model |> Tuple.mapFirst Model
        , subscriptions =
            \(Model model) ->
                config.subscriptions model.userModel
                    |> Sub.map UserMsg
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }


parseMarkdown :
    (String -> view)
    -> List ( List String, Result (Html msg) { parsedFrontmatter : metadata, body : String } )
    -> Result (Html msg) (Content.Content metadata view)
parseMarkdown markdownToHtml markdownContent =
    markdownContent
        |> List.map
            (Tuple.mapSecond
                (Result.map
                    (\{ parsedFrontmatter, body } ->
                        { metadata = parsedFrontmatter
                        , view = [ markdownToHtml body ]
                        }
                    )
                )
            )
        |> combineTupleResults
