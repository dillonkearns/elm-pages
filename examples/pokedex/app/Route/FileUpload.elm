module Route.FileUpload exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import ErrorPage exposing (ErrorPage)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ -> Request.skip "No action."
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    Maybe Request.File


type alias ActionData =
    {}


data : RouteParams -> Request.Parser (BackendTask (Server.Response.Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ Request.expectMultiPartFormPost
            (\{ field, optionalField, fileField } ->
                fileField "file"
            )
            |> Request.map
                (\file ->
                    BackendTask.succeed (Server.Response.render (Just file))
                )
        , Request.succeed
            (BackendTask.succeed (Server.Response.render Nothing))
        ]


head :
    StaticPayload Data ActionData RouteParams
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
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    { title = "File Upload"
    , body =
        [ static.data
            |> Maybe.map
                (\file ->
                    Html.div []
                        [ Html.h1 [] [ Html.text "Got file" ]
                        , Html.p [] [ Html.text file.name ]
                        ]
                )
            |> Maybe.withDefault (Html.text "No file uploaded. Choose a file to get started.")
        , Html.form [ Attr.method "POST", Attr.enctype "multipart/form-data" ]
            [ Html.input
                [ Attr.type_ "file"
                , Attr.name "file"
                ]
                []
            , Html.input
                [ Attr.type_ "submit"
                ]
                []
            ]
        ]
    }
