module Route.Docs.Section__ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.File
import BackendTask.Glob as Glob exposing (Glob)
import Css
import Css.Global
import DocsSection exposing (Section)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Heroicon
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr exposing (css)
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
import Tailwind.Breakpoints as Bp
import Tailwind.Theme as Theme
import Tailwind.Utilities as Tw
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
        [ Css.Global.global
            [ Css.Global.selector ".anchor-icon"
                [ Css.opacity Css.zero
                ]
            , Css.Global.selector "h2:hover .anchor-icon"
                [ Css.opacity (Css.num 100)
                ]
            ]
        , Html.div
            [ css
                [ Tw.flex
                , Tw.flex_1
                , Tw.h_full
                ]
            ]
            [ TableOfContents.view sharedModel.showMobileMenu True app.routeParams.section app.sharedData
            , Html.article
                [ css
                    [ Tw.prose
                    , Tw.max_w_xl

                    --, Tw.whitespace_normal
                    --, Tw.mx_auto
                    , Tw.relative
                    , Tw.pt_20
                    , Tw.pb_16
                    , Tw.px_6
                    , Tw.w_full
                    , Tw.max_w_full
                    , Tw.overflow_x_hidden
                    , Bp.md
                        [ Tw.px_8
                        ]
                    ]
                ]
                [ -- Frozen content - pass fields individually so codemod can track ephemeral fields
                  View.freeze (renderStaticContent app.data.body app.data.previousAndNext app.data.editUrl)
                ]
            ]
        ]
    }


{-| Render the article content as a frozen view.
This code is eliminated from the client bundle via DCE.
-}
renderStaticContent : List Block -> ( Maybe NextPrevious.Item, Maybe NextPrevious.Item ) -> String -> Html Never
renderStaticContent body previousAndNext editUrl =
    Html.div
        [ css
            [ Tw.max_w_screen_md
            , Tw.mx_auto
            , Bp.xl [ Tw.pr_36 ]
            ]
        ]
        ((body
            |> Markdown.Renderer.render TailwindMarkdownRenderer.renderer
            |> Result.withDefault []
         )
            ++ [ NextPrevious.view previousAndNext
               , Html.hr [] []
               , Html.footer
                    [ css [ Tw.text_right ]
                    ]
                    [ Html.a
                        [ Attr.href editUrl
                        , Attr.rel "noopener"
                        , Attr.target "_blank"
                        , css
                            [ Tw.text_sm
                            , Css.hover
                                [ Tw.text_color Theme.gray_800 |> Css.important
                                ]
                            , Tw.text_color Theme.gray_500 |> Css.important
                            , Tw.flex
                            , Tw.items_center
                            , Tw.float_right
                            ]
                        ]
                        [ Html.span [ css [ Tw.pr_1 ] ] [ Html.text "Suggest an edit on GitHub" ]
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
