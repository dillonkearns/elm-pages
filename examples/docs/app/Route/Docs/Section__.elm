module Route.Docs.Section__ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.File
import BackendTask.Glob as Glob exposing (Glob)
import DocsSection exposing (Section)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Heroicon
import Html exposing (Html)
import Html.Attributes as Attr
import List.Extra
import Markdown.Block as Block exposing (Block)
import Markdown.Parser
import Markdown.Renderer
import MarkdownCodec
import NextPrevious
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import TableOfContents
import TailwindMarkdownRenderer
import Url
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { section : Maybe String }


{-| Data type with both persistent and ephemeral fields.

  - `titles`, `metadata`: Used in head and view title (persistent)
  - `body`, `previousAndNext`, `editUrl`: Used only inside View.freeze (ephemeral, DCE'd)

-}
type alias Data =
    { titles : { title : String }
    , metadata : { title : String, description : String }
    , body : List Block
    , previousAndNext : ( Maybe NextPrevious.Item, Maybe NextPrevious.Item )
    , editUrl : String
    }


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }
        |> RouteBuilder.buildNoState
            { view = view
            }


pages : BackendTask FatalError (List RouteParams)
pages =
    DocsSection.all
        |> BackendTask.map
            (List.map
                (\section ->
                    { section = Just section.slug }
                )
            )
        |> BackendTask.map
            (\sections ->
                { section = Nothing } :: sections
            )


data : RouteParams -> BackendTask FatalError Data
data routeParams =
    BackendTask.map4
        (\titles metadata body editUrl ->
            { titles = { title = titles.title }
            , metadata = metadata
            , body = body
            , previousAndNext = titles.previousAndNext
            , editUrl = editUrl
            }
        )
        (previousAndNextData routeParams)
        (routeParams |> filePathBackendTask |> BackendTask.andThen MarkdownCodec.titleAndDescription)
        (pageBody routeParams)
        (routeParams.section
            |> Maybe.withDefault "what-is-elm-pages"
            |> findBySlug
            |> Glob.expectUniqueMatch
            |> BackendTask.map filePathToEditUrl
            |> BackendTask.allowFatal
        )


filePathToEditUrl : String -> String
filePathToEditUrl filePath =
    "https://github.com/dillonkearns/elm-pages/edit/master/examples/docs/" ++ filePath


previousAndNextData : RouteParams -> BackendTask FatalError { title : String, previousAndNext : ( Maybe NextPrevious.Item, Maybe NextPrevious.Item ) }
previousAndNextData current =
    DocsSection.all
        |> BackendTask.andThen
            (\sections ->
                let
                    index : Int
                    index =
                        sections
                            |> List.Extra.findIndex (\section -> Just section.slug == current.section)
                            |> Maybe.withDefault 0
                in
                BackendTask.map2 (\title previousAndNext -> { title = title, previousAndNext = previousAndNext })
                    (List.Extra.getAt index sections
                        |> maybeBackendTask titleForSection
                        |> BackendTask.map (Result.fromMaybe (FatalError.fromString "Couldn't find section"))
                        |> BackendTask.andThen BackendTask.fromResult
                        |> BackendTask.map .title
                    )
                    (BackendTask.map2 Tuple.pair
                        (List.Extra.getAt (index - 1) sections
                            |> maybeBackendTask titleForSection
                        )
                        (List.Extra.getAt (index + 1) sections
                            |> maybeBackendTask titleForSection
                        )
                    )
            )


maybeBackendTask : (a -> BackendTask error b) -> Maybe a -> BackendTask error (Maybe b)
maybeBackendTask fn maybe =
    case maybe of
        Just just ->
            fn just |> BackendTask.map Just

        Nothing ->
            BackendTask.succeed Nothing


