module Template.Documentation exposing (Model, Msg, template)

import DocSidebar
import Document exposing (Document)
import Element exposing (Element)
import Element.Events
import Element.Font as Font
import Head
import Head.Seo as Seo
import Json.Decode as Decode
import MarkdownRenderer
import Pages.ImagePath as ImagePath
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Palette
import Shared
import SiteOld
import Template exposing (StaticPayload, TemplateWithState)


type alias Documentation =
    { title : String }


type alias StaticData =
    ()


type alias Model =
    {}


type Msg
    = Increment


template : TemplateWithState {} StaticData Model Msg
template =
    Template.noStaticData
        { head = head
        , staticRoutes = StaticHttp.succeed []
        }
        |> Template.buildWithSharedState
            { view = view
            , init = init
            , update = update
            , subscriptions = \_ _ _ _ -> Sub.none
            }


init : {} -> ( Model, Cmd Msg )
init _ =
    ( {}, Cmd.none )


update : {} -> Msg -> Model -> Shared.Model -> ( Model, Cmd Msg, Maybe Shared.SharedMsg )
update _ msg model sharedModel =
    case msg of
        Increment ->
            ( model, Cmd.none, Just Shared.IncrementFromChild )


decoder : Decode.Decoder Documentation
decoder =
    Decode.map Documentation
        (Decode.field "title" Decode.string)


head : StaticPayload StaticData {} -> List Head.Tag
head staticPayload =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = ImagePath.build [ "images", "icon-png.png" ]
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = SiteOld.tagline
        , locale = Nothing
        , title = "TODO title" -- staticPayload.metadata.title -- TODO
        }
        |> Seo.website


view :
    Model
    -> Shared.Model
    -> StaticPayload StaticData {}
    -> Document Msg
view model sharedModel staticPayload =
    { title = "TODO title" -- staticPayload.metadata.title -- TODO
    , body =
        [ [ Element.row []
                [ --counterView sharedModel,
                  DocSidebar.view
                    staticPayload.path
                    -- allMetadata -- TODO
                    |> Element.el [ Element.width (Element.fillPortion 2), Element.alignTop, Element.height Element.fill ]
                , Element.column [ Element.width (Element.fillPortion 8), Element.padding 35, Element.spacing 15 ]
                    [ Palette.heading 1
                        [ Element.text "TODO title" --  Element.text staticPayload.metadata.title -- TODO
                        ]
                    , Element.column [ Element.spacing 20 ]
                        [--tocView staticPayload.path (Tuple.first rendered) -- TODO use StaticHttp to render view
                         --Element.column
                         --  [ Element.padding 50
                         --  , Element.spacing 30
                         --  , Element.Region.mainContent
                         --  ]
                         --  (Tuple.second rendered |> List.map (Element.map never))
                        ]
                    ]
                ]
          ]
            |> Element.textColumn
                [ Element.width Element.fill
                , Element.height Element.fill
                ]
        ]
    }


counterView : Shared.Model -> Element Msg
counterView sharedModel =
    Element.el [ Element.Events.onClick Increment ] (Element.text <| "Docs count: " ++ String.fromInt sharedModel.counter)


tocView : PagePath -> MarkdownRenderer.TableOfContents -> Element msg
tocView path toc =
    Element.column [ Element.alignTop, Element.spacing 20 ]
        [ Element.el [ Font.bold, Font.size 22 ] (Element.text "Table of Contents")
        , Element.column [ Element.spacing 10 ]
            (toc
                |> List.map
                    (\heading ->
                        Element.link [ Font.color (Element.rgb255 100 100 100) ]
                            { url = PagePath.toString path ++ "#" ++ heading.anchorId
                            , label = Element.text heading.name
                            }
                    )
            )
        ]