titleForSection : Section -> BackendTask FatalError NextPrevious.Item
titleForSection section =
    Glob.expectUniqueMatch (findBySlug section.slug)
        |> BackendTask.allowFatal
        |> BackendTask.andThen
            (\filePath ->
                BackendTask.File.bodyWithoutFrontmatter filePath
                    |> BackendTask.allowFatal
                    |> BackendTask.andThen markdownBody
                    |> BackendTask.map
                        (\blocks ->
                            List.Extra.findMap
                                (\block ->
                                    case block of
                                        Block.Heading Block.H1 inlines ->
                                            Just
                                                { title = Block.extractInlineText inlines
                                                , slug = section.slug
                                                }

                                        _ ->
                                            Nothing
                                )
                                blocks
                        )
            )
        |> BackendTask.andThen
            (\maybeTitle ->
                maybeTitle
                    |> Result.fromMaybe (FatalError.fromString "Expected to find an H1 heading in this markdown.")
                    |> BackendTask.fromResult
            )


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url =
                Pages.Url.external <|
                    "https://i.microlink.io/https%3A%2F%2Fcards.microlink.io%2F%3Fpreset%3Dcontentz%26title%3Delm-pages%2Bdocs%26description%3D"
                        ++ Url.percentEncode app.data.titles.title
            , alt = "elm-pages docs section title"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = app.data.metadata.description
        , locale = Nothing
        , title = app.data.titles.title ++ " | elm-pages docs"
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app sharedModel =
    { title = app.data.titles.title ++ " - elm-pages docs"
    , body =
        [ Html.div
            [ Attr.class "flex flex-1 h-full"
            ]
            [ TableOfContents.view sharedModel.showMobileMenu True app.routeParams.section app.sharedData
            , Html.article
                [ Attr.class "prose max-w-xl relative pt-20 pb-16 px-6 w-full max-w-full overflow-x-hidden md:px-8"
                ]
                [ -- Frozen content - fields accessed only here are removed from client Data type
                  View.freeze (renderStaticContent app.data.body app.data.previousAndNext app.data.editUrl)
                ]
            ]
        ]
    }


{-| Render the article content as a frozen view.
All of this code is eliminated from the client bundle via DCE.
-}
renderStaticContent : List Block -> ( Maybe NextPrevious.Item, Maybe NextPrevious.Item ) -> String -> Html Never
renderStaticContent body previousAndNext editUrl =
    Html.div
        [ Attr.class "max-w-screen-md mx-auto xl:pr-36"
        ]
        ((body
            |> Markdown.Renderer.render TailwindMarkdownRenderer.renderer
            |> Result.withDefault []
         )
            ++ [ NextPrevious.view previousAndNext
               , Html.hr [] []
               , Html.footer
                    [ Attr.class "text-right"
                    ]
                    [ Html.a
                        [ Attr.href editUrl
                        , Attr.rel "noopener"
                        , Attr.target "_blank"
                        , Attr.class "text-sm hover:!text-gray-800 !text-gray-500 flex items-center float-right"
                        ]
                        [ Html.span [ Attr.class "pr-1" ] [ Html.text "Suggest an edit on GitHub" ]
                        , Heroicon.edit
                        ]
                    ]
               ]
        )


filePathBackendTask : RouteParams -> BackendTask FatalError String
filePathBackendTask routeParams =
    let
        slug : String
        slug =
            routeParams.section
                |> Maybe.withDefault "what-is-elm-pages"
    in
    Glob.expectUniqueMatch (findBySlug slug)
        |> BackendTask.allowFatal


pageBody : RouteParams -> BackendTask FatalError (List Block)
pageBody routeParams =
    routeParams
        |> filePathBackendTask
        |> BackendTask.andThen
            (MarkdownCodec.withoutFrontmatter TailwindMarkdownRenderer.renderer)


findBySlug : String -> Glob String
findBySlug slug =
    Glob.succeed identity
        |> Glob.captureFilePath
        |> Glob.match (Glob.literal "content/docs/")
        |> Glob.match Glob.int
        |> Glob.match (Glob.literal "-")
        |> Glob.match (Glob.literal slug)
        |> Glob.match (Glob.literal ".md")


markdownBody : String -> BackendTask FatalError (List Block)
markdownBody rawBody =
    rawBody
        |> Markdown.Parser.parse
        |> Result.mapError (\_ -> FatalError.fromString "Markdown parsing error")
        |> BackendTask.fromResult
